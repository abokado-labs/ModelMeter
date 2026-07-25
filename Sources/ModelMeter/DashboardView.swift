import AppKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var store: UsageStore
    @State private var now = Date()
    @State private var historyRange: HistoryRange = .day
    let onResizeDrag: (CGSize) -> Void
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(onResizeDrag: @escaping (CGSize) -> Void = { _ in }) {
        self.onResizeDrag = onResizeDrag
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.showHistoryGraph, store.historyGraphPosition == .top {
                        historyGraph
                    }

                    ForEach(providerCards) { card in
                        ProviderZone(card: card)
                    }

                    if providerCards.isEmpty {
                        EmptyState(text: "All providers are switched off in settings.")
                    }

                    if store.showHistoryGraph, store.historyGraphPosition == .bottom {
                        historyGraph
                    }
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .bottomTrailing) {
            DashboardResizeHandle(onResizeDrag: onResizeDrag)
                .padding(.trailing, 5)
                .padding(.bottom, 5)
        }
        .onReceive(minuteTimer) { value in
            now = value
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsScene)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            SettingsWindowFocus.bringForwardSoon()
        }
    }

    private var historyGraph: some View {
        UsageHistorySection(
            entries: store.history,
            range: $historyRange,
            labelStyle: store.menuBarLabelStyle,
            visibleProviders: store.historyGraphProviders,
            shadeArea: store.shadeHistoryGraphArea,
            now: now
        )
    }

    private var providerCards: [ProviderCardModel] {
        [codexCard, claudeCard, geminiCard].compactMap { $0 }
    }

    private var providerStatusIssue: ProviderOperationalStatus? {
        guard store.providerStatusWarningsEnabled else { return nil }
        return store.providerStatuses.mostSevereIssue
    }

    private var codexCard: ProviderCardModel? {
        guard store.codexEnabled else { return nil }
        return ProviderCardModel(
            id: .codex,
            name: "Codex",
            enabled: store.codexEnabled,
            configured: true,
            status: store.snapshot.status,
            hasData: store.snapshot.rateLimits != nil,
            primary: codexFiveHourBalance,
            secondary: codexWeeklyBalance,
            connectionText: codexConnectionText,
            updatedText: codexUpdatedText,
            readingQuality: codexReadingQuality,
            message: codexMessage,
            operationalStatus: store.providerStatuses.codex
        )
    }

    private var codexFiveHourBalance: BalanceDisplay {
        guard let rateLimits = store.snapshot.rateLimits else {
            return .window(title: "5-hour", window: nil, tint: store.snapshot.status.color, now: now, resetDisplayMode: store.resetDisplayMode)
        }
        if let primary = rateLimits.primary {
            return .window(title: "5-hour", window: primary, tint: store.snapshot.status.color, now: now, resetDisplayMode: store.resetDisplayMode)
        }
        return .unavailable(
            title: "5-hour",
            tint: store.snapshot.status.color,
            message: "Temporarily unavailable from OpenAI",
            help: "OpenAI has temporarily paused five-hour usage tracking."
        )
    }

    private var codexWeeklyBalance: BalanceDisplay {
        guard let rateLimits = store.snapshot.rateLimits else {
            return .window(title: "Weekly", window: nil, tint: .purple, now: now, resetDisplayMode: store.resetDisplayMode)
        }
        if let secondary = rateLimits.secondary {
            return .window(title: "Weekly", window: secondary, tint: .purple, now: now, resetDisplayMode: store.resetDisplayMode)
        }
        return .unavailable(
            title: "Weekly",
            tint: .purple,
            message: "Not reported by OpenAI",
            help: "OpenAI did not include a weekly usage balance in this reading."
        )
    }

    private var claudeCard: ProviderCardModel? {
        guard store.claudeEnabled else { return nil }
        return ProviderCardModel(
            id: .claude,
            name: "Claude",
            enabled: store.claudeEnabled,
            configured: !store.claudeOrganizationID.isEmpty,
            status: store.claudeSnapshot.status,
            hasData: store.claudeSnapshot.rateLimits != nil,
            primary: .window(title: "5-hour", window: store.claudeSnapshot.rateLimits?.session, tint: store.claudeSnapshot.status.color, now: now, resetDisplayMode: store.resetDisplayMode),
            secondary: .window(title: "Weekly", window: store.claudeSnapshot.rateLimits?.weekly, tint: .purple, now: now, resetDisplayMode: store.resetDisplayMode),
            connectionText: claudeConnectionText,
            updatedText: claudeUpdatedText,
            readingQuality: claudeReadingQuality,
            message: claudeMessage,
            operationalStatus: store.providerStatuses.claude
        )
    }

    private var geminiCard: ProviderCardModel? {
        guard store.geminiEnabled else { return nil }
        return ProviderCardModel(
            id: .gemini,
            name: "Gemini",
            enabled: store.geminiEnabled,
            configured: geminiConfigured,
            status: store.geminiSnapshot.status,
            hasData: !store.geminiSnapshot.items.isEmpty,
            primary: .gemini(title: store.geminiSnapshot.primaryItem?.title ?? "Current usage", item: store.geminiSnapshot.primaryItem, tint: .blue, now: now, resetDisplayMode: store.resetDisplayMode),
            secondary: .gemini(title: store.geminiSnapshot.weeklyItem?.title ?? "Weekly limit", item: store.geminiSnapshot.weeklyItem, tint: .purple, now: now, resetDisplayMode: store.resetDisplayMode),
            connectionText: geminiConnectionText,
            updatedText: geminiUpdatedText,
            readingQuality: geminiReadingQuality,
            message: geminiMessage,
            operationalStatus: store.providerStatuses.gemini
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.snapshot.status.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(store.snapshot.status.color)
            Text("Model Meter")
                .font(.headline)
            if let issue = providerStatusIssue {
                Label(issue.severity.title, systemImage: issue.severity.symbolName)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(issue.severity.color)
                    .help(issue.plainExplanation)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Text(lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                SettingsWindowFocus.bringForwardSoon()
                DispatchQueue.main.async {
                    NSApp.sendAction(#selector(AppDelegate.closePopover(_:)), to: nil, from: nil)
                }
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

            Color.clear
                .frame(width: 24, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var codexUpdatedText: String {
        guard let updatedAt = store.snapshot.rateLimits?.capturedAt ?? store.snapshot.updatedAt else { return "Not refreshed" }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var codexMessage: String? {
        if let error = store.snapshot.errorMessage, !error.isEmpty { return error }
        return nil
    }

    private var codexConnectionText: String {
        guard let rateLimits = store.snapshot.rateLimits else { return "Waiting for Codex reading" }
        return "\(rateLimits.displayPlan) via \(rateLimits.sourceLabel)"
    }

    private var codexReadingQuality: ProviderReadingQuality {
        guard let rateLimits = store.snapshot.rateLimits else { return .unavailable }
        if store.snapshot.errorMessage != nil {
            return .lastGood(rateLimits.capturedAt)
        }
        if rateLimits.isLocalFallback {
            return .localFallback(rateLimits.sourceLabel)
        }
        return .freshLive(rateLimits.sourceLabel)
    }

    private var claudeUpdatedText: String {
        guard let updatedAt = store.claudeSnapshot.updatedAt else { return "Not refreshed" }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var geminiUpdatedText: String {
        guard let updatedAt = store.geminiSnapshot.updatedAt else { return "Not refreshed" }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    private var claudeAccountText: String {
        if store.claudeOrganizationID.isEmpty { return "Not connected" }
        if store.claudeSnapshot.errorMessage != nil { return "Needs attention" }
        if store.claudeSnapshot.rateLimits == nil { return "Configured" }
        return "Connected"
    }

    private var claudeConnectionText: String {
        if store.claudeOrganizationID.isEmpty { return "Not connected" }
        if store.claudeSnapshot.rateLimits == nil { return "Configured; waiting for Claude reading" }
        return "authenticated Claude usage"
    }

    private var claudeMessage: String? {
        if store.claudeOrganizationID.isEmpty {
            return "Connect Claude in settings to show the same 5-hour and weekly balance format."
        }
        return store.claudeSnapshot.errorMessage
    }

    private var claudeReadingQuality: ProviderReadingQuality {
        if store.claudeOrganizationID.isEmpty { return .notConfigured }
        guard store.claudeSnapshot.rateLimits != nil else { return .unavailable }
        if store.claudeSnapshot.errorMessage != nil {
            return .lastGood(store.claudeSnapshot.updatedAt)
        }
        return .freshLive("Authenticated Claude usage")
    }

    private var lastUpdatedText: String {
        let dates = [store.snapshot.updatedAt, store.claudeSnapshot.updatedAt, store.geminiSnapshot.updatedAt].compactMap { $0 }
        guard let latest = dates.max() else { return "Not refreshed yet" }
        return "Updated \(latest.formatted(date: .omitted, time: .shortened))"
    }

    private var geminiConfigured: Bool {
        !store.geminiSnapshot.items.isEmpty || GeminiWebSession.hasStoredSnapshot
    }

    private var geminiAccountText: String {
        if let accountPlan = store.geminiSnapshot.accountPlan, !accountPlan.isEmpty { return accountPlan }
        if let accountEmail = store.geminiSnapshot.accountEmail, !accountEmail.isEmpty { return accountEmail }
        return geminiConfigured ? "Connected" : "Not connected"
    }

    private var geminiConnectionText: String {
        if !geminiConfigured { return "Not connected" }
        if let accountPlan = store.geminiSnapshot.accountPlan, !accountPlan.isEmpty {
            return "\(accountPlan) via Gemini usage"
        }
        if let accountEmail = store.geminiSnapshot.accountEmail, !accountEmail.isEmpty {
            return "\(accountEmail) via Gemini usage"
        }
        return "Gemini usage page"
    }

    private var geminiMessage: String? {
        if store.geminiSnapshot.items.isEmpty, !geminiConfigured {
            return "Connect Gemini in settings to read usage percentages from gemini.google.com/usage."
        }
        if store.geminiSnapshot.items.isEmpty {
            return "Waiting for Gemini usage percentages."
        }
        return store.geminiSnapshot.errorMessage
    }

    private var geminiReadingQuality: ProviderReadingQuality {
        if !geminiConfigured { return .notConfigured }
        guard !store.geminiSnapshot.items.isEmpty else { return .unavailable }
        if store.geminiSnapshot.errorMessage != nil {
            return .lastGood(store.geminiSnapshot.updatedAt)
        }
        return .freshLive("Gemini usage page")
    }
}

private struct DashboardResizeHandle: View {
    let onResizeDrag: (CGSize) -> Void
    @State private var lastTranslation: CGSize = .zero

    var body: some View {
        ResizeGripMark()
            .stroke(
                Color.secondary.opacity(0.85),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastTranslation.width,
                            height: value.translation.height - lastTranslation.height
                        )
                        lastTranslation = value.translation
                        onResizeDrag(delta)
                    }
                    .onEnded { _ in
                        lastTranslation = .zero
                    }
            )
    }
}

private struct ResizeGripMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY - rect.height * 0.20))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.minY + rect.height * 0.34))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.60, y: rect.maxY - rect.height * 0.20))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.minY + rect.height * 0.60))
        return path
    }
}


private struct ProviderCardModel: Identifiable {
    let id: ProviderKind
    let name: String
    let enabled: Bool
    let configured: Bool
    let status: UsageStatus
    let hasData: Bool
    let primary: BalanceDisplay
    let secondary: BalanceDisplay
    let connectionText: String
    let updatedText: String
    let readingQuality: ProviderReadingQuality
    let message: String?
    let operationalStatus: ProviderOperationalStatus
}

private enum HistoryRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: Self { self }

    var title: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        }
    }

    var chartTitle: String {
        switch self {
        case .day: return "5-hour usage over 24h"
        case .week: return "5-hour usage over 7d"
        }
    }
}

private struct UsageHistorySection: View {
    let entries: [UsageHistoryEntry]
    @Binding var range: HistoryRange
    let labelStyle: MenuBarLabelStyle
    let visibleProviders: [ProviderKind]
    let shadeArea: Bool
    let now: Date

    private var graphData: HistoryGraphData {
        HistoryGraphData.make(
            entries: entries,
            visibleProviders: visibleProviders,
            rangeInterval: range.interval,
            now: now,
            gapThreshold: UsageHistoryStore.gapDisplayThreshold
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(range.chartTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Picker("History range", selection: $range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 112)
            }
            .padding(.trailing, UsageHistoryChart.plotTrailingInset)

            if !graphData.hasEnoughForChart {
                Text("Waiting for more readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else {
                UsageHistoryChart(graphData: graphData, range: range, shadeArea: shadeArea, now: now)
                    .frame(height: 118)
                HistorySummary(graphData: graphData, labelStyle: labelStyle)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UsageHistoryChart: View {
    let graphData: HistoryGraphData
    let range: HistoryRange
    let shadeArea: Bool
    let now: Date

    static let plotLeadingInset: CGFloat = 38
    static let plotTrailingInset: CGFloat = 4

    private let plotInsets = EdgeInsets(top: 6, leading: UsageHistoryChart.plotLeadingInset, bottom: 18, trailing: UsageHistoryChart.plotTrailingInset)
    private let axisLabelColor = Color.secondary.opacity(0.62)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = CGRect(
                x: plotInsets.leading,
                y: plotInsets.top,
                width: max(size.width - plotInsets.leading - plotInsets.trailing, 1),
                height: max(size.height - plotInsets.top - plotInsets.bottom, 1)
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(context: &context, plotRect: plotRect)
                    for series in graphData.series {
                        drawSeries(series, context: &context, plotRect: plotRect)
                    }
                }
                yAxisLabels(plotRect: plotRect)
                xAxisLabels(plotRect: plotRect)
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, plotRect: CGRect) {
        let gridColor = Color.secondary.opacity(0.18)
        for step in 0...4 {
            let y = plotRect.minY + plotRect.height * CGFloat(step) / 4
            var path = Path()
            path.move(to: CGPoint(x: plotRect.minX, y: y))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawSeries(_ series: HistoryGraphSeries, context: inout GraphicsContext, plotRect: CGRect) {
        let start = now.addingTimeInterval(-range.interval)
        let points = series.points.map { point -> CGPoint? in
            let xProgress = point.date.timeIntervalSince(start) / range.interval
            guard xProgress >= 0, xProgress <= 1 else { return nil }
            let yProgress = min(max(point.usedPercent / 100, 0), 1)
            let x = plotRect.minX + plotRect.width * CGFloat(xProgress)
            let y = plotRect.maxY - (plotRect.height * CGFloat(yProgress))
            return CGPoint(x: x, y: y)
        }

        guard points.contains(where: { $0 != nil }) else { return }

        for segment in series.segments where segment.isGap {
            guard let startPoint = chartPoint(at: segment.startIndex, in: points),
                  let endPoint = chartPoint(at: segment.endIndex, in: points) else { continue }
            let band = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: plotRect.minY,
                width: abs(endPoint.x - startPoint.x),
                height: plotRect.height
            )
            if band.width > 1 {
                var bandPath = Path()
                bandPath.addRect(band)
                context.fill(bandPath, with: .color(Color.secondary.opacity(0.035)))
            }
        }

        if shadeArea {
            for segment in series.segments where !segment.isGap {
                guard let startPoint = chartPoint(at: segment.startIndex, in: points),
                      let endPoint = chartPoint(at: segment.endIndex, in: points) else { continue }
                context.fill(
                    stepAreaPath(from: startPoint, to: endPoint, baseline: plotRect.maxY),
                    with: .color(series.provider.chartColor.opacity(0.10))
                )
            }
        }

        for segment in series.segments {
            guard let startPoint = chartPoint(at: segment.startIndex, in: points),
                  let endPoint = chartPoint(at: segment.endIndex, in: points) else { continue }
            let style = StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                lineJoin: .round,
                dash: segment.isGap ? [1.5, 4] : []
            )
            context.stroke(stepPath(from: startPoint, to: endPoint), with: .color(series.provider.chartColor), style: style)
        }

        for point in points.compactMap({ $0 }) {
            let rect = CGRect(x: point.x - 1.9, y: point.y - 1.9, width: 3.8, height: 3.8)
            context.fill(Path(ellipseIn: rect), with: .color(series.provider.chartColor))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -0.8, dy: -0.8)), with: .color(Color.primary.opacity(0.16)), lineWidth: 0.75)
        }
    }

    private func stepPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: end.x, y: start.y))
        path.addLine(to: end)
        return path
    }

    private func stepAreaPath(from start: CGPoint, to end: CGPoint, baseline: CGFloat) -> Path {
        var path = stepPath(from: start, to: end)
        path.addLine(to: CGPoint(x: end.x, y: baseline))
        path.addLine(to: CGPoint(x: start.x, y: baseline))
        path.closeSubpath()
        return path
    }

    private func chartPoint(at index: Int, in points: [CGPoint?]) -> CGPoint? {
        guard points.indices.contains(index) else { return nil }
        return points[index]
    }

    private func yAxisLabels(plotRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([100, 75, 50, 25, 0], id: \.self) { value in
                Text("\(value)%")
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(axisLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: plotInsets.leading - 8, alignment: .leading)
                    .position(
                        x: (plotInsets.leading - 8) / 2,
                        y: plotRect.maxY - (plotRect.height * CGFloat(value) / 100)
                    )
            }
        }
    }

    private func xAxisLabels(plotRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(xAxisTicks(now: now), id: \.offset) { tick in
                Text(tick.label)
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(axisLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .position(
                        x: plotRect.minX + plotRect.width * CGFloat(tick.offset),
                        y: plotRect.maxY + 12
                    )
            }
        }
    }

    private func xAxisTicks(now: Date = Date()) -> [(offset: Double, label: String)] {
        switch range {
        case .day:
            return [0, 0.5, 1].map { offset in
                let date = now.addingTimeInterval(-range.interval + (range.interval * offset))
                return (offset, date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
            }
        case .week:
            return [0, 1.0 / 3.0, 2.0 / 3.0, 1].map { offset in
                let date = now.addingTimeInterval(-range.interval + (range.interval * offset))
                return (offset, date.formatted(.dateTime.weekday(.abbreviated)))
            }
        }
    }

}

private struct HistorySummary: View {
    let graphData: HistoryGraphData
    let labelStyle: MenuBarLabelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 14) {
                ForEach(graphData.series.map(\.provider)) { provider in
                    HStack(spacing: 5) {
                        ProviderLegendMark(provider: provider, labelStyle: labelStyle)
                        Circle()
                            .fill(provider.chartColor)
                            .frame(width: 8, height: 8)
                    }
                    .accessibilityLabel(provider.rawValue)
                    .help(provider.rawValue)
                }
                Spacer(minLength: 0)
                if graphData.containsGap {
                    Text("Dotted = no readings >30m")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestGapCaption = graphData.latestGapCaption {
                Text(latestGapCaption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

private struct ProviderLegendMark: View {
    let provider: ProviderKind
    let labelStyle: MenuBarLabelStyle

    var body: some View {
        switch labelStyle {
        case .letters:
            Text(provider.shortLabel)
                .font(.caption.weight(.semibold))
        case .icons:
            if let image = provider.legendImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Text(provider.shortLabel)
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

private extension ProviderKind {
    var shortLabel: String {
        switch self {
        case .codex: return "C"
        case .claude: return "Cl"
        case .gemini: return "G"
        }
    }

    var chartColor: Color {
        switch self {
        case .codex: return .green
        case .claude: return .purple
        case .gemini: return .blue
        }
    }

    var legendImage: NSImage? {
        let resourceName: String
        switch self {
        case .codex:
            resourceName = "ChatGPT-Logo"
        case .claude:
            resourceName = "claude-transparent-custom"
        case .gemini:
            resourceName = "google-gemini-logomark-black-24439_32"
        }
        return Bundle.main.url(forResource: resourceName, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
    }
}

private struct BalanceDisplay {
    let title: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let progress: Double
    let elapsedProgress: Double?
    let detailText: String
    let detailHelpText: String?
    let tint: Color
    let availabilityMessage: String?

    var emptyCopy: BalanceDisplay {
        BalanceDisplay(
            title: title,
            usedPercent: nil,
            remainingPercent: nil,
            progress: 0,
            elapsedProgress: nil,
            detailText: "Waiting for status",
            detailHelpText: nil,
            tint: tint,
            availabilityMessage: nil
        )
    }

    static func window(title: String, window: RateLimitWindow?, tint: Color, now: Date, resetDisplayMode: ResetDisplayMode) -> BalanceDisplay {
        let reset = resetText(for: window, now: now, mode: resetDisplayMode)
        return BalanceDisplay(
            title: title,
            usedPercent: window?.usedPercent,
            remainingPercent: window?.remainingPercent,
            progress: window?.progress ?? 0,
            elapsedProgress: window?.elapsedProgress,
            detailText: reset.text,
            detailHelpText: reset.help,
            tint: tint,
            availabilityMessage: nil
        )
    }

    static func gemini(title: String, item: GeminiUsageItem?, tint: Color, now: Date, resetDisplayMode: ResetDisplayMode) -> BalanceDisplay {
        let detail = item?.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedReset = detail.flatMap { geminiResetText(from: $0, now: now, mode: resetDisplayMode) }
        return BalanceDisplay(
            title: title,
            usedPercent: item?.usedPercent,
            remainingPercent: item?.remainingPercent,
            progress: item.map { min(max($0.usedPercent / 100, 0), 1) } ?? 0,
            elapsedProgress: nil,
            detailText: formattedReset?.text ?? (detail?.isEmpty == false ? detail! : "Reset not reported"),
            detailHelpText: formattedReset?.help,
            tint: tint,
            availabilityMessage: nil
        )
    }

    static func unavailable(title: String, tint: Color, message: String, help: String) -> BalanceDisplay {
        BalanceDisplay(
            title: title,
            usedPercent: nil,
            remainingPercent: nil,
            progress: 0,
            elapsedProgress: nil,
            detailText: "",
            detailHelpText: help,
            tint: tint,
            availabilityMessage: message
        )
    }

    private static func resetText(for window: RateLimitWindow?, now: Date, mode: ResetDisplayMode) -> (text: String, help: String?) {
        guard let window else { return ("Waiting for status", nil) }
        if mode == .absolute {
            return (
                "Resets \(absoluteResetText(for: window.resetsAt, now: now))",
                window.resetsAt > now ? "Resets in \(relativeResetText(from: now, to: window.resetsAt))" : "Reset due"
            )
        }
        if window.resetsAt > now {
            return ("Resets in \(relativeResetText(from: now, to: window.resetsAt))", "Resets \(absoluteResetText(for: window.resetsAt, now: now))")
        }
        return ("Reset due", "Expected reset \(absoluteResetText(for: window.resetsAt, now: now))")
    }

    private static func geminiResetText(from detail: String, now: Date, mode: ResetDisplayMode) -> (text: String, help: String?)? {
        guard let resetDate = parseGeminiResetDate(detail, now: now) else { return nil }
        if mode == .absolute {
            return ("Resets \(absoluteResetText(for: resetDate, now: now))", resetDate > now ? "Resets in \(relativeResetText(from: now, to: resetDate))" : "Reset due")
        }
        if resetDate > now {
            return ("Resets in \(relativeResetText(from: now, to: resetDate))", "Resets \(absoluteResetText(for: resetDate, now: now))")
        }
        return ("Reset due", "Expected reset \(absoluteResetText(for: resetDate, now: now))")
    }

    private static func parseGeminiResetDate(_ detail: String, now: Date) -> Date? {
        if let date = parseGeminiMonthDayReset(detail, now: now) {
            return date
        }
        if let time = parseGeminiTimeOnlyReset(detail) {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
            guard let sameDay = Calendar.current.date(from: components) else { return nil }
            return sameDay >= now ? sameDay : Calendar.current.date(byAdding: .day, value: 1, to: sameDay)
        }
        return nil
    }

    private static func parseGeminiMonthDayReset(_ detail: String, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Resets' MMM d 'at' h:mm a yyyy"
        let year = Calendar.current.component(.year, from: now)
        return formatter.date(from: "\(detail) \(year)")
    }

    private static func parseGeminiTimeOnlyReset(_ detail: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Resets at' h:mm a"
        return formatter.date(from: detail)
    }

    private static func relativeResetText(from now: Date, to date: Date) -> String {
        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }

    private static func absoluteResetText(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day,
           days > 0,
           days < 7 {
            return "on \(weekdayText(for: date)) \(ordinalDayText(for: date)) at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "on \(date.formatted(.dateTime.month(.abbreviated))) \(ordinalDayText(for: date)) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    private static func weekdayText(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private static func ordinalDayText(for date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch day {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}

private struct ProviderZone: View {
    let card: ProviderCardModel

    private var providerHealth: ProviderHealth {
        if card.enabled == false { return .disabled }
        if card.configured == false { return .notConfigured }
        if card.hasData == false { return .waiting }
        return .healthy(card.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(providerHealth.title, systemImage: providerHealth.symbolName)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(providerHealth.color)
                    .help(providerHealth.title)
            }

            HStack(spacing: 10) {
                BalanceTile(balance: card.configured ? card.primary : card.primary.emptyCopy)
                BalanceTile(balance: card.configured ? card.secondary : card.secondary.emptyCopy)
            }

            ConnectionStatusLine(
                text: card.connectionText,
                updatedText: card.updatedText,
                quality: card.readingQuality,
                operationalStatus: card.operationalStatus
            )

            if card.operationalStatus.hasIssue {
                ProviderStatusContextLine(
                    status: card.operationalStatus,
                    quality: card.readingQuality
                )
            }

            if let message = card.message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(card.configured ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct ConnectionStatusLine: View {
    let text: String
    let updatedText: String
    let quality: ProviderReadingQuality
    let operationalStatus: ProviderOperationalStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption2)
                .foregroundStyle(symbolColor)
                .fixedSize()
            Text(trustText)
                .font(.caption2)
                .foregroundStyle(trustTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(updatedText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(helpText)
    }

    private var readingText: String {
        quality.compactText
    }

    private var trustText: String {
        return readingText
    }

    private var trustTextColor: Color {
        .secondary
    }

    private var symbolName: String {
        quality.symbolName
    }

    private var symbolColor: Color {
        quality.color
    }

    private var helpText: String {
        var lines = ["\(quality.displayText). Source: \(text). Updated \(updatedText)."]
        if operationalStatus.hasIssue || operationalStatus.severity == .operational {
            lines.append(operationalStatus.plainExplanation)
        }
        return lines.joined(separator: " ")
    }
}

private struct ProviderStatusContextLine: View {
    let status: ProviderOperationalStatus
    let quality: ProviderReadingQuality

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.75))
                .fixedSize()
            Text(status.contextText(for: quality))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .help(status.plainExplanation)
    }
}

private struct BalanceTile: View {
    let balance: BalanceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(balance.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let availabilityMessage = balance.availabilityMessage {
                Text(availabilityMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .help(balance.detailHelpText ?? availabilityMessage)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Used")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(balance.usedPercent.map { UsageMath.wholePercent($0) } ?? "--")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Available")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(balance.remainingPercent.map { UsageMath.wholePercent($0) } ?? "--")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                PaceBar(balance: balance)
                Text(balance.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(balance.detailHelpText ?? balance.detailText)
            }
        }
        .frame(minWidth: 136, maxWidth: .infinity, alignment: .leading)
    }
}


private struct PaceBar: View {
    let balance: BalanceDisplay

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = balance.progress
            let marker = balance.elapsedProgress ?? 0
            let markerX = min(max(width * marker, 4), max(width - 4, 4))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.24))
                    .frame(height: 7)
                    .offset(y: 6)
                Capsule()
                    .fill(balance.tint)
                    .frame(width: max(2, width * progress), height: 7)
                    .offset(y: 6)
                if balance.elapsedProgress != nil {
                    Rectangle()
                        .fill(Color.white)
                        .overlay(Rectangle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.75), radius: 1, x: 0, y: 0)
                        .frame(width: 3, height: 18)
                        .offset(x: markerX - 1.5, y: 0)
                }
            }
        }
        .frame(height: 18)
    }
}

private struct MetaTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
