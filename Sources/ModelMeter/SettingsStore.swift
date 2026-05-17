import Foundation

final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let codexHome = "codexHome"
        static let sessionLimit = "sessionLimit"
        static let dailyLimit = "dailyLimit"
        static let weeklyLimit = "weeklyLimit"
        static let refreshInterval = "refreshInterval"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationThreshold = "notificationThreshold"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarIconMode = "menuBarIconMode"
        static let menuBarLabelStyle = "menuBarLabelStyle"
        static let menuBarFontSize = "menuBarFontSize"
        static let claudeOrganizationID = "claudeOrganizationID"
        static let codexEnabled = "codexEnabled"
        static let claudeEnabled = "claudeEnabled"
        static let showCodexInMenuBar = "showCodexInMenuBar"
        static let showClaudeInMenuBar = "showClaudeInMenuBar"
        static let paceWarningsEnabled = "paceWarningsEnabled"
    }

    var codexHome: String {
        get {
            defaults.string(forKey: Key.codexHome)
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        }
        set { defaults.set(newValue, forKey: Key.codexHome) }
    }


    var codexEnabled: Bool {
        get { defaults.object(forKey: Key.codexEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.codexEnabled) }
    }

    var claudeEnabled: Bool {
        get { defaults.object(forKey: Key.claudeEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.claudeEnabled) }
    }

    var showCodexInMenuBar: Bool {
        get { defaults.object(forKey: Key.showCodexInMenuBar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showCodexInMenuBar) }
    }

    var showClaudeInMenuBar: Bool {
        get { defaults.object(forKey: Key.showClaudeInMenuBar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showClaudeInMenuBar) }
    }


    var paceWarningsEnabled: Bool {
        get { defaults.object(forKey: Key.paceWarningsEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.paceWarningsEnabled) }
    }

    var sessionLimit: Int {
        get { value(for: Key.sessionLimit, defaultValue: 200_000) }
        set { defaults.set(newValue, forKey: Key.sessionLimit) }
    }

    var dailyLimit: Int {
        get { value(for: Key.dailyLimit, defaultValue: 500_000) }
        set { defaults.set(newValue, forKey: Key.dailyLimit) }
    }

    var weeklyLimit: Int {
        get { value(for: Key.weeklyLimit, defaultValue: 2_000_000) }
        set { defaults.set(newValue, forKey: Key.weeklyLimit) }
    }

    var refreshInterval: Double {
        get {
            let stored = defaults.double(forKey: Key.refreshInterval)
            return stored > 0 ? stored : 30
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    var notificationsEnabled: Bool {
        get {
            defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    var notificationThreshold: Double {
        get {
            let stored = defaults.double(forKey: Key.notificationThreshold)
            return stored > 0 ? stored : 0.85
        }
        set { defaults.set(newValue, forKey: Key.notificationThreshold) }
    }

    var menuBarMetric: MenuBarMetric {
        get {
            guard let rawValue = defaults.string(forKey: Key.menuBarMetric),
                  let metric = MenuBarMetric(rawValue: rawValue)
            else {
                return .fiveHourAvailable
            }
            return metric
        }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarMetric) }
    }

    var menuBarIconMode: MenuBarIconMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.menuBarIconMode),
                  let mode = MenuBarIconMode(rawValue: rawValue)
            else {
                return .statusIcon
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarIconMode) }
    }

    var menuBarLabelStyle: MenuBarLabelStyle {
        get {
            guard let rawValue = defaults.string(forKey: Key.menuBarLabelStyle),
                  let style = MenuBarLabelStyle(rawValue: rawValue)
            else {
                return .letters
            }
            return style
        }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarLabelStyle) }
    }

    var menuBarFontSize: MenuBarFontSize {
        get {
            guard let rawValue = defaults.string(forKey: Key.menuBarFontSize),
                  let size = MenuBarFontSize(rawValue: rawValue)
            else {
                return .small
            }
            return size
        }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarFontSize) }
    }

    var claudeOrganizationID: String {
        get { defaults.string(forKey: Key.claudeOrganizationID) ?? "" }
        set { defaults.set(newValue, forKey: Key.claudeOrganizationID) }
    }

    private func value(for key: String, defaultValue: Int) -> Int {
        let stored = defaults.integer(forKey: key)
        return stored > 0 ? stored : defaultValue
    }
}
