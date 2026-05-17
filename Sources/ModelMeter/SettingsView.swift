import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        Form {
            Section("Providers") {
                Toggle("Enable Codex", isOn: $store.codexEnabled)
                TextField("Codex home", text: $store.codexHome)
                    .disabled(!store.codexEnabled)
                Text("Codex reads local rate-limit snapshots and `state_5.sqlite` from this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable Claude", isOn: $store.claudeEnabled)
                Button {
                    ClaudeSignInWindowManager.shared.open(store: store)
                } label: {
                    Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(!store.claudeEnabled)
                TextField("Organization ID", text: $store.claudeOrganizationID)
                    .disabled(!store.claudeEnabled)
                SecureField("Session key", text: $store.claudeSessionKey)
                    .disabled(!store.claudeEnabled)
                Button(role: .destructive) {
                    store.resetClaudeCredentials()
                } label: {
                    Label("Reset Claude credentials", systemImage: "key.slash")
                }
                .disabled(!store.claudeEnabled)
                if let error = store.claudeSnapshot.errorMessage, store.claudeEnabled, (!store.claudeOrganizationID.isEmpty || !store.claudeSessionKey.isEmpty) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }


            Section("Menu bar") {
                Toggle("Show Codex in menu bar", isOn: $store.showCodexInMenuBar)
                    .disabled(!store.codexEnabled)
                Toggle("Show Claude in menu bar", isOn: $store.showClaudeInMenuBar)
                    .disabled(!store.claudeEnabled)

                Picker("Metric", selection: $store.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }

                Picker("Provider labels", selection: $store.menuBarLabelStyle) {
                    ForEach(MenuBarLabelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

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

                Toggle("Warn when ahead of pace", isOn: $store.paceWarningsEnabled)
                Text("Turns a menu bar value red when the selected usage metric is above the time elapsed in its reset window. The time marker remains visible on each bar either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingValueRow(title: "Current menu bar", value: store.menuTitle)
            }

            Section("About & Privacy") {
                SettingValueRow(title: "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Button {
                    checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                Text("Model Meter is a local-first usage tracker from Abokado Labs. It is not affiliated with OpenAI, Anthropic, Claude, ChatGPT, Codex, or Apple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Codex data is read from local files. Claude credentials are stored in macOS Keychain and are used only for Claude usage checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Privacy") { openDocument("PRIVACY") }
                    Button("Licenses") { openDocument("THIRD_PARTY_NOTICES") }
                    Button("Website") { openURL("https://abokadolabs.com/") }
                }
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

    private func checkForUpdates() {
        NSApp.sendAction(#selector(AppDelegate.checkForUpdates(_:)), to: nil, from: nil)
    }

    private func openDocument(_ name: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            openURL("https://abokadolabs.com/")
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
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
