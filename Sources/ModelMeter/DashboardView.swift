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
                        VStack(alignment: .leading, spacing: 14) {
                            if store.codexEnabled {
                                ProviderZone(
                                    name: "Codex",
                                    enabled: store.codexEnabled,
                                    configured: true,
                                    status: store.snapshot.status,
                                    hasData: store.snapshot.rateLimits != nil,
                                    primaryTitle: "5-hour window",
                                    primaryWindow: store.snapshot.rateLimits?.primary,
                                    secondaryTitle: "Weekly window",
                                    secondaryWindow: store.snapshot.rateLimits?.secondary,
                                    metaLeftTitle: "Plan",
                                    metaLeftValue: store.snapshot.rateLimits?.displayPlan ?? "Unknown",
                                    metaRightTitle: "Updated",
                                    metaRightValue: codexUpdatedText,
                                    message: store.snapshot.errorMessage
                                )
                            }

                            if store.claudeEnabled {
                                ProviderZone(
                                    name: "Claude",
                                    enabled: store.claudeEnabled,
                                    configured: !store.claudeOrganizationID.isEmpty,
                                    status: store.claudeSnapshot.status,
                                    hasData: store.claudeSnapshot.rateLimits != nil,
                                    primaryTitle: "5-hour window",
                                    primaryWindow: store.claudeSnapshot.rateLimits?.session,
                                    secondaryTitle: "Weekly window",
                                    secondaryWindow: store.claudeSnapshot.rateLimits?.weekly,
                                    metaLeftTitle: "Account",
                                    metaLeftValue: claudeAccountText,
                                    metaRightTitle: "Updated",
                                    metaRightValue: claudeUpdatedText,
                                    message: claudeMessage
                                )
                            }

                            if !store.codexEnabled && !store.claudeEnabled {
                                EmptyState(text: "Both providers are switched off in settings.")
                            }
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
            Text("Model Meter")
                .font(.headline)
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

    private var codexUpdatedText: String {
        guard let updatedAt = store.snapshot.rateLimits?.capturedAt ?? store.snapshot.updatedAt else { return "Not refreshed" }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var claudeUpdatedText: String {
        guard let updatedAt = store.claudeSnapshot.updatedAt else { return "Not refreshed" }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var claudeAccountText: String {
        if store.claudeOrganizationID.isEmpty { return "Not connected" }
        if store.claudeSnapshot.errorMessage != nil { return "Needs attention" }
        if store.claudeSnapshot.rateLimits == nil { return "Configured" }
        return "Connected"
    }

    private var claudeMessage: String? {
        if store.claudeOrganizationID.isEmpty {
            return "Connect Claude in settings to show the same 5-hour and weekly balance format."
        }
        return store.claudeSnapshot.errorMessage
    }

    private var lastUpdatedText: String {
        let dates = [store.snapshot.updatedAt, store.claudeSnapshot.updatedAt].compactMap { $0 }
        guard let latest = dates.max() else { return "Not refreshed yet" }
        return "Updated \(latest.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ProviderZone: View {
    let name: String
    let enabled: Bool
    let configured: Bool
    let status: UsageStatus
    let hasData: Bool
    let primaryTitle: String
    let primaryWindow: RateLimitWindow?
    let secondaryTitle: String
    let secondaryWindow: RateLimitWindow?
    let metaLeftTitle: String
    let metaLeftValue: String
    let metaRightTitle: String
    let metaRightValue: String
    let message: String?

    private var providerHealth: ProviderHealth {
        if enabled == false { return .disabled }
        if configured == false { return .notConfigured }
        if message != nil { return .error }
        if hasData == false { return .waiting }
        return .healthy(status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(providerHealth.title, systemImage: providerHealth.symbolName)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(providerHealth.color)
                    .help(providerHealth.title)
            }

            HStack(spacing: 12) {
                BalanceTile(title: primaryTitle, window: configured ? primaryWindow : nil, tint: status.color)
                BalanceTile(title: secondaryTitle, window: configured ? secondaryWindow : nil, tint: .purple)
            }

            HStack(spacing: 12) {
                MetaTile(title: metaLeftTitle, value: metaLeftValue)
                MetaTile(title: metaRightTitle, value: metaRightValue)
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(configured ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum ProviderHealth {
    case healthy(UsageStatus)
    case waiting
    case error
    case notConfigured
    case disabled

    var symbolName: String {
        switch self {
        case .healthy:
            return "checkmark.circle.fill"
        case .waiting:
            return "clock.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .notConfigured:
            return "questionmark.circle.fill"
        case .disabled:
            return "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .healthy(let status):
            return status.color
        case .waiting, .notConfigured, .disabled:
            return .secondary
        case .error:
            return .orange
        }
    }

    var title: String {
        switch self {
        case .healthy:
            return "Connected and refreshed"
        case .waiting:
            return "Waiting for data"
        case .error:
            return "Needs attention"
        case .notConfigured:
            return "Not configured"
        case .disabled:
            return "Disabled"
        }
    }
}

private struct BalanceTile: View {
    let title: String
    let window: RateLimitWindow?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Used")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(window.map { UsageMath.wholePercent($0.usedPercent) } ?? "--")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Available")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(window.map { UsageMath.wholePercent($0.remainingPercent) } ?? "--")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }
            PaceBar(window: window, tint: tint)
            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
    }

    private var resetText: String {
        guard let window else { return "Waiting for status" }
        let calendar = Calendar.current
        if calendar.isDateInToday(window.resetsAt) {
            return "Resets \(window.resetsAt.formatted(date: .omitted, time: .shortened))"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: window.resetsAt)).day,
           days > 0,
           days < 7 {
            return "Resets \(window.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        return "Resets \(window.resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }
}


private struct PaceBar: View {
    let window: RateLimitWindow?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = window?.progress ?? 0
            let marker = window?.elapsedProgress ?? 0
            let markerX = min(max(width * marker, 4), max(width - 4, 4))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.24))
                    .frame(height: 7)
                    .offset(y: 6)
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, width * progress), height: 7)
                    .offset(y: 6)
                if window != nil {
                    Rectangle()
                        .fill(Color.white)
                        .overlay(Rectangle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.75), radius: 1, x: 0, y: 0)
                        .frame(width: 3, height: 18)
                        .offset(x: markerX - 1.5, y: 0)
                }
            }
        }
        .frame(height: 20)
    }
}

private struct MetaTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
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
