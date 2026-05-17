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

    private let settings = SettingsStore.shared
    private let reader = UsageReader()
    private let claudeClient = ClaudeUsageClient()
    private var timer: Timer?
    private var lastNotificationStatus: UsageStatus = .unknown

    init() {
        codexHome = settings.codexHome
        claudeOrganizationID = settings.claudeOrganizationID
        claudeSessionKey = KeychainStore.read(account: "claudeSessionKey")
        claudeCfClearance = KeychainStore.read(account: "claudeCfClearance")
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
    }

    var menuTitle: String {
        let codex = snapshot.rateLimits.map { "C \(UsageMath.wholePercent($0.primary.remainingPercent))" } ?? "C --"
        let claude = claudeSnapshot.rateLimits.map { "Cl \(UsageMath.wholePercent($0.session.remainingPercent))" } ?? "Cl --"
        return "\(codex)  \(claude)"
    }

    func start() {
        refresh()
        scheduleTimer()
    }

    func refresh() {
        do {
            snapshot = try reader.loadSnapshot(settings: settings)
            notifyIfNeeded(snapshot)
        } catch {
            snapshot = UsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription)
        }

        if !claudeOrganizationID.isEmpty && !claudeSessionKey.isEmpty {
            Task {
                await refreshClaude()
            }
        }
    }

    func saveSettings() {
        persistSettings()
        refresh()
        scheduleTimer()
    }

    private func persistSettings() {
        settings.codexHome = codexHome
        settings.claudeOrganizationID = claudeOrganizationID
        KeychainStore.write(claudeSessionKey, account: "claudeSessionKey")
        KeychainStore.write(claudeCfClearance, account: "claudeCfClearance")
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
        do {
            let result = try await claudeClient.fetch(
                organizationID: claudeOrganizationID,
                sessionKey: claudeSessionKey,
                cfClearance: claudeCfClearance
            )
            claudeSnapshot = result
        } catch {
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription)
        }
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
        } catch {
            KeychainStore.write(sessionKey, account: "claudeSessionKey")
            KeychainStore.write(cfClearance, account: "claudeCfClearance")
            claudeSnapshot = ClaudeUsageSnapshot(updatedAt: Date(), errorMessage: error.localizedDescription)
        }
    }
}
