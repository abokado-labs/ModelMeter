import AppKit
import SwiftUI
import WebKit

@MainActor
final class GeminiSignInController: ObservableObject {
    weak var webView: WKWebView?
    @Published var pageStatus = "Waiting for Gemini usage page"

    func markUsagePageLoaded() {
        pageStatus = "Gemini usage page loaded"
    }

    func confirmUsage() async throws -> GeminiUsageSnapshot {
        guard let webView else { throw GeminiSignInError.webViewMissing }
        do {
            return try await GeminiWebSession.shared.captureSnapshot(from: webView)
        } catch GeminiUsageError.noUsageFound {
            let text = try await pageSnapshot(from: webView)
            throw GeminiSignInError.usageMissing(GeminiUsageParser.diagnosticPreview(text))
        }
    }

    func diagnosticSummary() async -> String {
        guard let webView else { return "Gemini sign-in window is not ready" }
        do {
            let snapshot = try await pageSnapshot(from: webView)
            let preview = GeminiUsageParser.diagnosticPreview(snapshot)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ModelMeter-Gemini-Diagnostics.txt")
            try snapshot.write(to: fileURL, atomically: true, encoding: .utf8)
            return "Rendered page preview: \(preview). Full diagnostics: \(fileURL.path)"
        } catch {
            return error.localizedDescription
        }
    }

    private func pageSnapshot(from webView: WKWebView) async throws -> String {
        try await evaluateStringJavaScript(pageSnapshotScript, in: webView)
    }

    private func evaluateStringJavaScript(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    private var pageSnapshotScript: String {
        """
        (() => {
          const lines = [];
          const add = (value) => {
            if (!value) return;
            const text = String(value).replace(/\\s+/g, ' ').trim();
            if (!text) return;
            if (lines[lines.length - 1] === text) return;
            lines.push(text);
          };
          const walk = (root, depth = 0) => {
            if (!root || depth > 10) return;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
            let node;
            while ((node = walker.nextNode())) {
              if (node.nodeType === Node.TEXT_NODE) {
                add(node.nodeValue);
                continue;
              }
              if (node.nodeType !== Node.ELEMENT_NODE) continue;
              add(node.getAttribute('aria-label'));
              add(node.getAttribute('title'));
              add(node.getAttribute('alt'));
              add(node.getAttribute('data-test-id'));
              add(node.getAttribute('data-testid'));
              if (node.getAttribute('role') === 'progressbar') {
                add('progressbar ' + Array.from(node.attributes).map((attr) => attr.name + '=' + attr.value).join(' '));
              }
              if (node.shadowRoot) {
                add('SHADOW ROOT ' + (node.tagName || 'node'));
                walk(node.shadowRoot, depth + 1);
              }
            }
          };
          add('URL: ' + location.href);
          add('TITLE: ' + document.title);
          add('BODY INNER TEXT');
          add(document.body ? document.body.innerText : '');
          add('DOM AND SHADOW TEXT');
          walk(document.documentElement);
          const scripts = Array.from(document.scripts)
            .map((script) => script.textContent || '')
            .filter((value) => /usage|quota|limit|meter|balance|percent|percentage/i.test(value))
            .slice(0, 12);
          if (scripts.length) {
            add('SCRIPT CANDIDATES');
            scripts.forEach((value) => add(value.slice(0, 1200)));
          }
          const resources = performance.getEntriesByType('resource')
            .map((entry) => {
              try {
                const url = new URL(entry.name);
                return url.origin + url.pathname;
              } catch (_) {
                return entry.name;
              }
            })
            .filter((value, index, list) => list.indexOf(value) === index)
            .filter((value) => /usage|quota|limit|meter|balance|batchexecute|_/i.test(value))
            .slice(-120);
          if (resources.length) {
            add('RESOURCE CANDIDATES');
            resources.forEach(add);
          }
          return lines.join('\\n');
        })();
        """
    }
}

struct GeminiSignInView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    var onClose: () -> Void = {}
    @StateObject private var controller = GeminiSignInController()
    @State private var status = "Sign in to Gemini and wait for Usage Limits, then click Connect."
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gemini Sign In")
                        .font(.headline)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.pageStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Inspect Page") {
                    diagnose()
                }
                .disabled(isCompleting)
                Button("Connect") {
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
            GeminiWebView(controller: controller)
        }
        .frame(width: 920, height: 720)
    }

    private func diagnose() {
        guard !isCompleting else { return }
        isCompleting = true
        status = "Inspecting Gemini page..."
        Task {
            let summary = await controller.diagnosticSummary()
            await MainActor.run {
                status = summary
                isCompleting = false
            }
        }
    }

    private func connect() {
        guard !isCompleting else { return }
        isCompleting = true
        status = "Confirming Gemini usage page..."
        Task {
            do {
                let snapshot = try await controller.confirmUsage()
                await store.completeGeminiSignIn(snapshot: snapshot)
                await MainActor.run {
                    onClose()
                    dismiss()
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

private struct GeminiWebView: NSViewRepresentable {
    @ObservedObject var controller: GeminiSignInController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
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
        controller.webView = webView
        webView.load(URLRequest(url: URL(string: "https://gemini.google.com/usage")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        controller.webView = nsView
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var controller: GeminiSignInController?
        weak var parentWebView: WKWebView?
        private var popupWindow: NSPanel?
        private var popupWebView: WKWebView?

        init(controller: GeminiSignInController) {
            self.controller = controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView.url?.absoluteString.contains("gemini.google.com/usage") == true {
                DispatchQueue.main.async { [weak self] in
                    self?.controller?.markUsagePageLoaded()
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: CGRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
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
    }
}

enum GeminiSignInError: LocalizedError {
    case webViewMissing
    case usageMissing(String)

    var errorDescription: String? {
        switch self {
        case .webViewMissing:
            return "Gemini sign-in window is not ready"
        case .usageMissing(let preview):
            return "No Gemini usage percentages were found. Rendered page preview: \(preview)"
        }
    }
}
