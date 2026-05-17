import AppKit
import SwiftUI
import WebKit

@MainActor
final class ClaudeSignInController: ObservableObject {
    weak var webView: WKWebView?
    @Published var sessionCookieStatus = "Waiting for Claude session cookie"

    func markSessionCookieFound(expiryDate: Date?) {
        if let expiryDate {
            sessionCookieStatus = "Claude session cookie found, expires \(expiryDate.formatted(date: .abbreviated, time: .shortened))"
        } else {
            sessionCookieStatus = "Claude session cookie found"
        }
    }

    func extractCredentials() async throws -> (sessionKey: String, cfClearance: String, organizationID: String?) {
        guard let webView else {
            throw ClaudeSignInError.webViewMissing
        }

        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        let claudeCookies = cookies.filter { cookie in
            cookie.domain.contains("claude") || cookie.domain.contains("anthropic")
        }

        guard let sessionKeyCookie = claudeCookies.first(where: { $0.name == "sessionKey" }),
              !sessionKeyCookie.value.isEmpty
        else {
            let names = claudeCookies.map { "\($0.name)@\($0.domain)" }.sorted().joined(separator: ", ")
            throw ClaudeSignInError.sessionCookieMissing(names.isEmpty ? "no Claude cookies visible" : names)
        }

        let cfClearance = claudeCookies.first(where: { $0.name == "cf_clearance" })?.value ?? ""
        return (sessionKeyCookie.value, cfClearance, Self.organizationID(from: webView.url))
    }

    private static func organizationID(from url: URL?) -> String? {
        guard let url else { return nil }
        let pattern = #"/organizations/([0-9a-fA-F-]{36})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url.absoluteString, range: NSRange(url.absoluteString.startIndex..., in: url.absoluteString)),
              let range = Range(match.range(at: 1), in: url.absoluteString)
        else {
            return nil
        }
        return String(url.absoluteString[range])
    }
}

struct ClaudeSignInView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    var onClose: () -> Void = {}
    @StateObject private var controller = ClaudeSignInController()
    @State private var status = "Sign in to Claude. When Claude opens, click Use This Session."
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Sign In")
                        .font(.headline)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.sessionCookieStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use This Session") {
                    connect()
                }
                .disabled(isCompleting)
                .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    onClose()
                    dismiss()
                }
            }
            .padding(14)
            Divider()
            ClaudeWebView(controller: controller)
        }
        .frame(width: 920, height: 720)
    }

    private func connect() {
        guard !isCompleting else { return }
        isCompleting = true
        status = "Reading Claude session..."
        Task {
            do {
                let credentials = try await controller.extractCredentials()
                await MainActor.run {
                    status = credentials.organizationID == nil
                        ? "Found session. Discovering Claude organization..."
                        : "Found session and organization. Fetching Claude usage..."
                }
                await store.completeClaudeSignIn(
                    sessionKey: credentials.sessionKey,
                    cfClearance: credentials.cfClearance,
                    organizationID: credentials.organizationID
                )
                await MainActor.run {
                    if let error = store.claudeSnapshot.errorMessage {
                        status = error
                        isCompleting = false
                    } else {
                        onClose()
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    status = error.localizedDescription
                    isCompleting = false
                }
            }
        }
    }
}

private struct ClaudeWebView: NSViewRepresentable {
    @ObservedObject var controller: ClaudeSignInController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, cookieDomain: "claude.ai")
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = ClaudeUsageClient.safariUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.parentWebView = webView
        context.coordinator.startObservingCookies(for: configuration.websiteDataStore)
        controller.webView = webView

        let cookieStore = configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where cookie.domain.contains("claude") || cookie.domain.contains("anthropic") {
                group.enter()
                cookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
            }
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        controller.webView = nsView
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        weak var controller: ClaudeSignInController?
        let cookieDomain: String
        weak var parentWebView: WKWebView?
        private var popupWindow: NSPanel?
        private var popupWebView: WKWebView?
        private var foundCookie = false

        init(controller: ClaudeSignInController, cookieDomain: String) {
            self.controller = controller
            self.cookieDomain = cookieDomain
        }

        func startObservingCookies(for dataStore: WKWebsiteDataStore) {
            dataStore.httpCookieStore.add(self)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            checkForSessionCookie(in: cookieStore)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForSessionCookie(in: webView.configuration.websiteDataStore.httpCookieStore)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: CGRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
            popup.customUserAgent = ClaudeUsageClient.safariUserAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 520, height: 680),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Sign In"
            panel.contentView = popup
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            popupWindow = panel
            popupWebView = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView === popupWebView {
                popupWindow?.close()
                popupWindow = nil
                popupWebView = nil
            }
        }

        private func checkForSessionCookie(in cookieStore: WKHTTPCookieStore) {
            guard !foundCookie else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.foundCookie else { return }
                guard let cookie = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains(self.cookieDomain) }) else {
                    return
                }
                self.foundCookie = true
                DispatchQueue.main.async { [weak self] in
                    self?.controller?.markSessionCookieFound(expiryDate: cookie.expiresDate)
                }
            }
        }
    }
}

enum ClaudeSignInError: LocalizedError {
    case webViewMissing
    case sessionCookieMissing(String)

    var errorDescription: String? {
        switch self {
        case .webViewMissing:
            return "Claude sign-in window is not ready"
        case .sessionCookieMissing(let details):
            return "No Claude session cookie found yet (\(details)). Finish signing in, then click Use This Session."
        }
    }
}
