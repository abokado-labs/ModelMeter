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
                .frame(width: 520)
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
        popover.contentSize = NSSize(width: 390, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView()
                .environmentObject(store)
                .frame(width: 390, height: 560)
        )
    }

    private func configureContextMenu() {
        contextMenu.removeAllItems()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
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
        statusItem?.length = max(36, min(image.size.width + 12, 140))
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
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
                .frame(width: 520, height: 560)
        )
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 520, height: 560))
        window.minSize = NSSize(width: 500, height: 520)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
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
