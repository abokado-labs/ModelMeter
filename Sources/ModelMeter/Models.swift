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
            return "Requests live usage balances through Codex app-server when available, then falls back to Codex's ChatGPT login in auth.json."
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

    var sessionProgress: Double { rateLimits?.primary?.progress ?? UsageMath.progress(sessionTokens, SettingsStore.shared.sessionLimit) }
    var weeklyProgress: Double { rateLimits?.secondary?.progress ?? UsageMath.progress(weeklyTokens, SettingsStore.shared.weeklyLimit) }
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

struct GeminiUsageItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let usedPercent: Double
    let detail: String?

    var remainingPercent: Double { max(100 - usedPercent, 0) }
}

struct UsageHistoryEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let provider: ProviderKind
    let capturedAt: Date
    let primaryUsedPercent: Double?
    let primaryRemainingPercent: Double?
    let secondaryUsedPercent: Double?
    let secondaryRemainingPercent: Double?
    let sourceLabel: String

    init(
        id: UUID = UUID(),
        provider: ProviderKind,
        capturedAt: Date,
        primaryUsedPercent: Double?,
        primaryRemainingPercent: Double?,
        secondaryUsedPercent: Double?,
        secondaryRemainingPercent: Double?,
        sourceLabel: String
    ) {
        self.id = id
        self.provider = provider
        self.capturedAt = capturedAt
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryRemainingPercent = primaryRemainingPercent
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryRemainingPercent = secondaryRemainingPercent
        self.sourceLabel = sourceLabel
    }
}

enum ProviderReadingQuality {
    case freshLive(String)
    case localFallback(String)
    case lastGood(Date?)
    case unavailable
    case notConfigured

    var title: String {
        switch self {
        case .freshLive:
            return "Live"
        case .localFallback:
            return "Local"
        case .lastGood:
            return "Last good"
        case .unavailable:
            return "Unavailable"
        case .notConfigured:
            return "Not configured"
        }
    }

    var detail: String? {
        switch self {
        case .freshLive(let source), .localFallback(let source):
            return source
        case .lastGood(let date):
            guard let date else { return nil }
            return date.formatted(date: .omitted, time: .shortened)
        case .unavailable, .notConfigured:
            return nil
        }
    }

    var displayText: String {
        if let detail {
            return "\(title): \(detail)"
        }
        return title
    }

    var hasCurrentReading: Bool {
        switch self {
        case .freshLive, .localFallback:
            return true
        case .lastGood, .unavailable, .notConfigured:
            return false
        }
    }

    var compactText: String {
        switch self {
        case .freshLive(let source):
            return "Fresh · \(Self.compactSource(source))"
        case .localFallback(let source):
            return "Local · \(Self.compactSource(source))"
        case .lastGood:
            return "Last good"
        case .unavailable:
            return "Not refreshed"
        case .notConfigured:
            return "Not connected"
        }
    }

    private static func compactSource(_ source: String) -> String {
        let lowercased = source.lowercased()
        if lowercased.contains("oauth") { return "OAuth" }
        if lowercased.contains("claude") { return "Claude" }
        if lowercased.contains("gemini") { return "Gemini" }
        if lowercased.contains("local") { return "Local" }
        if lowercased.contains("app") { return "App server" }
        return source
    }

    var symbolName: String {
        switch self {
        case .freshLive:
            return "bolt.circle.fill"
        case .localFallback:
            return "folder.circle.fill"
        case .lastGood:
            return "clock.badge.checkmark.fill"
        case .unavailable:
            return "exclamationmark.circle.fill"
        case .notConfigured:
            return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .freshLive:
            return .green
        case .localFallback:
            return .blue
        case .lastGood:
            return .orange
        case .unavailable:
            return .secondary
        case .notConfigured:
            return .secondary
        }
    }
}

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case codex = "Codex"
    case claude = "Claude"
    case gemini = "Gemini"

    var id: Self { self }
}

struct HistoryGraphPoint: Equatable {
    let date: Date
    let usedPercent: Double
}

struct HistoryGraphSegment: Equatable {
    let startIndex: Int
    let endIndex: Int
    let isGap: Bool
    let isReset: Bool

    init(startIndex: Int, endIndex: Int, isGap: Bool, isReset: Bool = false) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.isGap = isGap
        self.isReset = isReset
    }
}

struct HistoryGraphSeries: Equatable {
    let provider: ProviderKind
    let points: [HistoryGraphPoint]
    let segments: [HistoryGraphSegment]
}

struct HistoryGraphData: Equatable {
    let series: [HistoryGraphSeries]
    let latestGapCaption: String?

    var containsGap: Bool {
        series.contains { providerSeries in
            providerSeries.segments.contains { $0.isGap }
        }
    }

    var hasEnoughForChart: Bool {
        series.contains { $0.points.count > 1 }
    }

    static func make(
        entries: [UsageHistoryEntry],
        visibleProviders: [ProviderKind],
        rangeInterval: TimeInterval,
        now: Date = Date(),
        gapThreshold: TimeInterval = 30 * 60
    ) -> HistoryGraphData {
        let cutoff = now.addingTimeInterval(-rangeInterval)
        var allGapSummaries: [HistoryGapSummary] = []

        let series = visibleProviders.compactMap { provider -> HistoryGraphSeries? in
            let providerSamples = entries
                .filter { $0.provider == provider && $0.capturedAt <= now && $0.primaryUsedPercent != nil }
                .sorted { $0.capturedAt < $1.capturedAt }

            guard !providerSamples.isEmpty else { return nil }

            let rangeSamples = providerSamples.filter { $0.capturedAt >= cutoff }
            let anchorSample = providerSamples.last { $0.capturedAt < cutoff }
            var nodes: [HistoryTimelineNode] = []

            if let anchorSample,
               let used = anchorSample.primaryUsedPercent {
                nodes.append(
                    HistoryTimelineNode(
                        point: HistoryGraphPoint(date: cutoff, usedPercent: used),
                        sampleDate: anchorSample.capturedAt,
                        isCarriedForward: true
                    )
                )
            }

            nodes.append(
                contentsOf: rangeSamples.compactMap { sample in
                    guard let used = sample.primaryUsedPercent else { return nil }
                    return HistoryTimelineNode(
                        point: HistoryGraphPoint(date: sample.capturedAt, usedPercent: used),
                        sampleDate: sample.capturedAt,
                        isCarriedForward: false
                    )
                }
            )

            guard !nodes.isEmpty else { return nil }

            if let latestSample = providerSamples.last,
               let latestUsed = latestSample.primaryUsedPercent,
               now.timeIntervalSince(latestSample.capturedAt) > gapThreshold,
               let latestPoint = nodes.last?.point,
               now.timeIntervalSince(latestPoint.date) > 60 {
                nodes.append(
                    HistoryTimelineNode(
                        point: HistoryGraphPoint(date: now, usedPercent: latestUsed),
                        sampleDate: now,
                        isCarriedForward: true
                    )
                )
            }

            var segments: [HistoryGraphSegment] = []
            if nodes.count > 1 {
                for index in 1..<nodes.count {
                    let previous = nodes[index - 1]
                    let current = nodes[index]
                    let sampleGap = current.sampleDate.timeIntervalSince(previous.sampleDate)
                    let delta = current.point.usedPercent - previous.point.usedPercent
                    let isGap = current.isCarriedForward || sampleGap > gapThreshold
                    let isReset = delta.rounded() <= -1
                    segments.append(
                        HistoryGraphSegment(
                            startIndex: index - 1,
                            endIndex: index,
                            isGap: isGap,
                            isReset: isReset
                        )
                    )

                    if isGap && !current.isCarriedForward && !isReset {
                        if delta.rounded() >= 1 {
                            allGapSummaries.append(
                                HistoryGapSummary(
                                    provider: provider,
                                    delta: delta,
                                    startDate: previous.sampleDate,
                                    endDate: current.sampleDate
                                )
                            )
                        }
                    }
                }
            }

            return HistoryGraphSeries(
                provider: provider,
                points: nodes.map(\.point),
                segments: segments
            )
        }

        return HistoryGraphData(
            series: series,
            latestGapCaption: Self.caption(for: allGapSummaries)
        )
    }

    private static func caption(for summaries: [HistoryGapSummary]) -> String? {
        guard let latestEnd = summaries.map(\.endDate).max() else { return nil }
        let groupWindow: TimeInterval = 5 * 60
        let latest = summaries
            .filter { abs($0.endDate.timeIntervalSince(latestEnd)) <= groupWindow }
            .sorted { lhs, rhs in
                let order = ProviderKind.allCases
                let lhsIndex = order.firstIndex(of: lhs.provider) ?? order.endIndex
                let rhsIndex = order.firstIndex(of: rhs.provider) ?? order.endIndex
                return lhsIndex < rhsIndex
            }
        guard !latest.isEmpty else { return nil }

        let longestGap = latest
            .map { $0.endDate.timeIntervalSince($0.startDate) }
            .max() ?? 0
        let changes = latest
            .map { "\($0.provider.rawValue) \(Self.formatDelta($0.delta))" }
            .joined(separator: ", ")
        return "No readings for \(Self.formatDuration(longestGap)); \(changes) found on return"
    }

    private static func formatDelta(_ delta: Double) -> String {
        let rounded = Int(delta.rounded())
        return "\(rounded >= 0 ? "+" : "")\(rounded)%"
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int(duration.rounded() / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

private struct HistoryTimelineNode {
    let point: HistoryGraphPoint
    let sampleDate: Date
    let isCarriedForward: Bool
}

private struct HistoryGapSummary {
    let provider: ProviderKind
    let delta: Double
    let startDate: Date
    let endDate: Date
}

enum HistoryGraphPosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: Self { self }

    var title: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
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

    var statusLineText: String {
        if hasIssue {
            if let affectedServiceLabel {
                return "\(statusProviderName) \(affectedServiceLabel) issue"
            }
            return "\(statusProviderName) service issue"
        }
        if severity == .unknown {
            return "\(statusProviderName) status not available"
        }
        return "\(statusProviderName) status: all clear"
    }

    func contextText(for quality: ProviderReadingQuality) -> String {
        if quality.hasCurrentReading {
            return "\(statusProviderName) reports \(issueSummary), but this reading succeeded."
        }
        if case .lastGood = quality {
            return "\(statusProviderName) reports \(issueSummary). Showing the last good reading."
        }
        return "\(statusProviderName) reports \(issueSummary)."
    }

    var plainExplanation: String {
        if hasIssue {
            if let affectedService {
                return "\(statusProviderName)'s public status page says \(affectedService) is \(plainIssueDescription). Your Model Meter balance reading may still work."
            }
            return "\(statusProviderName)'s public status page says some services are \(plainIssueDescription). Your Model Meter balance reading may still work."
        }
        if severity == .unknown {
            return "Model Meter could not check \(statusProviderName)'s public status page."
        }
        return "\(statusProviderName)'s public status page says services are running normally."
    }

    private var statusProviderName: String {
        switch provider {
        case .codex:
            return "OpenAI"
        case .claude:
            return "Claude"
        case .gemini:
            return "Google"
        }
    }

    private var affectedService: String? {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var affectedServiceLabel: String? {
        guard let affectedService else { return nil }
        let lowercased = affectedService.lowercased()
        if provider == .claude, lowercased.contains("claude.ai") { return "web" }
        if lowercased == "login" { return "login" }
        if lowercased == "api" { return "API" }
        return affectedService
    }

    private var issueSummary: String {
        guard let affectedServiceLabel else { return "service issues" }
        return "\(affectedServiceLabel) issues"
    }

    private var plainIssueNoun: String {
        switch severity {
        case .degraded:
            return "problems"
        case .partialOutage:
            return "outage"
        case .majorOutage:
            return "major outage"
        case .maintenance:
            return "maintenance"
        case .unknown, .operational:
            return severity.title.lowercased()
        }
    }

    private var plainIssueDescription: String {
        switch severity {
        case .degraded:
            return "having problems"
        case .partialOutage:
            return "partly down"
        case .majorOutage:
            return "down for many users"
        case .maintenance:
            return "under maintenance"
        case .unknown, .operational:
            return severity.title.lowercased()
        }
    }
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

struct CodexRateLimits: Codable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditBalance?
    let planType: String?
    let capturedAt: Date
    let sourcePath: String

    var displayPlan: String {
        guard let planType, !planType.isEmpty else { return "Unknown plan" }
        return planType
    }

    var sourceLabel: String {
        if sourcePath == "codex oauth wham/usage" { return "ChatGPT OAuth" }
        if sourcePath == "codex app-server" { return "Codex app-server" }
        if sourcePath.hasPrefix("/") { return "Local Codex snapshot" }
        return sourcePath
    }

    var isLocalFallback: Bool {
        sourcePath.hasPrefix("/")
    }

    var isLikelyPlaceholder: Bool {
        guard isLocalFallback, planType == nil || planType?.isEmpty == true else { return false }
        guard primary?.usedPercent == 0, secondary?.usedPercent == 0 else { return false }
        return true
    }
}

enum CodexRateLimitWindows {
    static func split(_ windows: [RateLimitWindow]) -> (primary: RateLimitWindow?, secondary: RateLimitWindow?) {
        let primary = windows
            .filter { $0.windowMinutes != 10_080 }
            .min { $0.windowMinutes < $1.windowMinutes }
        let secondary = windows
            .filter { $0.windowMinutes == 10_080 }
            .first ?? windows.max { $0.windowMinutes < $1.windowMinutes }
        return (primary, secondary)
    }
}

struct RateLimitWindow: Codable {
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

struct CreditBalance: Codable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?
}

struct ClaudeRateLimits: Codable {
    let session: RateLimitWindow
    let weekly: RateLimitWindow
    let opusWeekly: RateLimitWindow?
    let extraUsage: ClaudeExtraUsage?
}

struct ClaudeExtraUsage: Codable {
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
            return rateLimits.primary?.usedPercent
        case .fiveHourAvailable:
            return rateLimits.primary?.remainingPercent
        case .sevenDayUsed:
            return rateLimits.secondary?.usedPercent
        case .sevenDayAvailable:
            return rateLimits.secondary?.remainingPercent
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

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case allProviders
    case lowestAvailable
    case warningsOnly
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allProviders: return "All"
        case .lowestAvailable: return "Lowest"
        case .warningsOnly: return "Warnings"
        case .iconOnly: return "Icon"
        }
    }

    var detail: String {
        switch self {
        case .allProviders:
            return "Shows every selected provider."
        case .lowestAvailable:
            return "Shows the selected provider with the least capacity left."
        case .warningsOnly:
            return "Shows only providers that need attention."
        case .iconOnly:
            return "Shows only the status icon."
        }
    }
}

enum ResetDisplayMode: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relative: return "Countdown"
        case .absolute: return "Date & time"
        }
    }

    var detail: String {
        switch self {
        case .relative:
            return "Shows reset timing as a countdown, for example 4d 12h."
        case .absolute:
            return "Shows reset timing as a calendar date and time."
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
