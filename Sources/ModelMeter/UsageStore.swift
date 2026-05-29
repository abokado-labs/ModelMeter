import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var claudeSnapshot = ClaudeUsageSnapshot()
    @Published private(set) var geminiSnapshot = GeminiUsageSnapshot()
    @Published private(set) var providerStatuses = ProviderStatusSnapshot()
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
    @Published var menuBarIconMode: MenuBarIconMode
    @Published var menuBarLabelStyle: MenuBarLabelStyle
    @Published var menuBarFontSize: MenuBarFontSize
    @Published var codexEnabled: Bool
    @Published var claudeEnabled: Bool
    @Published var geminiEnabled: Bool
    @Published var showCodexInMenuBar: Bool
    @Published var showClaudeInMenuBar: Bool
    @Published var showGeminiInMenuBar: Bool
    @Published var paceWarningsEnabled: Bool
    @Published var providerStatusWarningsEnabled: Bool

    private let settings = SettingsStore.shared
    private let reader = UsageReader()
    private let codexLiveUsageClient = CodexLiveUsageClient()
    private let codexAppServerClient = CodexAppServerClient()
    private let claudeClient = ClaudeUsageClient()
    private let geminiClient = GeminiUsageClient()
    private let providerStatusClient = ProviderStatusClient()
    private var timer: Timer?
    private var providerStatusTimer: Timer?
    private var lastNotificationStatus: UsageStatus = .unknown
    private var hasStarted = false
    private var isRefreshingCodex = false
    private var isRefreshingProviderStatuses = false

    init() {
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
        menuBarIconMode = settings.menuBarIconMode
        menuBarLabelStyle = settings.menuBarLabelStyle
        menuBarFontSize = settings.menuBarFontSize
        codexEnabled = settings.codexEnabled
        claudeEnabled = settings.claudeEnabled
        geminiEnabled = settings.geminiEnabled
        showCodexInMenuBar = settings.showCodexInMenuBar
        showClaudeInMenuBar = settings.showClaudeInMenuBar
        showGeminiInMenuBar = settings.showGeminiInMenuBar
        paceWarningsEnabled = settings.paceWarningsEnabled
        providerStatusWarningsEnabled = settings.providerStatusWarningsEnabled
    }

    var menuTitle: String {
        var parts: [String] = []
        if codexEnabled && showCodexInMenuBar {
            parts.append(menuBarMetric.value(from: snapshot).map { "C \(UsageMath.wholePercent($0))" } ?? "C --")
        }
        if claudeEnabled && showClaudeInMenuBar {
            parts.append(menuBarMetric.value(from: claudeSnapshot).map { "Cl \(UsageMath.wholePercent($0))" } ?? "Cl --")
        }
        if geminiEnabled && showGeminiInMenuBar {
            parts.append(menuBarMetric.value(from: geminiSnapshot).map { "G \(UsageMath.wholePercent($0))" } ?? "G --")
        }
        return parts.isEmpty ? "LLM" : parts.joined(separator: "  ")
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
        let reader = reader
        let codexLiveUsageClient = codexLiveUsageClient

        Task.detached(priority: .utility) {
            let result = Result {
                AppLog.codex.info("Codex refresh source selected: \(codexDataSource.title, privacy: .public)")

                switch codexDataSource {
                case .liveOAuth:
                    var liveSnapshot = UsageSnapshot(updatedAt: Date())
                    do {
                        let liveRateLimits = try codexLiveUsageClient.loadRateLimits(codexHome: codexHome)
                        liveSnapshot.rateLimits = liveRateLimits
                        liveSnapshot.updatedAt = Date()
                        liveSnapshot.errorMessage = nil
                        AppLog.codex.info("Codex refresh using live OAuth source")
                        return liveSnapshot
                    } catch {
                        AppLog.codex.error("Codex live OAuth refresh failed: \(error.localizedDescription, privacy: .public)")
                        liveSnapshot.rateLimits = nil
                        liveSnapshot.updatedAt = Date()
                        liveSnapshot.errorMessage = "Live Codex refresh failed. Switch Codex data source to Local Codex files to use the fallback route. Check Xcode logs for ModelMeter/Codex."
                        return liveSnapshot
                    }

                case .localFiles:
                    AppLog.codex.info("Codex local file refresh starting")
                    var fullSnapshot = (try? reader.loadSnapshot(codexHome: codexHome)) ?? UsageSnapshot(updatedAt: Date())
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
                    return fullSnapshot
                }
            }
            await MainActor.run {
                self.isRefreshingCodex = false
                switch result {
                case .success(let fullSnapshot):
                    self.snapshot = fullSnapshot
                    self.notifyIfNeeded(fullSnapshot)
                    AppLog.codex.info("Codex refresh finished; source=\(fullSnapshot.rateLimits?.sourceLabel ?? "none", privacy: .public); error=\(fullSnapshot.errorMessage ?? "none", privacy: .public)")
                case .failure(let error):
                    var current = self.snapshot
                    current.errorMessage = error.localizedDescription
                    current.updatedAt = Date()
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
        claudeSessionKey = ""
        claudeCfClearance = ""
        claudeSnapshot = ClaudeUsageSnapshot(
            updatedAt: Date(),
            errorMessage: status == errSecSuccess ? nil : "Could not clear Claude credentials from Keychain: \(KeychainStore.statusDescription(status))"
        )
    }

    func resetGeminiCredentials() {
        Task { await GeminiWebSession.shared.clearSession() }
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
        settings.menuBarIconMode = menuBarIconMode
        settings.menuBarLabelStyle = menuBarLabelStyle
        settings.menuBarFontSize = menuBarFontSize
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
        AppLog.gemini.info("Gemini refresh queued")
        do {
            geminiSnapshot = try await geminiClient.fetch()
            AppLog.gemini.info("Gemini refresh finished; error=none")
        } catch {
            if !geminiSnapshot.items.isEmpty {
                geminiSnapshot = GeminiUsageSnapshot(
                    items: geminiSnapshot.items,
                    updatedAt: geminiSnapshot.updatedAt,
                    errorMessage: error.localizedDescription
                )
                AppLog.gemini.error("Gemini refresh failed; preserving current snapshot; error=\(error.localizedDescription, privacy: .public)")
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
        persistSettings()
    }

    private func refreshClaude() async {
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
            AppLog.claude.info("Claude refresh finished; error=none")
        } catch {
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription)
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
