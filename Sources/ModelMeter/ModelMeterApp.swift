import AppKit
import Combine
import Sparkle
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let openSettingsScene = Notification.Name("ModelMeterOpenSettingsScene")
}

@MainActor
enum SettingsWindowFocus {
    static func bringForwardSoon(retries: Int = 8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            bringForward(retries: retries)
        }
    }

    private static func bringForward(retries: Int) {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow = NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("settings") }) {
            settingsWindow.level = .normal
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            bringForward(retries: retries - 1)
        }
    }
}

@main
struct ModelMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            MeterSettingsRoot {
                SettingsView()
                    .environmentObject(appDelegate.store)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = UsageStore()

    private var statusItem: NSStatusItem?
    private var updaterController: SPUStandardUpdaterController?
    private let popover = NSPopover()
    private let contextMenu = NSMenu()
    private let defaultDashboardWidth: CGFloat = 390
    private let minimumDashboardWidth: CGFloat = 360
    private let minimumDashboardHeight: CGFloat = 420
    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureTelemetry()
        configureUpdater()
        configurePopover()
        configureContextMenu()
        configureStatusItem()
        configureKeyboardShortcuts()
        bindStatusItem()

        store.start()
        Task { @MainActor in
            await NotificationManager.shared.requestAuthorization()
        }
    }

    private func configureTelemetry() {
        let bundle = Bundle.main
        TelemetryClient.configure(
            appID: "model-meter",
            bundleID: bundle.bundleIdentifier ?? "com.bobkitchen.ModelMeter",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        statusItem = nil
    }

    private func configureUpdater() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = dashboardPopoverSize()
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(onResizeDrag: { [weak self] delta in
                Task { @MainActor in
                    self?.resizeDashboardPopover(by: delta)
                }
            })
            .environmentObject(store)
            .frame(minWidth: minimumDashboardWidth, minHeight: minimumDashboardHeight)
        )
    }

    private func dashboardPopoverSize() -> NSSize {
        if let savedSize = SettingsStore.shared.popoverSize {
            return clampedDashboardSize(NSSize(width: savedSize.width, height: savedSize.height))
        }
        return defaultDashboardPopoverSize()
    }

    private func defaultDashboardPopoverSize() -> NSSize {
        var providerHeights: [CGFloat] = []

        if store.codexEnabled {
            providerHeights.append(providerHeight(hasMessage: hasVisibleMessage(store.snapshot.errorMessage)))
        }
        if store.claudeEnabled {
            providerHeights.append(providerHeight(hasMessage: hasVisibleMessage(claudePopoverMessage)))
        }
        if store.geminiEnabled {
            providerHeights.append(providerHeight(hasMessage: hasVisibleMessage(store.geminiSnapshot.errorMessage)))
        }

        let providerGap = CGFloat(max(providerHeights.count - 1, 0)) * 10
        let chromeHeight: CGFloat = 104
        let contentPadding: CGFloat = 24
        let historyHeight: CGFloat = store.showHistoryGraph ? 138 : 0
        let emptyHeight: CGFloat = providerHeights.isEmpty ? 72 : 0
        let rawHeight = chromeHeight + contentPadding + historyHeight + providerGap + emptyHeight + providerHeights.reduce(0, +)
        return clampedDashboardSize(NSSize(width: defaultDashboardWidth, height: rawHeight.rounded(.up)))
    }


    private func providerHeight(hasMessage: Bool) -> CGFloat {
        150 + (hasMessage ? 46 : 0)
    }

    private func hasVisibleMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var claudePopoverMessage: String? {
        if store.claudeOrganizationID.isEmpty {
            return "Connect Claude in settings to show the same 5-hour and weekly balance format."
        }
        return store.claudeSnapshot.errorMessage
    }

    private func clampedDashboardSize(_ size: NSSize) -> NSSize {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        let visibleWidth = NSScreen.main?.visibleFrame.width ?? 1_200
        let maximumHeight = max(minimumDashboardHeight, visibleHeight - 80)
        let maximumWidth = max(minimumDashboardWidth, min(760, visibleWidth - 80))
        return NSSize(
            width: min(max(size.width.rounded(.up), minimumDashboardWidth), maximumWidth),
            height: min(max(size.height.rounded(.up), minimumDashboardHeight), maximumHeight)
        )
    }

    private func configureContextMenu() {
        contextMenu.removeAllItems()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)
        let updatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = self
        contextMenu.addItem(updatesItem)
        contextMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 64)
        if let button = item.button {
            button.title = "MM"
            button.toolTip = menuBarToolTip()
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
        }
    }

    private func configureKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else { return event }
            guard event.charactersIgnoringModifiers == "," else { return event }
            self.openSettings(event)
            return nil
        }
    }

    private func bindStatusItem() {
        store.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItem()
                    self?.resizeVisiblePopoverIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let image = MenuBarImageRenderer.render(
            title: menuBarPlainTitle(),
            status: store.snapshot.status,
            iconMode: store.menuBarDisplayMode == .iconOnly ? .statusIcon : store.menuBarIconMode,
            fontSize: store.menuBarFontSize,
            labelStyle: store.menuBarLabelStyle,
            codexWarning: codexMenuWarning,
            claudeWarning: claudeMenuWarning,
            geminiWarning: geminiMenuWarning
        )
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.image = image
        button.imagePosition = .imageOnly
        statusItem?.length = max(36, min(image.size.width + 12, 190))
        button.toolTip = menuBarToolTip()
    }

    private func menuBarPlainTitle() -> String {
        switch store.menuBarDisplayMode {
        case .allProviders:
            return menuBarParts().map(\.text).joined(separator: "  ").ifEmpty("MM")
        case .lowestAvailable:
            return lowestAvailableMenuPart()?.text ?? "MM"
        case .warningsOnly:
            return menuBarParts().filter(\.warning).map(\.text).joined(separator: "  ").ifEmpty("OK")
        case .iconOnly:
            return ""
        }
    }

    private func menuBarParts() -> [MenuBarPart] {
        var parts: [MenuBarPart] = []
        if store.codexEnabled && store.showCodexInMenuBar {
            let value = store.menuBarMetric.value(from: store.snapshot).map { UsageMath.wholePercent($0) } ?? "--"
            parts.append(MenuBarPart(provider: .codex, label: "C", value: value, warning: codexMenuWarning))
        }

        if store.claudeEnabled && store.showClaudeInMenuBar {
            let value = store.menuBarMetric.value(from: store.claudeSnapshot).map { UsageMath.wholePercent($0) } ?? "--"
            parts.append(MenuBarPart(provider: .claude, label: "Cl", value: value, warning: claudeMenuWarning))
        }

        if store.geminiEnabled && store.showGeminiInMenuBar {
            let value = store.menuBarMetric.value(from: store.geminiSnapshot).map { UsageMath.wholePercent($0) } ?? "--"
            parts.append(MenuBarPart(provider: .gemini, label: "G", value: value, warning: geminiMenuWarning))
        }

        return parts
    }

    private func lowestAvailableMenuPart() -> MenuBarPart? {
        let metric = availableMetricForCompactMode()
        return menuBarParts()
            .compactMap { part -> (part: MenuBarPart, value: Double)? in
                guard let value = menuBarValue(provider: part.provider, metric: metric) else { return nil }
                return (
                    MenuBarPart(
                        provider: part.provider,
                        label: part.label,
                        value: UsageMath.wholePercent(value),
                        warning: part.warning
                    ),
                    value
                )
            }
            .min { $0.value < $1.value }?
            .part
    }

    private func availableMetricForCompactMode() -> MenuBarMetric {
        switch store.menuBarMetric {
        case .fiveHourUsed, .fiveHourAvailable:
            return .fiveHourAvailable
        case .sevenDayUsed, .sevenDayAvailable:
            return .sevenDayAvailable
        }
    }

    private func menuBarValue(provider: ProviderKind, metric: MenuBarMetric) -> Double? {
        switch provider {
        case .codex:
            return metric.value(from: store.snapshot)
        case .claude:
            return metric.value(from: store.claudeSnapshot)
        case .gemini:
            return metric.value(from: store.geminiSnapshot)
        }
    }

    private var codexMenuWarning: Bool {
        store.codexMenuMetricAheadOfPace || store.codexMenuStatusWarning
    }

    private var claudeMenuWarning: Bool {
        store.claudeMenuMetricAheadOfPace || store.claudeMenuStatusWarning
    }

    private var geminiMenuWarning: Bool {
        store.geminiMenuMetricAheadOfPace || store.geminiMenuStatusWarning
    }

    private func menuBarToolTip() -> String {
        var lines = ["Model Meter"]
        if store.providerStatusWarningsEnabled {
            for status in [store.providerStatuses.codex, store.providerStatuses.claude, store.providerStatuses.gemini] where status.hasIssue {
                lines.append(status.plainExplanation)
            }
        }
        return lines.joined(separator: "\n")
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(sender)
            statusItem?.menu = contextMenu
            sender.performClick(nil)
            statusItem?.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            TelemetryClient.record(.popoverOpened)
            popover.contentSize = dashboardPopoverSize()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func resizeVisiblePopoverIfNeeded() {
        guard popover.isShown else { return }
        if SettingsStore.shared.popoverSize == nil {
            popover.contentSize = defaultDashboardPopoverSize()
        }
    }

    private func resizeDashboardPopover(by delta: CGSize) {
        guard popover.isShown else { return }
        let current = popover.contentSize
        let next = clampedDashboardSize(NSSize(
            width: current.width + delta.width,
            height: current.height + delta.height
        ))
        popover.contentSize = next
        SettingsStore.shared.popoverSize = CGSize(width: next.width, height: next.height)
    }

    @objc func openSettings(_ sender: Any?) {
        TelemetryClient.record(.settingsOpened)
        NSApp.activate(ignoringOtherApps: true)
        _ = popover.contentViewController?.view
        NotificationCenter.default.post(name: .openSettingsScene, object: nil)
        SettingsWindowFocus.bringForwardSoon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.popover.performClose(sender)
        }
    }

    @objc func closePopover(_ sender: Any?) {
        popover.performClose(sender)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
}

private struct MenuBarPart {
    let provider: ProviderKind
    let label: String
    let value: String
    let warning: Bool

    var text: String {
        "\(label)\(warning ? "!" : "") \(value)"
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
