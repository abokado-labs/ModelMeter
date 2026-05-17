import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var claudeSnapshot = ClaudeUsageSnapshot()
    @Published var codexHome: String
    @Published var claudeOrganizationID: String
    @Published var claudeSessionKey: String
    @Published var claudeCfClearance: String
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
    @Published var showCodexInMenuBar: Bool
    @Published var showClaudeInMenuBar: Bool
    @Published var paceWarningsEnabled: Bool

    private let settings = SettingsStore.shared
    private let reader = UsageReader()
    private let claudeClient = ClaudeUsageClient()
    private var timer: Timer?
    private var lastNotificationStatus: UsageStatus = .unknown
    private var hasStarted = false
    private var isRefreshingCodex = false

    init() {
        codexHome = settings.codexHome
        claudeOrganizationID = settings.claudeOrganizationID
        claudeSessionKey = ""
        claudeCfClearance = ""
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
        showCodexInMenuBar = settings.showCodexInMenuBar
        showClaudeInMenuBar = settings.showClaudeInMenuBar
        paceWarningsEnabled = settings.paceWarningsEnabled
    }

    var menuTitle: String {
        var parts: [String] = []
        if codexEnabled && showCodexInMenuBar {
            parts.append(menuBarMetric.value(from: snapshot).map { "C \(UsageMath.wholePercent($0))" } ?? "C --")
        }
        if claudeEnabled && showClaudeInMenuBar {
            parts.append(menuBarMetric.value(from: claudeSnapshot).map { "Cl \(UsageMath.wholePercent($0))" } ?? "Cl --")
        }
        return parts.isEmpty ? "LLM" : parts.joined(separator: "  ")
    }

    var codexMenuMetricAheadOfPace: Bool {
        guard paceWarningsEnabled, let window = menuBarMetric.codexWindow(from: snapshot) else { return false }
        return window.isAheadOfPace
    }

    var claudeMenuMetricAheadOfPace: Bool {
        guard paceWarningsEnabled, let window = menuBarMetric.claudeWindow(from: claudeSnapshot) else { return false }
        return window.isAheadOfPace
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleTimer()
        refresh()
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
    }

    private func refreshCodexAsync() {
        guard !isRefreshingCodex else { return }
        isRefreshingCodex = true
        let codexHome = codexHome
        let reader = reader

        Task.detached(priority: .utility) {
            let balanceSnapshot = reader.loadBalanceSnapshot(codexHome: codexHome)
            await MainActor.run {
                self.snapshot = balanceSnapshot
                self.notifyIfNeeded(balanceSnapshot)
            }

            let result = Result { try reader.loadSnapshot(codexHome: codexHome) }
            await MainActor.run {
                self.isRefreshingCodex = false
                switch result {
                case .success(let fullSnapshot):
                    self.snapshot = fullSnapshot
                    self.notifyIfNeeded(fullSnapshot)
                case .failure(let error):
                    var current = self.snapshot
                    current.errorMessage = error.localizedDescription
                    current.updatedAt = Date()
                    self.snapshot = current
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

    private func persistSettings() {
        settings.codexHome = codexHome
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
        settings.showCodexInMenuBar = showCodexInMenuBar
        settings.showClaudeInMenuBar = showClaudeInMenuBar
        settings.paceWarningsEnabled = paceWarningsEnabled
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(refreshInterval, 5), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
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

    private func refreshClaude() async {
        let credentials = loadedClaudeCredentials()
        guard !credentials.sessionKey.isEmpty else {
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: "Claude credentials are not available. Sign in again from settings.")
            return
        }

        do {
            let result = try await claudeClient.fetch(
                organizationID: claudeOrganizationID,
                sessionKey: credentials.sessionKey,
                cfClearance: credentials.cfClearance
            )
            claudeSnapshot = result
        } catch {
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription)
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
