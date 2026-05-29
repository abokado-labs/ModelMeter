import AppKit
import Foundation
import SwiftUI

enum CodexDataSource: String, CaseIterable, Identifiable {
    case liveOAuth
    case localFiles

    var id: Self { self }

    var title: String {
        switch self {
        case .liveOAuth:
            return "Live ChatGPT"
        case .localFiles:
            return "Local Codex files"
        }
    }

    var detail: String {
        switch self {
        case .liveOAuth:
            return "Uses Codex's ChatGPT login in auth.json to request live 5-hour and weekly balances."
        case .localFiles:
            return "Reads Codex's local session snapshots and state_5.sqlite. This can lag or miss live balance changes."
        }
    }
}

struct UsageSnapshot {
    var sessionTokens: Int = 0
    var weeklyTokens: Int = 0
    var todayTokens: Int = 0
    var totalTokens: Int = 0
    var activeThreads: Int = 0
    var recentThreads: [ThreadUsage] = []
    var modelBreakdown: [ModelUsage] = []
    var rateLimits: CodexRateLimits?
    var updatedAt: Date?
    var errorMessage: String?

    var sessionProgress: Double { rateLimits?.primary.progress ?? UsageMath.progress(sessionTokens, SettingsStore.shared.sessionLimit) }
    var weeklyProgress: Double { rateLimits?.secondary.progress ?? UsageMath.progress(weeklyTokens, SettingsStore.shared.weeklyLimit) }
    var todayProgress: Double { UsageMath.progress(todayTokens, SettingsStore.shared.dailyLimit) }
    var status: UsageStatus { UsageStatus(progress: max(sessionProgress, weeklyProgress)) }

}

struct ClaudeUsageSnapshot {
    var rateLimits: ClaudeRateLimits?
    var updatedAt: Date?
    var errorMessage: String?

    var sessionProgress: Double { rateLimits?.session.progress ?? -1 }
    var weeklyProgress: Double { rateLimits?.weekly.progress ?? -1 }
    var status: UsageStatus { UsageStatus(progress: max(sessionProgress, weeklyProgress)) }
}

struct GeminiUsageSnapshot {
    var items: [GeminiUsageItem] = []
    var updatedAt: Date?
    var errorMessage: String?
    var accountEmail: String?
    var accountPlan: String?

    var primaryItem: GeminiUsageItem? { items.first { $0.id == "current-usage" } ?? items.first }
    var weeklyItem: GeminiUsageItem? { items.first { $0.id == "weekly-limit" } ?? items.dropFirst().first }
    var status: UsageStatus {
        let usedValues = items.map { $0.usedPercent / 100 }
        return UsageStatus(progress: usedValues.max() ?? -1)
    }
}

struct GeminiUsageItem: Identifiable, Hashable {
    let id: String
    let title: String
    let usedPercent: Double
    let detail: String?

    var remainingPercent: Double { max(100 - usedPercent, 0) }
}

enum ProviderKind: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claude = "Claude"
    case gemini = "Gemini"

    var id: Self { self }
}

enum ProviderStatusSeverity: String, Comparable {
    case unknown
    case operational
    case degraded
    case partialOutage
    case majorOutage
    case maintenance

    init(statusPageIndicator: String) {
        switch statusPageIndicator.lowercased() {
        case "none":
            self = .operational
        case "minor":
            self = .degraded
        case "major":
            self = .partialOutage
        case "critical":
            self = .majorOutage
        default:
            self = .unknown
        }
    }

    init(statusPageStatus: String) {
        switch statusPageStatus.lowercased() {
        case "operational":
            self = .operational
        case "degraded_performance":
            self = .degraded
        case "partial_outage":
            self = .partialOutage
        case "major_outage":
            self = .majorOutage
        case "under_maintenance":
            self = .maintenance
        default:
            self = .unknown
        }
    }

    static func < (lhs: ProviderStatusSeverity, rhs: ProviderStatusSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var isIssue: Bool {
        switch self {
        case .degraded, .partialOutage, .majorOutage, .maintenance:
            return true
        case .unknown, .operational:
            return false
        }
    }

    var rank: Int {
        switch self {
        case .unknown: return 0
        case .operational: return 1
        case .maintenance: return 2
        case .degraded: return 3
        case .partialOutage: return 4
        case .majorOutage: return 5
        }
    }

    var title: String {
        switch self {
        case .unknown: return "Status unknown"
        case .operational: return "Operational"
        case .degraded: return "Degraded"
        case .partialOutage: return "Partial outage"
        case .majorOutage: return "Major outage"
        case .maintenance: return "Maintenance"
        }
    }

    var symbolName: String {
        switch self {
        case .operational: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .degraded, .partialOutage, .majorOutage, .maintenance:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .operational: return .green
        case .unknown: return .secondary
        case .maintenance: return .blue
        case .degraded: return .yellow
        case .partialOutage, .majorOutage: return .orange
        }
    }
}

struct ProviderOperationalStatus: Equatable {
    let provider: ProviderKind
    let severity: ProviderStatusSeverity
    let message: String?
    let source: String
    let checkedAt: Date?

    static func unknown(provider: ProviderKind, source: String = "") -> ProviderOperationalStatus {
        ProviderOperationalStatus(
            provider: provider,
            severity: .unknown,
            message: nil,
            source: source,
            checkedAt: nil
        )
    }

    var hasIssue: Bool { severity.isIssue }
    var displayMessage: String { message ?? severity.title }
}

struct ProviderStatusSnapshot: Equatable {
    var codex: ProviderOperationalStatus = .unknown(provider: .codex)
    var claude: ProviderOperationalStatus = .unknown(provider: .claude)
    var gemini: ProviderOperationalStatus = .unknown(provider: .gemini)
    var updatedAt: Date?

    func status(for provider: ProviderKind) -> ProviderOperationalStatus {
        switch provider {
        case .codex: return codex
        case .claude: return claude
        case .gemini: return gemini
        }
    }

    var mostSevereIssue: ProviderOperationalStatus? {
        [codex, claude, gemini]
            .filter(\.hasIssue)
            .max { $0.severity < $1.severity }
    }
}

struct ThreadUsage: Identifiable, Decodable {
    let id: String
    let title: String
    let tokens: Int
    let updatedAt: Date
    let model: String
    let cwd: String
}

struct ModelUsage: Identifiable, Decodable {
    let model: String
    let tokens: Int
    let threads: Int

    var id: String { model }
}

struct CodexRateLimits {
    let primary: RateLimitWindow
    let secondary: RateLimitWindow
    let credits: CreditBalance?
    let planType: String?
    let capturedAt: Date
    let sourcePath: String

    var displayPlan: String {
        guard let planType, !planType.isEmpty else { return "Unknown plan" }
        return planType
    }

    var sourceLabel: String {
        if sourcePath == "codex oauth wham/usage" { return "ChatGPT OAuth live usage" }
        if sourcePath == "codex app-server" { return "Codex app-server" }
        if sourcePath.hasPrefix("/") { return "Local Codex fallback" }
        return sourcePath
    }

    var isLocalFallback: Bool {
        sourcePath.hasPrefix("/")
    }

    var isLikelyPlaceholder: Bool {
        guard isLocalFallback, planType == nil || planType?.isEmpty == true else { return false }
        guard primary.usedPercent == 0, secondary.usedPercent == 0 else { return false }
        return true
    }
}

struct RateLimitWindow {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    var progress: Double {
        min(max(usedPercent / 100, 0), 1)
    }

    var remainingPercent: Double {
        max(100 - usedPercent, 0)
    }

    var elapsedProgress: Double {
        let windowSeconds = TimeInterval(windowMinutes * 60)
        guard windowSeconds > 0 else { return 0 }
        let start = resetsAt.addingTimeInterval(-windowSeconds)
        let elapsed = Date().timeIntervalSince(start)
        return min(max(elapsed / windowSeconds, 0), 1)
    }

    var paceUsedPercent: Double {
        elapsedProgress * 100
    }

    var isAheadOfPace: Bool {
        usedPercent > paceUsedPercent + 2
    }

    var windowLabel: String {
        if windowMinutes == 300 { return "5 hours" }
        if windowMinutes == 10_080 { return "7 days" }
        if windowMinutes % 1_440 == 0 { return "\(windowMinutes / 1_440) days" }
        if windowMinutes % 60 == 0 { return "\(windowMinutes / 60) hours" }
        return "\(windowMinutes) minutes"
    }
}

struct CreditBalance {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?
}

struct ClaudeRateLimits {
    let session: RateLimitWindow
    let weekly: RateLimitWindow
    let opusWeekly: RateLimitWindow?
    let extraUsage: ClaudeExtraUsage?
}

struct ClaudeExtraUsage {
    let currentSpending: Double?
    let budgetLimit: Double?
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case fiveHourUsed
    case fiveHourAvailable
    case sevenDayUsed
    case sevenDayAvailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHourUsed: return "5-hour used"
        case .fiveHourAvailable: return "5-hour available"
        case .sevenDayUsed: return "7-day used"
        case .sevenDayAvailable: return "7-day available"
        }
    }

    var shortPrefix: String {
        switch self {
        case .fiveHourUsed: return "5h"
        case .fiveHourAvailable: return "5h"
        case .sevenDayUsed: return "7d"
        case .sevenDayAvailable: return "7d"
        }
    }

    var descriptor: String {
        switch self {
        case .fiveHourUsed, .sevenDayUsed: return "used"
        case .fiveHourAvailable, .sevenDayAvailable: return "available"
        }
    }

    func value(from snapshot: UsageSnapshot) -> Double? {
        guard let rateLimits = snapshot.rateLimits else { return nil }
        switch self {
        case .fiveHourUsed:
            return rateLimits.primary.usedPercent
        case .fiveHourAvailable:
            return rateLimits.primary.remainingPercent
        case .sevenDayUsed:
            return rateLimits.secondary.usedPercent
        case .sevenDayAvailable:
            return rateLimits.secondary.remainingPercent
        }
    }

    func value(from snapshot: ClaudeUsageSnapshot) -> Double? {
        guard let rateLimits = snapshot.rateLimits else { return nil }
        switch self {
        case .fiveHourUsed:
            return rateLimits.session.usedPercent
        case .fiveHourAvailable:
            return rateLimits.session.remainingPercent
        case .sevenDayUsed:
            return rateLimits.weekly.usedPercent
        case .sevenDayAvailable:
            return rateLimits.weekly.remainingPercent
        }
    }

    func value(from snapshot: GeminiUsageSnapshot) -> Double? {
        switch self {
        case .fiveHourUsed:
            return snapshot.primaryItem?.usedPercent
        case .fiveHourAvailable:
            return snapshot.primaryItem?.remainingPercent
        case .sevenDayUsed:
            return snapshot.weeklyItem?.usedPercent
        case .sevenDayAvailable:
            return snapshot.weeklyItem?.remainingPercent
        }
    }

    func codexWindow(from snapshot: UsageSnapshot) -> RateLimitWindow? {
        guard let rateLimits = snapshot.rateLimits else { return nil }
        switch self {
        case .fiveHourUsed, .fiveHourAvailable:
            return rateLimits.primary
        case .sevenDayUsed, .sevenDayAvailable:
            return rateLimits.secondary
        }
    }

    func claudeWindow(from snapshot: ClaudeUsageSnapshot) -> RateLimitWindow? {
        guard let rateLimits = snapshot.rateLimits else { return nil }
        switch self {
        case .fiveHourUsed, .fiveHourAvailable:
            return rateLimits.session
        case .sevenDayUsed, .sevenDayAvailable:
            return rateLimits.weekly
        }
    }
}

enum MenuBarIconMode: String, CaseIterable, Identifiable {
    case statusIcon
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statusIcon: return "Show status icon"
        case .hidden: return "Hide icon"
        }
    }
}

enum MenuBarLabelStyle: String, CaseIterable, Identifiable {
    case letters
    case icons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters: return "Letters"
        case .icons: return "Icons"
        }
    }
}

enum MenuBarFontSize: String, CaseIterable, Identifiable {
    case small
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .regular: return "Regular"
        case .large: return "Large"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: return 10
        case .regular: return 12
        case .large: return 14
        }
    }
}

enum UsageStatus {
    case normal
    case busy
    case high
    case capped
    case unknown

    init(progress: Double) {
        switch progress {
        case ..<0:
            self = .unknown
        case 0..<0.65:
            self = .normal
        case 0.65..<0.85:
            self = .busy
        case 0.85..<1:
            self = .high
        default:
            self = .capped
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .busy: return .yellow
        case .high: return .orange
        case .capped: return .red
        case .unknown: return .secondary
        }
    }

    var nsColor: NSColor {
        switch self {
        case .normal: return .systemGreen
        case .busy: return .systemYellow
        case .high: return .systemOrange
        case .capped: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "gauge.with.dots.needle.bottom.50percent"
        case .busy: return "gauge.with.dots.needle.67percent"
        case .high: return "gauge.with.dots.needle.100percent"
        case .capped: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .normal: return "Plenty remaining"
        case .busy: return "Usage elevated"
        case .high: return "Limit approaching"
        case .capped: return "Limit reached"
        case .unknown: return "No data"
        }
    }
}

enum UsageMath {
    static func progress(_ value: Int, _ limit: Int) -> Double {
        guard limit > 0 else { return -1 }
        return min(max(Double(value) / Double(limit), 0), 1)
    }

    static func percent(_ progress: Double) -> String {
        guard progress >= 0 else { return "--" }
        return "\(Int(progress * 100))%"
    }

    static func wholePercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func tokenString(_ tokens: Int) -> String {
        let value = Double(tokens)
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        return "\(tokens)"
    }
}
