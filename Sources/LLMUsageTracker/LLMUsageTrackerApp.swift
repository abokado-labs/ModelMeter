import SwiftUI
import UserNotifications

@main
struct LLMUsageTrackerApp: App {
    @StateObject private var store: UsageStore

    init() {
        let store = UsageStore()
        _store = StateObject(wrappedValue: store)
        Task { @MainActor in
            store.start()
            await NotificationManager.shared.requestAuthorization()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
                .frame(width: 390, height: 560)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Image(nsImage: MenuBarImageRenderer.render(
            title: store.menuTitle,
            status: store.snapshot.status,
            iconMode: store.menuBarIconMode,
            fontSize: store.menuBarFontSize
        ))
    }
}
