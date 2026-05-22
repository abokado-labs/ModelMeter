import AppKit
import Combine
import Sparkle
import SwiftUI
import UserNotifications

@main
struct ModelMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.store)
                .frame(width: 640, height: 560)
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
    private let popoverWidth: CGFloat = 390
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureUpdater()
        configurePopover()
        configureContextMenu()
        configureStatusItem()
        bindStatusItem()

        store.start()
        Task { @MainActor in
            await NotificationManager.shared.requestAuthorization()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
            rootView: DashboardView()
                .environmentObject(store)
                .frame(width: popoverWidth)
        )
    }

    private func dashboardPopoverSize() -> NSSize {
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
        let emptyHeight: CGFloat = providerHeights.isEmpty ? 72 : 0
        let rawHeight = chromeHeight + contentPadding + providerGap + emptyHeight + providerHeights.reduce(0, +)
        return NSSize(width: popoverWidth, height: clampedPopoverHeight(rawHeight))
    }


    private func providerHeight(hasMessage: Bool) -> CGFloat {
        176 + (hasMessage ? 46 : 0)
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

    private func clampedPopoverHeight(_ rawHeight: CGFloat) -> CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maximumHeight = max(420, visibleHeight - 80)
        return min(max(rawHeight.rounded(.up), 420), maximumHeight)
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
            button.toolTip = "Model Meter"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
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
            iconMode: store.menuBarIconMode,
            fontSize: store.menuBarFontSize,
            labelStyle: store.menuBarLabelStyle,
            codexWarning: store.codexMenuMetricAheadOfPace,
            claudeWarning: store.claudeMenuMetricAheadOfPace
        )
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.image = image
        button.imagePosition = .imageOnly
        statusItem?.length = max(36, min(image.size.width + 12, 190))
        button.toolTip = "Model Meter"
    }

    private func menuBarPlainTitle() -> String {
        var parts: [String] = []
        if store.codexEnabled && store.showCodexInMenuBar {
            let label = store.codexMenuMetricAheadOfPace ? "C!" : "C"
            let value = store.menuBarMetric.value(from: store.snapshot).map { UsageMath.wholePercent($0) } ?? "--"
            parts.append("\(label) \(value)")
        }

        if store.claudeEnabled && store.showClaudeInMenuBar {
            let label = store.claudeMenuMetricAheadOfPace ? "Cl!" : "Cl"
            let value = store.menuBarMetric.value(from: store.claudeSnapshot).map { UsageMath.wholePercent($0) } ?? "--"
            parts.append("\(label) \(value)")
        }

        if store.geminiEnabled && store.showGeminiInMenuBar {
            let value = store.menuBarMetric.value(from: store.geminiSnapshot).map { UsageMath.wholePercent($0) } ?? "--"
            parts.append("G \(value)")
        }

        return parts.isEmpty ? "MM" : parts.joined(separator: "  ")
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
            popover.contentSize = dashboardPopoverSize()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func resizeVisiblePopoverIfNeeded() {
        guard popover.isShown else { return }
        popover.contentSize = dashboardPopoverSize()
    }

    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: SettingsView()
                .environmentObject(store)
                .frame(width: 640, height: 560)
        )
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 640, height: 560))
        window.minSize = NSSize(width: 560, height: 500)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings(_ sender: Any?) {
        popover.performClose(sender)
        showSettingsWindow()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
}
