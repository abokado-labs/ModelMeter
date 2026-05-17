import AppKit
import SwiftUI

@MainActor
final class ClaudeSignInWindowManager {
    static let shared = ClaudeSignInWindowManager()

    private var panel: NSPanel?

    private init() {}

    func open(store: UsageStore) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Sign in to Claude"
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = NSHostingView(
            rootView: ClaudeSignInView { [weak self] in
                self?.close()
            }
            .environmentObject(store)
        )
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
