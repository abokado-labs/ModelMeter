import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var selectedTab: SettingsTab = .providers

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(selectedTab.title)
                            .font(.title2.weight(.semibold))
                        selectedContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .providers:
            providersTab
        case .menuBar:
            menuBarTab
        case .updatesPrivacy:
            updatesPrivacyTab
        }
    }

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Codex") {
                providerToggle(title: "Codex", isOn: $store.codexEnabled)
                Picker("Data source", selection: $store.codexDataSource) {
                    ForEach(CodexDataSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!store.codexEnabled)
                helperText(store.codexDataSource.detail)
                setupSteps([
                    "For Live ChatGPT, install Codex and sign in with your ChatGPT account using the normal Codex app or CLI.",
                    "Leave Codex home pointed at the folder containing `auth.json`, normally `~/.codex`.",
                    "For Local Codex files, Model Meter reads Codex session snapshots and `state_5.sqlite` from the same folder.",
                    "Click Save and Refresh after changing the data source or folder."
                ])
                TextField("Codex home", text: $store.codexHome)
                    .disabled(!store.codexEnabled)
                helperText("Live ChatGPT does not store your OpenAI password or API key; it uses Codex's existing `auth.json`. Local Codex files avoids network calls but may be stale or incomplete.")
                SettingValueRow(title: "Current source", value: store.snapshot.rateLimits?.sourceLabel ?? "Not refreshed")
                if let error = store.snapshot.errorMessage, store.codexEnabled {
                    statusText(error, style: .warning)
                }
            }

            SettingsSection("Claude") {
                providerToggle(title: "Claude", isOn: $store.claudeEnabled)
                setupSteps([
                    "Click Sign in with Claude and complete Claude's login flow.",
                    "When the Claude window reaches the signed-in Claude app, click Use This Session.",
                    "Click Save and Refresh to update the dashboard and menu bar."
                ])
                settingsButton("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark") {
                    ClaudeSignInWindowManager.shared.open(store: store)
                }
                .disabled(!store.claudeEnabled)
                TextField("Organization ID", text: $store.claudeOrganizationID)
                    .disabled(!store.claudeEnabled)
                SecureField("Session key", text: $store.claudeSessionKey)
                    .disabled(!store.claudeEnabled)
                settingsButton("Reset Claude credentials", systemImage: "key.slash") {
                    store.resetClaudeCredentials()
                }
                .disabled(!store.claudeEnabled)
                if let error = store.claudeSnapshot.errorMessage, store.claudeEnabled, (!store.claudeOrganizationID.isEmpty || !store.claudeSessionKey.isEmpty) {
                    statusText(error, style: .warning)
                }
            }

            SettingsSection("Gemini") {
                providerToggle(title: "Gemini", isOn: $store.geminiEnabled)
                GeminiSetupStatus(isConnected: geminiWebSessionAvailable, updatedAt: store.geminiSnapshot.updatedAt)
                    .disabled(!store.geminiEnabled)
                setupSteps([
                    "Click Sign in to Gemini. Model Meter opens its own secure WebKit login window, separate from Safari.",
                    "Sign in with the Google account that has your Gemini plan.",
                    "Wait until the Gemini Usage limits page is fully visible with Current usage and Weekly limit.",
                    "Click Connect in that window, then click Save and Refresh here."
                ])
                helperText("Gemini is refreshed from gemini.google.com/usage through the embedded WebKit session. Model Meter stores only parsed usage percentages and reset times, not your Google password.")
                HStack(spacing: 8) {
                    settingsButton("Sign in to Gemini", systemImage: "person.crop.circle.badge.checkmark") {
                        GeminiSignInWindowManager.shared.open(store: store)
                    }
                    settingsButton("Refresh Gemini", systemImage: "arrow.clockwise") {
                        store.refreshGeminiNow()
                    }
                    settingsButton("Reset Gemini session", systemImage: "trash") {
                        store.resetGeminiCredentials()
                    }
                }
                .disabled(!store.geminiEnabled)
                if let error = store.geminiSnapshot.errorMessage, store.geminiEnabled {
                    statusText(error, style: .warning)
                }
            }
        }
    }

    private var menuBarTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Provider Visibility") {
                Toggle("Show Codex in menu bar", isOn: $store.showCodexInMenuBar)
                    .disabled(!store.codexEnabled)
                Toggle("Show Claude in menu bar", isOn: $store.showClaudeInMenuBar)
                    .disabled(!store.claudeEnabled)
                Toggle("Show Gemini in menu bar", isOn: $store.showGeminiInMenuBar)
                    .disabled(!store.geminiEnabled)
            }

            SettingsSection("Display") {
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
            }

            SettingsSection("Warnings") {
                Toggle("Warn when usage is ahead of pace", isOn: $store.paceWarningsEnabled)
                helperText("Turns a menu bar value red when usage is ahead of the time elapsed in its reset window. The time marker remains visible on each bar.")

                Toggle("Warn when a provider reports an outage", isOn: $store.providerStatusWarningsEnabled)
                helperText("Checks official provider status sources about every 5 minutes. Status pages can lag real incidents, so this is a known-issue warning rather than a full health guarantee.")

                settingsButton("Refresh Provider Status", systemImage: "waveform.path.ecg") {
                    store.refreshProviderStatuses()
                }
                .disabled(!store.providerStatusWarningsEnabled)
            }

            SettingsSection("Preview") {
                SettingValueRow(title: "Current menu bar", value: store.menuTitle)
            }
        }
    }

    private var updatesPrivacyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection("Updates") {
                SettingValueRow(title: "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                settingsButton("Check for Updates", systemImage: "arrow.triangle.2.circlepath") {
                    checkForUpdates()
                }
            }

            SettingsSection("Support") {
                HStack(spacing: 8) {
                    settingsButton("Send Feedback", systemImage: "envelope") {
                        openFeedbackEmail(subject: "Model Meter feedback")
                    }
                    settingsButton("Request Feature", systemImage: "lightbulb") {
                        openFeedbackEmail(subject: "Model Meter feature request")
                    }
                }
                helperText("This opens your email app. Model Meter does not send feedback automatically.")
            }

            SettingsSection("Privacy") {
                helperText("Model Meter is a local-first usage tracker from Abokado Labs. It is not affiliated with OpenAI, Anthropic, Google, Gemini, Claude, ChatGPT, Codex, or Apple.")
                helperText("Codex can be refreshed either from Codex's existing ChatGPT OAuth session or from local Codex files, depending on the selected Codex data source. Claude credentials are stored in macOS Keychain. Gemini web usage is refreshed through an embedded WebKit session. Only parsed usage percentages and reset times are stored locally.")
                helperText("Provider status warnings are checked from official public status sources. Model Meter stores only the latest normalized status, source URL, and checked time.")
            }

            SettingsSection("Links") {
                HStack(spacing: 8) {
                    settingsButton("Privacy", systemImage: "lock.shield") { openDocument("PRIVACY") }
                    settingsButton("Licenses", systemImage: "doc.text") { openDocument("THIRD_PARTY_NOTICES") }
                    settingsButton("Website", systemImage: "globe") { openURL("https://abokadolabs.com/") }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Changes are applied when you save and refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            settingsButton("Save and Refresh", systemImage: "checkmark") {
                store.saveSettings()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var geminiWebSessionAvailable: Bool {
        !store.geminiSnapshot.items.isEmpty || GeminiWebSession.hasStoredSnapshot
    }

    private func providerToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle("Enable \(title)", isOn: isOn)
            .font(.headline)
    }


    private func setupSteps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("How to connect")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 7) {
                    Text("\(index + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func helperText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusText(_ message: String, style: StatusStyle) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(style == .success ? .green : .orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private func openFeedbackEmail(subject: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        App version: Model Meter \(version) (\(build))
        macOS version: \(osVersion)

        What happened / What would you like?


        Steps or context:


        Expected result:


        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "hello@abokadolabs.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum SettingsTab: CaseIterable, Identifiable {
    case providers
    case menuBar
    case updatesPrivacy

    var id: Self { self }

    var title: String {
        switch self {
        case .providers: return "Providers"
        case .menuBar: return "Menu Bar"
        case .updatesPrivacy: return "Updates & Support"
        }
    }

    var systemImage: String {
        switch self {
        case .providers: return "server.rack"
        case .menuBar: return "menubar.rectangle"
        case .updatesPrivacy: return "questionmark.circle"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeminiSetupStatus: View {
    let isConnected: Bool
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isConnected ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(isConnected ? "Gemini Web Session connected" : "Gemini sign-in required")
                    .font(.subheadline.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusText: String {
        if let updatedAt {
            return "Last captured " + updatedAt.formatted(date: .omitted, time: .shortened)
        }
        return "Sign in with Google in Model Meter's WebKit window. Safari is not required."
    }
}

private enum StatusStyle {
    case success
    case warning
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
        .frame(maxWidth: .infinity)
    }
}
