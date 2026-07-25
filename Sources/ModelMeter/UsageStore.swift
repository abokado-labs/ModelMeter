import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var claudeSnapshot = ClaudeUsageSnapshot()
    @Published private(set) var geminiSnapshot = GeminiUsageSnapshot()
    @Published private(set) var providerStatuses = ProviderStatusSnapshot()
    @Published private(set) var history: [UsageHistoryEntry]
    @Published var codexHome: String
    @Published var codexDataSource: CodexDataSource
    @Published var claudeOrganizationID: String
    @Published var claudeSessionKey: String
    @Published var claudeCfClearance: String
    @Published var geminiCookieHeader: String
    @Published var sessionLimit: Int
    @Published var dailyLimit: Int
    @Published var weeklyLimit: Int
    @Published var refreshInterval: Double
    @Published var notificationsEnabled: Bool
    @Published var notificationThreshold: Double
    @Published var menuBarMetric: MenuBarMetric
    @Published var menuBarDisplayMode: MenuBarDisplayMode
    @Published var menuBarIconMode: MenuBarIconMode
    @Published var menuBarLabelStyle: MenuBarLabelStyle
    @Published var menuBarFontSize: MenuBarFontSize
    @Published var resetDisplayMode: ResetDisplayMode
    @Published var showHistoryGraph: Bool
    @Published var showCodexInHistoryGraph: Bool
    @Published var showClaudeInHistoryGraph: Bool
    @Published var showGeminiInHistoryGraph: Bool
    @Published var shadeHistoryGraphArea: Bool
    @Published var historyGraphPosition: HistoryGraphPosition
    @Published var codexEnabled: Bool
    @Published var claudeEnabled: Bool
    @Published var geminiEnabled: Bool
    @Published var showCodexInMenuBar: Bool
    @Published var showClaudeInMenuBar: Bool
    @Published var showGeminiInMenuBar: Bool
    @Published var paceWarningsEnabled: Bool
    @Published var providerStatusWarningsEnabled: Bool

    private let settings = SettingsStore.shared
    private let codexRefreshPlan: CodexRefreshPlan
    private let claudeClient = ClaudeUsageClient()
    private let geminiClient = GeminiUsageClient()
    private let providerStatusClient = ProviderStatusClient()
    private var timer: Timer?
    private var providerStatusTimer: Timer?
    private var lastNotificationStatus: UsageStatus = .unknown
    private var hasStarted = false
    private var isRefreshingCodex = false
    private var isRefreshingClaude = false
    private var isRefreshingGemini = false
    private var isRefreshingProviderStatuses = false

    init(codexRefreshPlan: CodexRefreshPlan = .live()) {
        self.codexRefreshPlan = codexRefreshPlan
        codexHome = settings.codexHome
        codexDataSource = settings.codexDataSource
        claudeOrganizationID = settings.claudeOrganizationID
        claudeSessionKey = ""
        claudeCfClearance = ""
        geminiCookieHeader = ""
        sessionLimit = settings.sessionLimit
        dailyLimit = settings.dailyLimit
        weeklyLimit = settings.weeklyLimit
        refreshInterval = settings.refreshInterval
        notificationsEnabled = settings.notificationsEnabled
        notificationThreshold = settings.notificationThreshold
        menuBarMetric = settings.menuBarMetric
        menuBarDisplayMode = settings.menuBarDisplayMode
        menuBarIconMode = settings.menuBarIconMode
        menuBarLabelStyle = settings.menuBarLabelStyle
        menuBarFontSize = settings.menuBarFontSize
        resetDisplayMode = settings.resetDisplayMode
        showHistoryGraph = settings.showHistoryGraph
        showCodexInHistoryGraph = settings.showCodexInHistoryGraph
        showClaudeInHistoryGraph = settings.showClaudeInHistoryGraph
        showGeminiInHistoryGraph = settings.showGeminiInHistoryGraph
        shadeHistoryGraphArea = settings.shadeHistoryGraphArea
        historyGraphPosition = settings.historyGraphPosition
        codexEnabled = settings.codexEnabled
        claudeEnabled = settings.claudeEnabled
        geminiEnabled = settings.geminiEnabled
        showCodexInMenuBar = settings.showCodexInMenuBar
        showClaudeInMenuBar = settings.showClaudeInMenuBar
        showGeminiInMenuBar = settings.showGeminiInMenuBar
        paceWarningsEnabled = settings.paceWarningsEnabled
        providerStatusWarningsEnabled = settings.providerStatusWarningsEnabled
        history = UsageHistoryStore.load()
    }

    var menuTitle: String {
        switch menuBarDisplayMode {
        case .allProviders:
            return menuTitleParts().map(\.text).joined(separator: "  ").ifEmpty("MM")
        case .lowestAvailable:
            return lowestAvailableMenuTitlePart()?.text ?? "MM"
        case .warningsOnly:
            return menuTitleParts().filter(\.warning).map(\.text).joined(separator: "  ").ifEmpty("OK")
        case .iconOnly:
            return "Icon only"
        }
    }

    private func menuTitleParts() -> [MenuTitlePart] {
        var result: [MenuTitlePart] = []
        if codexEnabled && showCodexInMenuBar {
            result.append(MenuTitlePart(provider: .codex, label: "C", value: menuBarMetric.value(from: snapshot), warning: codexMenuMetricAheadOfPace || codexMenuStatusWarning))
        }
        if claudeEnabled && showClaudeInMenuBar {
            result.append(MenuTitlePart(provider: .claude, label: "Cl", value: menuBarMetric.value(from: claudeSnapshot), warning: claudeMenuMetricAheadOfPace || claudeMenuStatusWarning))
        }
        if geminiEnabled && showGeminiInMenuBar {
            result.append(MenuTitlePart(provider: .gemini, label: "G", value: menuBarMetric.value(from: geminiSnapshot), warning: geminiMenuMetricAheadOfPace || geminiMenuStatusWarning))
        }
        return result
    }

    private func lowestAvailableMenuTitlePart() -> MenuTitlePart? {
        let metric: MenuBarMetric
        switch menuBarMetric {
        case .fiveHourUsed, .fiveHourAvailable:
            metric = .fiveHourAvailable
        case .sevenDayUsed, .sevenDayAvailable:
            metric = .sevenDayAvailable
        }

        return menuTitleParts()
            .compactMap { part -> (part: MenuTitlePart, value: Double)? in
                let value: Double?
                switch part.provider {
                case .codex:
                    value = metric.value(from: snapshot)
                case .claude:
                    value = metric.value(from: claudeSnapshot)
                case .gemini:
                    value = metric.value(from: geminiSnapshot)
                }
                guard let value else { return nil }
                return (MenuTitlePart(provider: part.provider, label: part.label, value: value, warning: part.warning), value)
            }
            .min { $0.value < $1.value }?
            .part
    }

    var codexMenuMetricAheadOfPace: Bool {
        guard paceWarningsEnabled, let window = menuBarMetric.codexWindow(from: snapshot) else { return false }
        return window.isAheadOfPace
    }

    var codexMenuStatusWarning: Bool {
        providerStatusWarningsEnabled && providerStatuses.codex.hasIssue
    }

    var claudeMenuMetricAheadOfPace: Bool {
        guard paceWarningsEnabled, let window = menuBarMetric.claudeWindow(from: claudeSnapshot) else { return false }
        return window.isAheadOfPace
    }

    var claudeMenuStatusWarning: Bool {
        providerStatusWarningsEnabled && providerStatuses.claude.hasIssue
    }

    var geminiMenuMetricAheadOfPace: Bool { false }

    var geminiMenuStatusWarning: Bool {
        providerStatusWarningsEnabled && providerStatuses.gemini.hasIssue
    }

    var historyGraphProviders: [ProviderKind] {
        var providers: [ProviderKind] = []
        if codexEnabled && showCodexInHistoryGraph {
            providers.append(.codex)
        }
        if claudeEnabled && showClaudeInHistoryGraph {
            providers.append(.claude)
        }
        if geminiEnabled && showGeminiInHistoryGraph {
            providers.append(.gemini)
        }
        return providers
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleTimer()
        scheduleProviderStatusTimer()
        refresh()
        refreshProviderStatuses()
    }

    func refresh() {
        if codexEnabled {
            refreshCodexAsync()
        }

        if claudeEnabled && !claudeOrganizationID.isEmpty {
            Task {
                await refreshClaude()
            }
        }

        if geminiEnabled {
            Task {
                await refreshGemini()
            }
        }
    }

    private func refreshCodexAsync() {
        guard !isRefreshingCodex else {
            AppLog.codex.info("Codex refresh skipped because one is already running")
            return
        }
        AppLog.codex.info("Codex refresh queued")
        isRefreshingCodex = true
        let codexHome = codexHome
        let codexDataSource = codexDataSource
        let codexRefreshPlan = codexRefreshPlan

        Task.detached(priority: .utility) {
            let result = Result {
                AppLog.codex.info("Codex refresh source selected: \(codexDataSource.title, privacy: .public)")
                return try codexRefreshPlan.loadSnapshot(codexHome: codexHome, dataSource: codexDataSource)
            }
            await MainActor.run {
                self.isRefreshingCodex = false
                switch result {
                case .success(let fullSnapshot):
                    if let rateLimits = fullSnapshot.rateLimits, fullSnapshot.errorMessage == nil {
                        LastGoodUsageCache.saveCodexRateLimits(rateLimits)
                        self.recordHistory(
                            UsageHistoryEntry(
                                provider: .codex,
                                capturedAt: rateLimits.capturedAt,
                                primaryUsedPercent: rateLimits.primary?.usedPercent,
                                primaryRemainingPercent: rateLimits.primary?.remainingPercent,
                                secondaryUsedPercent: rateLimits.secondary?.usedPercent,
                                secondaryRemainingPercent: rateLimits.secondary?.remainingPercent,
                                sourceLabel: rateLimits.sourceLabel
                            )
                        )
                    }
                    self.snapshot = fullSnapshot
                    self.notifyIfNeeded(fullSnapshot)
                    AppLog.codex.info("Codex refresh finished; source=\(fullSnapshot.rateLimits?.sourceLabel ?? "none", privacy: .public); error=\(fullSnapshot.errorMessage ?? "none", privacy: .public)")
                case .failure(let error):
                    var current = self.snapshot
                    current.errorMessage = error.localizedDescription
                    current.updatedAt = Date()
                    if current.rateLimits == nil, let cached = LastGoodUsageCache.loadCodexRateLimits() {
                        current.rateLimits = cached
                        current.updatedAt = cached.capturedAt
                        current.errorMessage = error.localizedDescription + " Showing the last good Codex reading."
                    }
                    self.snapshot = current
                    AppLog.codex.error("Codex refresh crashed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func saveSettings() {
        persistSettings()
        refresh()
        scheduleTimer()
    }

    func resetClaudeCredentials() {
        let status = KeychainStore.clearClaudeCredentials()
        LastGoodUsageCache.clearClaudeSnapshot()
        claudeSessionKey = ""
        claudeCfClearance = ""
        claudeSnapshot = ClaudeUsageSnapshot(
            updatedAt: Date(),
            errorMessage: status == errSecSuccess ? nil : "Could not clear Claude credentials from Keychain: \(KeychainStore.statusDescription(status))"
        )
    }

    func resetGeminiCredentials() {
        Task { await GeminiWebSession.shared.clearSession() }
        LastGoodUsageCache.clearGeminiSnapshot()
        geminiCookieHeader = ""
        geminiSnapshot = GeminiUsageSnapshot(updatedAt: Date())
    }

    private func persistSettings() {
        settings.codexHome = codexHome
        settings.codexDataSource = codexDataSource
        settings.claudeOrganizationID = claudeOrganizationID
        if !claudeSessionKey.isEmpty || !claudeCfClearance.isEmpty {
            let credentialsStatus = KeychainStore.writeClaudeCredentials(
                KeychainStore.ClaudeCredentials(sessionKey: claudeSessionKey, cfClearance: claudeCfClearance)
            )
            if credentialsStatus != errSecSuccess {
                claudeSnapshot = ClaudeUsageSnapshot(
                    updatedAt: Date(),
                    errorMessage: "Could not save Claude credentials to Keychain: \(KeychainStore.statusDescription(credentialsStatus))"
                )
            }
        }
        settings.sessionLimit = sessionLimit
        settings.dailyLimit = dailyLimit
        settings.weeklyLimit = weeklyLimit
        settings.refreshInterval = refreshInterval
        settings.notificationsEnabled = notificationsEnabled
        settings.notificationThreshold = notificationThreshold
        settings.menuBarMetric = menuBarMetric
        settings.menuBarDisplayMode = menuBarDisplayMode
        settings.menuBarIconMode = menuBarIconMode
        settings.menuBarLabelStyle = menuBarLabelStyle
        settings.menuBarFontSize = menuBarFontSize
        settings.resetDisplayMode = resetDisplayMode
        settings.showHistoryGraph = showHistoryGraph
        settings.showCodexInHistoryGraph = showCodexInHistoryGraph
        settings.showClaudeInHistoryGraph = showClaudeInHistoryGraph
        settings.showGeminiInHistoryGraph = showGeminiInHistoryGraph
        settings.shadeHistoryGraphArea = shadeHistoryGraphArea
        settings.historyGraphPosition = historyGraphPosition
        settings.codexEnabled = codexEnabled
        settings.claudeEnabled = claudeEnabled
        settings.geminiEnabled = geminiEnabled
        settings.showCodexInMenuBar = showCodexInMenuBar
        settings.showClaudeInMenuBar = showClaudeInMenuBar
        settings.showGeminiInMenuBar = showGeminiInMenuBar
        settings.paceWarningsEnabled = paceWarningsEnabled
        settings.providerStatusWarningsEnabled = providerStatusWarningsEnabled
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(refreshInterval, 5), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func scheduleProviderStatusTimer() {
        providerStatusTimer?.invalidate()
        providerStatusTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProviderStatuses()
            }
        }
    }

    func refreshProviderStatuses() {
        guard providerStatusWarningsEnabled else { return }
        guard !isRefreshingProviderStatuses else {
            AppLog.status.info("Provider status refresh skipped because one is already running")
            return
        }
        isRefreshingProviderStatuses = true
        AppLog.status.info("Provider status refresh queued")
        Task {
            let snapshot = await providerStatusClient.fetchAll()
            providerStatuses = snapshot
            isRefreshingProviderStatuses = false
            let issue = snapshot.mostSevereIssue.map { "\($0.provider.rawValue): \($0.severity.title)" } ?? "none"
            AppLog.status.info("Provider status refresh finished; issue=\(issue, privacy: .public)")
        }
    }

    private func notifyIfNeeded(_ snapshot: UsageSnapshot) {
        guard notificationsEnabled else { return }
        let progress = max(snapshot.sessionProgress, snapshot.weeklyProgress)
        guard progress >= notificationThreshold else {
            lastNotificationStatus = snapshot.status
            return
        }
        guard lastNotificationStatus != snapshot.status else { return }
        lastNotificationStatus = snapshot.status
        NotificationManager.shared.send(
            title: "Codex usage \(UsageMath.percent(progress))",
            body: "Codex reports \(UsageMath.wholePercent(100 - (progress * 100))) remaining in the most constrained window."
        )
    }


    private func refreshGemini() async {
        guard !isRefreshingGemini else {
            AppLog.gemini.info("Gemini refresh skipped because one is already running")
            return
        }
        isRefreshingGemini = true
        defer { isRefreshingGemini = false }

        AppLog.gemini.info("Gemini refresh queued")
        do {
            geminiSnapshot = try await geminiClient.fetch()
            LastGoodUsageCache.saveGeminiSnapshot(geminiSnapshot)
            recordGeminiHistoryIfAvailable(sourceLabel: "Gemini usage page")
            AppLog.gemini.info("Gemini refresh finished; error=none")
        } catch {
            if !geminiSnapshot.items.isEmpty {
                LastGoodUsageCache.saveGeminiSnapshot(geminiSnapshot)
                geminiSnapshot = GeminiUsageSnapshot(
                    items: geminiSnapshot.items,
                    updatedAt: geminiSnapshot.updatedAt,
                    errorMessage: error.localizedDescription
                )
                AppLog.gemini.error("Gemini refresh failed; preserving current snapshot; error=\(error.localizedDescription, privacy: .public)")
            } else if var cached = LastGoodUsageCache.loadGeminiSnapshot() {
                cached.errorMessage = error.localizedDescription + " Showing the last good Gemini reading."
                geminiSnapshot = cached
                AppLog.gemini.error("Gemini refresh failed; using cached snapshot; error=\(error.localizedDescription, privacy: .public)")
            } else {
                geminiSnapshot = GeminiUsageSnapshot(
                    updatedAt: Date(),
                    errorMessage: error.localizedDescription
                )
                AppLog.gemini.error("Gemini refresh failed with no usable snapshot; error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func refreshGeminiNow() {
        Task { await refreshGemini() }
    }

    func completeGeminiSignIn(snapshot: GeminiUsageSnapshot) async {
        geminiCookieHeader = ""
        geminiEnabled = true
        showGeminiInMenuBar = true
        geminiSnapshot = snapshot
        LastGoodUsageCache.saveGeminiSnapshot(snapshot)
        recordGeminiHistoryIfAvailable(sourceLabel: "Gemini usage page")
        persistSettings()
    }

    private func refreshClaude() async {
        guard !isRefreshingClaude else {
            AppLog.claude.info("Claude refresh skipped because one is already running")
            return
        }
        isRefreshingClaude = true
        defer { isRefreshingClaude = false }

        AppLog.claude.info("Claude refresh queued; configuredOrganization=\((!self.claudeOrganizationID.isEmpty), privacy: .public)")
        let credentials = loadedClaudeCredentials()
        guard !credentials.sessionKey.isEmpty else {
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: "Claude credentials are not available. Sign in again from settings.")
            AppLog.claude.error("Claude refresh failed; no session key available")
            return
        }

        do {
            let result = try await claudeClient.fetch(
                organizationID: claudeOrganizationID,
                sessionKey: credentials.sessionKey,
                cfClearance: credentials.cfClearance
            )
            claudeSnapshot = result
            LastGoodUsageCache.saveClaudeSnapshot(result)
            recordHistory(
                UsageHistoryEntry(
                    provider: .claude,
                    capturedAt: result.updatedAt ?? Date(),
                    primaryUsedPercent: result.rateLimits?.session.usedPercent,
                    primaryRemainingPercent: result.rateLimits?.session.remainingPercent,
                    secondaryUsedPercent: result.rateLimits?.weekly.usedPercent,
                    secondaryRemainingPercent: result.rateLimits?.weekly.remainingPercent,
                    sourceLabel: "Authenticated Claude usage"
                )
            )
            AppLog.claude.info("Claude refresh finished; error=none")
        } catch {
            if var cached = LastGoodUsageCache.loadClaudeSnapshot() {
                cached.errorMessage = error.localizedDescription + " Showing the last good Claude reading."
                claudeSnapshot = cached
            } else {
                claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription)
            }
            AppLog.claude.error("Claude refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadedClaudeCredentials() -> KeychainStore.ClaudeCredentials {
        if !claudeSessionKey.isEmpty || !claudeCfClearance.isEmpty {
            return KeychainStore.ClaudeCredentials(sessionKey: claudeSessionKey, cfClearance: claudeCfClearance)
        }
        let credentials = KeychainStore.readClaudeCredentials(allowPrompt: false)
        claudeSessionKey = credentials.sessionKey
        claudeCfClearance = credentials.cfClearance
        return credentials
    }

    private func recordGeminiHistoryIfAvailable(sourceLabel: String) {
        guard !geminiSnapshot.items.isEmpty else { return }
        recordHistory(
            UsageHistoryEntry(
                provider: .gemini,
                capturedAt: geminiSnapshot.updatedAt ?? Date(),
                primaryUsedPercent: geminiSnapshot.primaryItem?.usedPercent,
                primaryRemainingPercent: geminiSnapshot.primaryItem?.remainingPercent,
                secondaryUsedPercent: geminiSnapshot.weeklyItem?.usedPercent,
                secondaryRemainingPercent: geminiSnapshot.weeklyItem?.remainingPercent,
                sourceLabel: sourceLabel
            )
        )
    }

    private func recordHistory(_ entry: UsageHistoryEntry) {
        guard entry.primaryUsedPercent != nil || entry.secondaryUsedPercent != nil else { return }
        history = UsageHistoryStore.append(entry, to: history)
    }

    func completeClaudeSignIn(sessionKey: String, cfClearance: String, organizationID: String?) async {
        claudeSessionKey = sessionKey
        claudeCfClearance = cfClearance
        do {
            if let organizationID, !organizationID.isEmpty {
                claudeOrganizationID = organizationID
            } else {
                claudeOrganizationID = try await claudeClient.discoverOrganizationID(
                    sessionKey: sessionKey,
                    cfClearance: cfClearance
                )
            }
            saveSettings()
            await refreshClaude()
        } catch {
            let credentialsStatus = KeychainStore.writeClaudeCredentials(
                KeychainStore.ClaudeCredentials(sessionKey: sessionKey, cfClearance: cfClearance)
            )
            let keychainMessage = credentialsStatus == errSecSuccess
                ? ""
                : " Keychain save failed: \(KeychainStore.statusDescription(credentialsStatus))"
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription + keychainMessage)
        }
    }
}

private enum LastGoodUsageCache {
    private static let codexRateLimitsKey = "lastGoodCodexRateLimits"
    private static let claudeSnapshotKey = "lastGoodClaudeSnapshot"
    private static let geminiSnapshotKey = "lastGoodGeminiSnapshot"

    private struct ClaudePayload: Codable {
        let rateLimits: ClaudeRateLimits
        let updatedAt: Date
    }

    private struct GeminiPayload: Codable {
        let items: [GeminiUsageItem]
        let updatedAt: Date
        let accountEmail: String?
        let accountPlan: String?
    }

    static func saveCodexRateLimits(_ rateLimits: CodexRateLimits) {
        guard let data = try? JSONEncoder().encode(rateLimits) else { return }
        UserDefaults.standard.set(data, forKey: codexRateLimitsKey)
    }

    static func loadCodexRateLimits() -> CodexRateLimits? {
        guard let data = UserDefaults.standard.data(forKey: codexRateLimitsKey) else { return nil }
        return try? JSONDecoder().decode(CodexRateLimits.self, from: data)
    }

    static func saveClaudeSnapshot(_ snapshot: ClaudeUsageSnapshot) {
        guard let rateLimits = snapshot.rateLimits else { return }
        let payload = ClaudePayload(rateLimits: rateLimits, updatedAt: snapshot.updatedAt ?? Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: claudeSnapshotKey)
    }

    static func loadClaudeSnapshot() -> ClaudeUsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: claudeSnapshotKey),
              let payload = try? JSONDecoder().decode(ClaudePayload.self, from: data) else {
            return nil
        }
        return ClaudeUsageSnapshot(
            rateLimits: payload.rateLimits,
            updatedAt: payload.updatedAt,
            errorMessage: nil
        )
    }

    static func clearClaudeSnapshot() {
        UserDefaults.standard.removeObject(forKey: claudeSnapshotKey)
    }

    static func saveGeminiSnapshot(_ snapshot: GeminiUsageSnapshot) {
        guard !snapshot.items.isEmpty else { return }
        let payload = GeminiPayload(
            items: snapshot.items,
            updatedAt: snapshot.updatedAt ?? Date(),
            accountEmail: snapshot.accountEmail,
            accountPlan: snapshot.accountPlan
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: geminiSnapshotKey)
    }

    static func loadGeminiSnapshot() -> GeminiUsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: geminiSnapshotKey),
              let payload = try? JSONDecoder().decode(GeminiPayload.self, from: data),
              !payload.items.isEmpty else {
            return nil
        }
        return GeminiUsageSnapshot(
            items: payload.items,
            updatedAt: payload.updatedAt,
            errorMessage: nil,
            accountEmail: payload.accountEmail,
            accountPlan: payload.accountPlan
        )
    }

    static func clearGeminiSnapshot() {
        UserDefaults.standard.removeObject(forKey: geminiSnapshotKey)
    }
}

enum UsageHistoryStore {
    private static let key = "usageHistoryEntries"
    static let graphSamplingInterval: TimeInterval = 15 * 60
    static let gapDisplayThreshold: TimeInterval = 30 * 60
    private static let meaningfulPercentChange = 1.0
    private static let maximumAge: TimeInterval = 8 * 24 * 60 * 60
    private static let maximumEntries = 10_000

    static func load(now: Date = Date(), defaults: UserDefaults = .standard) -> [UsageHistoryEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([UsageHistoryEntry].self, from: data) else {
            return []
        }
        let loaded = prune(coalesced(entries, now: now), now: now)
        if loaded != entries {
            save(loaded, defaults: defaults)
        }
        return loaded
    }

    static func append(_ entry: UsageHistoryEntry, to entries: [UsageHistoryEntry], now: Date = Date(), defaults: UserDefaults = .standard) -> [UsageHistoryEntry] {
        var candidate = entries
        candidate.append(entry)
        let next = prune(coalesced(candidate, now: now), now: now)
        if next != entries {
            save(next, defaults: defaults)
        }
        return next
    }

    static func coalesced(_ entries: [UsageHistoryEntry], now: Date = Date()) -> [UsageHistoryEntry] {
        let cutoff = now.addingTimeInterval(-maximumAge)
        let sorted = entries
            .filter { $0.capturedAt >= cutoff }
            .sorted { $0.capturedAt < $1.capturedAt }
        var keptByProvider: [ProviderKind: [UsageHistoryEntry]] = [:]

        for entry in sorted {
            guard entry.primaryUsedPercent != nil || entry.secondaryUsedPercent != nil else { continue }
            let last = keptByProvider[entry.provider]?.last
            guard shouldStore(entry, after: last) else { continue }
            keptByProvider[entry.provider, default: []].append(entry)
        }

        return keptByProvider
            .values
            .flatMap { $0 }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private static func shouldStore(_ entry: UsageHistoryEntry, after previous: UsageHistoryEntry?) -> Bool {
        guard let previous else { return true }
        if isNearExactDuplicate(entry, of: previous) {
            return false
        }
        if hasMeaningfulChange(from: previous, to: entry) {
            return true
        }
        return entry.capturedAt.timeIntervalSince(previous.capturedAt) >= graphSamplingInterval
    }

    private static func isNearExactDuplicate(_ entry: UsageHistoryEntry, of previous: UsageHistoryEntry) -> Bool {
        entry.provider == previous.provider
            && abs(entry.capturedAt.timeIntervalSince(previous.capturedAt)) < 2
            && entry.primaryUsedPercent == previous.primaryUsedPercent
            && entry.secondaryUsedPercent == previous.secondaryUsedPercent
    }

    private static func hasMeaningfulChange(from previous: UsageHistoryEntry, to entry: UsageHistoryEntry) -> Bool {
        let primaryDelta = percentDelta(previous.primaryUsedPercent, entry.primaryUsedPercent)
        let secondaryDelta = percentDelta(previous.secondaryUsedPercent, entry.secondaryUsedPercent)
        return max(primaryDelta, secondaryDelta) >= meaningfulPercentChange
    }

    private static func percentDelta(_ previous: Double?, _ current: Double?) -> Double {
        guard let previous, let current else { return 0 }
        return abs(current - previous)
    }

    private static func prune(_ entries: [UsageHistoryEntry], now: Date) -> [UsageHistoryEntry] {
        let cutoff = now.addingTimeInterval(-maximumAge)
        return Array(
            entries
                .filter { $0.capturedAt >= cutoff }
                .sorted { $0.capturedAt < $1.capturedAt }
                .suffix(maximumEntries)
        )
    }

    private static func save(_ entries: [UsageHistoryEntry], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

private struct MenuTitlePart {
    let provider: ProviderKind
    let label: String
    let value: Double?
    let warning: Bool

    var text: String {
        "\(label)\(warning ? "!" : "") \(value.map { UsageMath.wholePercent($0) } ?? "--")"
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

struct CodexRefreshPlan: Sendable {
    let loadAppServerRateLimits: @Sendable () throws -> CodexRateLimits
    let loadOAuthRateLimits: @Sendable (_ codexHome: String) throws -> CodexRateLimits
    let loadLocalSnapshot: @Sendable (_ codexHome: String) throws -> UsageSnapshot
    let loadCachedRateLimits: @Sendable () -> CodexRateLimits?

    static func live() -> CodexRefreshPlan {
        let appServerClient = CodexAppServerClient()
        let oauthClient = CodexLiveUsageClient()
        let reader = UsageReader()
        return CodexRefreshPlan(
            loadAppServerRateLimits: { try appServerClient.loadRateLimits() },
            loadOAuthRateLimits: { codexHome in try oauthClient.loadRateLimits(codexHome: codexHome) },
            loadLocalSnapshot: { codexHome in try reader.loadSnapshot(codexHome: codexHome) },
            loadCachedRateLimits: { LastGoodUsageCache.loadCodexRateLimits() }
        )
    }

    func loadSnapshot(codexHome: String, dataSource: CodexDataSource) throws -> UsageSnapshot {
        switch dataSource {
        case .liveOAuth:
            return loadLiveSnapshot(codexHome: codexHome)
        case .localFiles:
            return loadLocalFileSnapshot(codexHome: codexHome)
        }
    }

    private func loadLiveSnapshot(codexHome: String) -> UsageSnapshot {
        var liveSnapshot = UsageSnapshot(updatedAt: Date())
        var failures: [String] = []

        do {
            let liveRateLimits = try loadAppServerRateLimits()
            liveSnapshot.rateLimits = liveRateLimits
            liveSnapshot.updatedAt = liveRateLimits.capturedAt
            liveSnapshot.errorMessage = nil
            AppLog.codex.info("Codex refresh using app-server live source")
            return liveSnapshot
        } catch {
            failures.append("Codex app-server: \(error.localizedDescription)")
            AppLog.codex.warning("Codex app-server refresh failed; trying OAuth fallback: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let liveRateLimits = try loadOAuthRateLimits(codexHome)
            liveSnapshot.rateLimits = liveRateLimits
            liveSnapshot.updatedAt = liveRateLimits.capturedAt
            liveSnapshot.errorMessage = nil
            AppLog.codex.info("Codex refresh using live OAuth fallback")
            return liveSnapshot
        } catch {
            failures.append("ChatGPT OAuth: \(error.localizedDescription)")
            AppLog.codex.error("Codex live OAuth refresh failed: \(error.localizedDescription, privacy: .public)")
        }

        if let cached = loadCachedRateLimits() {
            liveSnapshot.rateLimits = cached
            liveSnapshot.updatedAt = cached.capturedAt
            liveSnapshot.errorMessage = "Live Codex refresh failed. Showing the last good Codex reading."
        } else {
            liveSnapshot.rateLimits = nil
            liveSnapshot.updatedAt = Date()
            liveSnapshot.errorMessage = "Live Codex refresh failed. Switch Codex data source to Local Codex files to use the fallback route. Check Xcode logs for ModelMeter/Codex."
        }
        AppLog.codex.error("All live Codex refresh routes failed: \(failures.joined(separator: " | "), privacy: .public)")
        return liveSnapshot
    }

    private func loadLocalFileSnapshot(codexHome: String) -> UsageSnapshot {
        AppLog.codex.info("Codex local file refresh starting")
        var fullSnapshot = (try? loadLocalSnapshot(codexHome)) ?? UsageSnapshot(updatedAt: Date())
        let localSource = fullSnapshot.rateLimits?.sourceLabel ?? "none"
        AppLog.codex.info("Codex local files loaded; source=\(localSource, privacy: .public); hasRateLimits=\((fullSnapshot.rateLimits != nil), privacy: .public)")
        fullSnapshot.updatedAt = fullSnapshot.rateLimits?.capturedAt ?? fullSnapshot.updatedAt ?? Date()
        if let local = fullSnapshot.rateLimits, local.isLikelyPlaceholder {
            fullSnapshot.rateLimits = nil
            fullSnapshot.errorMessage = "Local Codex files contain only placeholder balance data. Switch Codex data source to Live ChatGPT for current balances."
        } else if fullSnapshot.rateLimits == nil {
            fullSnapshot.errorMessage = "No Codex rate-limit balances found in local files."
        } else {
            fullSnapshot.errorMessage = nil
        }
        if fullSnapshot.rateLimits == nil, let cached = loadCachedRateLimits() {
            fullSnapshot.rateLimits = cached
            fullSnapshot.updatedAt = cached.capturedAt
            fullSnapshot.errorMessage = (fullSnapshot.errorMessage ?? "Codex local file refresh failed.") + " Showing the last good Codex reading."
        }
        return fullSnapshot
    }
}
