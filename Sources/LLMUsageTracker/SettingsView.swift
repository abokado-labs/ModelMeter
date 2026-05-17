import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Form {
            Section("Codex data") {
                TextField("Codex home", text: $store.codexHome)
                Text("The app reads Codex session status snapshots and `state_5.sqlite` from this folder. Nothing is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Icon", selection: $store.menuBarIconMode) {
                    ForEach(MenuBarIconMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Font size", selection: $store.menuBarFontSize) {
                    ForEach(MenuBarFontSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                SettingValueRow(title: "Current menu bar", value: store.menuTitle)
                Text("The menu bar shows available balance for both providers: `C` for Codex and `Cl` for Claude.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude") {
                Button {
                    ClaudeSignInWindowManager.shared.open(store: store)
                } label: {
                    Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark")
                }
                TextField("Organization ID", text: $store.claudeOrganizationID)
                SecureField("Session key", text: $store.claudeSessionKey)
                if let error = store.claudeSnapshot.errorMessage, !store.claudeOrganizationID.isEmpty || !store.claudeSessionKey.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Claude uses the authenticated `claude.ai` usage endpoint. The session key is stored in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local token detail") {
                Stepper(value: $store.dailyLimit, in: 10_000...20_000_000, step: 10_000) {
                    SettingValueRow(title: "Daily token budget", value: UsageMath.tokenString(store.dailyLimit))
                }
                Text("The 5-hour and 7-day balances come from Codex `rate_limits`, not these local token budgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Refresh and alerts") {
                Stepper(value: $store.refreshInterval, in: 5...600, step: 5) {
                    SettingValueRow(title: "Refresh interval", value: "\(Int(store.refreshInterval))s")
                }
                Toggle("Notifications", isOn: $store.notificationsEnabled)
                Slider(value: $store.notificationThreshold, in: 0.5...1, step: 0.05) {
                    Text("Alert threshold")
                } minimumValueLabel: {
                    Text("50%")
                } maximumValueLabel: {
                    Text("100%")
                }
                SettingValueRow(
                    title: "Alert threshold",
                    value: UsageMath.percent(store.notificationThreshold)
                )
            }

            HStack {
                Spacer()
                Button("Save and Refresh") {
                    store.saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct SettingValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
