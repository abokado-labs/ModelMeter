import Foundation
import WebKit

@MainActor
final class GeminiWebSession {
    static let shared = GeminiWebSession()

    private static let usageURL = URL(string: "https://gemini.google.com/usage")!
    private static let snapshotKey = "geminiWebSessionSnapshot"
    private let dataStore = WKWebsiteDataStore.default()
    private var activeWebView: WKWebView?
    private var activeLoader: GeminiRenderedPageLoader?

    static var hasStoredSnapshot: Bool {
        loadStoredSnapshot(maxAge: nil) != nil
    }

    private init() {}

    func refresh() async throws -> GeminiUsageSnapshot {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.customUserAgent = ClaudeUsageClient.safariUserAgent
        let loader = GeminiRenderedPageLoader(webView: webView)
        activeWebView = webView
        activeLoader = loader
        defer {
            activeWebView = nil
            activeLoader = nil
        }

        let text = try await loader.renderedText(from: Self.usageURL)
        return try captureSnapshot(fromRenderedText: text, currentURL: webView.url)
    }

    func captureSnapshot(from webView: WKWebView) async throws -> GeminiUsageSnapshot {
        let text = try await evaluateStringJavaScript(Self.pageSnapshotScript, in: webView)
        return try captureSnapshot(fromRenderedText: text, currentURL: webView.url)
    }

    func clearSession() async {
        Self.clearStoredSnapshot()
        let records = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                continuation.resume(returning: records)
            }
        }
        let matchingRecords = records.filter { record in
            let name = record.displayName.lowercased()
            return name.contains("google") || name.contains("gemini") || name.contains("gstatic")
        }
        guard !matchingRecords.isEmpty else { return }
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matchingRecords) {
                continuation.resume()
            }
        }
    }

    static func loadStoredSnapshot(maxAge: TimeInterval? = 12 * 60 * 60) -> GeminiUsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.items.isEmpty
        else { return nil }
        if let maxAge, Date().timeIntervalSince(payload.updatedAt) > maxAge {
            return nil
        }
        return GeminiUsageSnapshot(
            items: payload.items.map { item in
                GeminiUsageItem(
                    id: item.id,
                    title: item.title,
                    usedPercent: min(max(item.usedPercent, 0), 100),
                    detail: item.detail
                )
            },
            updatedAt: payload.updatedAt,
            errorMessage: nil,
            accountEmail: nil,
            accountPlan: payload.source
        )
    }

    static func clearStoredSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    private func captureSnapshot(fromRenderedText text: String, currentURL: URL?) throws -> GeminiUsageSnapshot {
        let items = GeminiUsageParser.parse(text)
        guard !items.isEmpty else {
            if isSignInState(renderedText: text, currentURL: currentURL) {
                throw GeminiUsageError.notLoggedIn
            }
            throw GeminiUsageError.noUsageFound
        }

        let snapshot = GeminiUsageSnapshot(
            items: items,
            updatedAt: Date(),
            errorMessage: nil,
            accountEmail: nil,
            accountPlan: "Gemini Web Session"
        )
        Self.store(snapshot)
        return snapshot
    }

    private func isSignInState(renderedText: String, currentURL: URL?) -> Bool {
        let compact = renderedText.lowercased()
        let url = currentURL?.absoluteString.lowercased() ?? ""
        return url.contains("accounts.google.com")
            || url.contains("signin")
            || compact.contains("sign in")
            || compact.contains("choose an account")
    }

    private static func store(_ snapshot: GeminiUsageSnapshot) {
        let payload = Payload(
            updatedAt: snapshot.updatedAt ?? Date(),
            source: "Gemini Web Session",
            items: snapshot.items.map { item in
                Item(id: item.id, title: item.title, usedPercent: item.usedPercent, detail: item.detail)
            }
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
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

    private struct Payload: Codable {
        let updatedAt: Date
        let source: String
        let items: [Item]
    }

    private struct Item: Codable {
        let id: String
        let title: String
        let usedPercent: Double
        let detail: String?
    }

    static let pageSnapshotScript = """
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
          return lines.join('\\n');
        })();
        """
}
