import AppKit
import SwiftUI

@MainActor
final class GeminiSignInWindowManager {
    static let shared = GeminiSignInWindowManager()

    private var window: NSWindow?

    private init() {}

    func open(store: UsageStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Gemini"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.contentView = NSHostingView(
            rootView: GeminiSignInView { [weak self] in
                self?.close()
            }
            .environmentObject(store)
        )
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}
