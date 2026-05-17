import SwiftUI
import UserNotifications

@main
struct CodexUsageTrackerApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
                .frame(width: 390, height: 560)
                .task {
                    store.start()
                    await NotificationManager.shared.requestAuthorization()
                }
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
