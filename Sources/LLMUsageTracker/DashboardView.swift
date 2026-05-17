import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                settingsPanel
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let error = store.snapshot.errorMessage {
                                ErrorPanel(message: error)
                            }
                            providerOverview
                            SectionTitle("Codex")
                            usageGrid
                            claudeSection
                            modelSection
                            recentSection
                        }
                        .padding(16)
                    }
                    Divider()
                    footer
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    store.saveSettings()
                    showingSettings = false
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .help("Done")
            }
            .padding(16)
            Divider()
            SettingsView()
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.snapshot.status.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(store.snapshot.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage Tracker")
                    .font(.headline)
                Text(store.menuTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(16)
    }

    private var providerOverview: some View {
        HStack(spacing: 14) {
            ProviderBalancePanel(
                name: "Codex",
                value: store.snapshot.rateLimits.map { UsageMath.wholePercent($0.primary.remainingPercent) } ?? "--",
                detail: "5-hour available",
                status: store.snapshot.status
            )
            ProviderBalancePanel(
                name: "Claude",
                value: store.claudeSnapshot.rateLimits.map { UsageMath.wholePercent($0.session.remainingPercent) } ?? "--",
                detail: claudeDetail,
                status: store.claudeSnapshot.status
            )
        }
    }

    private var claudeDetail: String {
        if store.claudeOrganizationID.isEmpty || store.claudeSessionKey.isEmpty {
            return "Not configured"
        }
        if store.claudeSnapshot.errorMessage != nil {
            return "Needs attention"
        }
        return "session available"
    }

    private var usageGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                RateLimitMeter(
                    title: "5-hour balance",
                    window: store.snapshot.rateLimits?.primary,
                    tint: store.snapshot.status.color
                )
                RateLimitMeter(
                    title: "7-day balance",
                    window: store.snapshot.rateLimits?.secondary,
                    tint: .purple
                )
            }
            GridRow {
                UsageMeter(
                    title: "Today tokens",
                    tokens: store.snapshot.todayTokens,
                    limit: store.dailyLimit,
                    progress: store.snapshot.todayProgress,
                    tint: .blue
                )
                StatPanel(
                    title: "Plan",
                    value: store.snapshot.rateLimits?.displayPlan ?? "Unknown",
                    detail: rateLimitDetail
                )
            }
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Claude")
            if store.claudeOrganizationID.isEmpty || store.claudeSessionKey.isEmpty {
                SetupPanel(
                    title: "Claude account not connected",
                    message: "Add your Claude organization ID and session key in settings to show real session and weekly balances."
                )
            } else if let error = store.claudeSnapshot.errorMessage {
                ErrorPanel(message: error)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        RateLimitMeter(
                            title: "Session balance",
                            window: store.claudeSnapshot.rateLimits?.session,
                            tint: store.claudeSnapshot.status.color
                        )
                        RateLimitMeter(
                            title: "Weekly balance",
                            window: store.claudeSnapshot.rateLimits?.weekly,
                            tint: .indigo
                        )
                    }
                    GridRow {
                        RateLimitMeter(
                            title: "Opus weekly",
                            window: store.claudeSnapshot.rateLimits?.opusWeekly,
                            tint: .orange
                        )
                        StatPanel(
                            title: "Claude status",
                            value: store.claudeSnapshot.rateLimits == nil ? "Waiting" : "Connected",
                            detail: claudeUpdatedText
                        )
                    }
                }
            }
        }
    }

    private var claudeUpdatedText: String {
        guard let updatedAt = store.claudeSnapshot.updatedAt else {
            return "Not refreshed yet"
        }
        return "Updated \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var rateLimitDetail: String {
        guard let rateLimits = store.snapshot.rateLimits else {
            return "No status snapshot found"
        }
        return "Captured \(rateLimits.capturedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Models this week")
            if store.snapshot.modelBreakdown.isEmpty {
                EmptyState(text: "No model usage in the current 7-day window.")
            } else {
                VStack(spacing: 8) {
                    ForEach(store.snapshot.modelBreakdown) { item in
                        HStack(spacing: 10) {
                            Text(item.model)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.threads) threads")
                                .foregroundStyle(.secondary)
                            Text(UsageMath.tokenString(item.tokens))
                                .monospacedDigit()
                                .frame(width: 62, alignment: .trailing)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Recent threads")
            if store.snapshot.recentThreads.isEmpty {
                EmptyState(text: "No Codex threads with token usage yet.")
            } else {
                VStack(spacing: 8) {
                    ForEach(store.snapshot.recentThreads) { thread in
                        RecentThreadRow(thread: thread)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(16)
    }

    private var lastUpdatedText: String {
        guard let updatedAt = store.snapshot.updatedAt else { return "Not refreshed yet" }
        return "Updated \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct UsageMeter: View {
    let title: String
    let tokens: Int
    let limit: Int
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(UsageMath.percent(progress))
                    .font(.caption)
                    .monospacedDigit()
            }
            ProgressView(value: progress < 0 ? 0 : progress)
                .tint(tint)
            HStack(alignment: .firstTextBaseline) {
                Text(UsageMath.tokenString(tokens))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("/ \(UsageMath.tokenString(limit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProviderBalancePanel: View {
    let name: String
    let value: String
    let detail: String
    let status: UsageStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: status.symbolName)
                    .foregroundStyle(status.color)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RateLimitMeter: View {
    let title: String
    let window: RateLimitWindow?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.map { UsageMath.wholePercent($0.usedPercent) } ?? "--")
                    .font(.caption)
                    .monospacedDigit()
            }
            ProgressView(value: window?.progress ?? 0)
                .tint(tint)
            HStack(alignment: .firstTextBaseline) {
                Text(window.map { UsageMath.wholePercent($0.remainingPercent) } ?? "--")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var resetText: String {
        guard let window else { return "Waiting for Codex status" }
        return "Resets \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct StatPanel: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 170, height: 83, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecentThreadRow: View {
    let thread: ThreadUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(thread.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(UsageMath.tokenString(thread.tokens))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(thread.model)
                Spacer()
                Text(thread.updatedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SetupPanel: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ErrorPanel: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
