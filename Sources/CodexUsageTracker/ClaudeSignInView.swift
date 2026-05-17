import SwiftUI
import WebKit

@MainActor
final class ClaudeSignInController: ObservableObject {
    weak var webView: WKWebView?

    func extractCredentials() async throws -> (sessionKey: String, cfClearance: String, organizationID: String?) {
        guard let webView else {
            throw ClaudeSignInError.webViewMissing
        }

        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        guard let sessionKey = cookies.first(where: { $0.name == "sessionKey" })?.value,
              !sessionKey.isEmpty
        else {
            throw ClaudeSignInError.sessionCookieMissing
        }

        let cfClearance = cookies.first(where: { $0.name == "cf_clearance" })?.value ?? ""
        return (sessionKey, cfClearance, Self.organizationID(from: webView.url))
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
    @State private var status = "Sign in to Claude. When the usage page loads, click Use This Session."
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
                    status = "Found Claude session. Connecting usage..."
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
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

enum ClaudeSignInError: LocalizedError {
    case webViewMissing
    case sessionCookieMissing

    var errorDescription: String? {
        switch self {
        case .webViewMissing:
            return "Claude sign-in window is not ready"
        case .sessionCookieMissing:
            return "No Claude session cookie found yet. Finish signing in, then click Use This Session."
        }
    }
}
