import Foundation
import WebKit

@MainActor
final class GeminiUsageClient {
    static func deleteImportedCredentials() {}

    func fetch() async throws -> GeminiUsageSnapshot {
        do {
            return try await GeminiWebSession.shared.refresh()
        } catch {
            if var stored = GeminiWebSession.loadStoredSnapshot(maxAge: nil) {
                stored.errorMessage = error.localizedDescription
                return stored
            }
            throw error
        }
    }
}

@MainActor
final class GeminiRenderedPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var didComplete = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        self.webView.navigationDelegate = self
    }

    func renderedText(from url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.webView.load(URLRequest(url: url))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                self.finish(.failure(GeminiUsageError.invalidResponse("Timed out while rendering Gemini usage page")))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureWhenUsageTextAppears()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func captureWhenUsageTextAppears() {
        Task { @MainActor in
            var lastSnapshot = ""
            for _ in 0..<24 {
                let snapshot = (try? await evaluateStringJavaScript(Self.pageSnapshotScript)) ?? ""
                if !snapshot.isEmpty { lastSnapshot = snapshot }
                if snapshot.localizedCaseInsensitiveContains("Usage limits")
                    && snapshot.localizedCaseInsensitiveContains("Current usage")
                    && snapshot.localizedCaseInsensitiveContains("Weekly limit") {
                    finish(.success(snapshot))
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            if !lastSnapshot.isEmpty {
                finish(.success(lastSnapshot))
            } else {
                finish(.failure(GeminiUsageError.noUsageFound))
            }
        }
    }

    private func evaluateStringJavaScript(_ script: String) async throws -> String {
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

    private func finish(_ result: Result<String, Error>) {
        guard !didComplete else { return }
        didComplete = true
        let continuation = continuation
        self.continuation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private static let pageSnapshotScript = """
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

enum GeminiUsageParser {
    private static let usageLabels: [(id: String, title: String, match: String)] = [
        ("current-usage", "Current usage", "current usage"),
        ("weekly-limit", "Weekly limit", "weekly limit")
    ]

    static func parse(_ text: String) -> [GeminiUsageItem] {
        if let items = parseCompactRenderedText(text), !items.isEmpty {
            return items
        }

        let lines = normalizedVisibleLines(from: text)
        guard !lines.isEmpty else { return [] }

        return usageLabels.compactMap { label in
            guard let parsed = parseUsage(label: label, lines: lines) else { return nil }
            return GeminiUsageItem(
                id: label.id,
                title: label.title,
                usedPercent: parsed.usedPercent,
                detail: parsed.detail
            )
        }
    }

    static func diagnosticPreview(_ text: String) -> String {
        let lines = normalizedVisibleLines(from: text)
        guard !lines.isEmpty else { return "No visible usage text was found." }
        return lines.prefix(18).joined(separator: " | ")
    }

    private static func parseCompactRenderedText(_ text: String) -> [GeminiUsageItem]? {
        let compact = compactRenderedUsageText(from: text)
        guard compact.localizedCaseInsensitiveContains("Usage limits"),
              compact.localizedCaseInsensitiveContains("Current usage"),
              compact.localizedCaseInsensitiveContains("Weekly limit")
        else { return nil }

        let suppressSyntheticReset = sourceUpdatedText(in: compact)?.localizedCaseInsensitiveContains("just now") == true
        var items: [GeminiUsageItem] = []
        if let current = parseCompactSection(
            id: "current-usage",
            title: "Current usage",
            startLabel: "Current usage",
            endLabels: ["Weekly limit", "gxu-weekly"],
            compact: compact,
            suppressSyntheticReset: suppressSyntheticReset
        ) {
            items.append(current)
        }
        if let weekly = parseCompactSection(
            id: "weekly-limit",
            title: "Weekly limit",
            startLabel: "Weekly limit",
            endLabels: ["Get 20x", "Upgrade", "DOM AND SHADOW TEXT", "SCRIPT CANDIDATES", "RESOURCE CANDIDATES"],
            compact: compact,
            suppressSyntheticReset: suppressSyntheticReset
        ) {
            items.append(weekly)
        }
        return items.isEmpty ? nil : items
    }

    private static func compactRenderedUsageText(from text: String) -> String {
        let bodyMarker = "BODY INNER TEXT"
        let bodyEndMarkers = ["DOM AND SHADOW TEXT", "SCRIPT CANDIDATES", "RESOURCE CANDIDATES"]
        var source = text
        if let bodyStart = text.range(of: bodyMarker, options: [.caseInsensitive]) {
            let afterBody = text[bodyStart.upperBound...]
            let bodyEnd = bodyEndMarkers
                .compactMap { afterBody.range(of: $0, options: [.caseInsensitive])?.lowerBound }
                .min()
            source = bodyEnd.map { String(afterBody[..<$0]) } ?? String(afterBody)
        }
        return collapseWhitespace(source)
    }

    private static func parseCompactSection(
        id: String,
        title: String,
        startLabel: String,
        endLabels: [String],
        compact: String,
        suppressSyntheticReset: Bool = false
    ) -> GeminiUsageItem? {
        guard let startRange = compact.range(of: startLabel, options: [.caseInsensitive]) else { return nil }
        let afterStart = compact[startRange.upperBound...]
        let sectionEnd = endLabels
            .compactMap { afterStart.range(of: $0, options: [.caseInsensitive])?.lowerBound }
            .min()
        let section = sectionEnd.map { String(afterStart[..<$0]) } ?? String(afterStart)
        guard let usedPercent = usedPercent(in: section) else { return nil }
        return GeminiUsageItem(
            id: id,
            title: title,
            usedPercent: usedPercent,
            detail: suppressSyntheticReset && usedPercent == 0 ? nil : resetDetail(in: section)
        )
    }

    private static func sourceUpdatedText(in compact: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"Updated\s+(.+?)(?=\s+Current usage|\s+gxu-currently|$)"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(compact.startIndex..., in: compact)
        guard let match = regex.firstMatch(in: compact, range: range),
              let valueRange = Range(match.range(at: 1), in: compact)
        else { return nil }
        return collapseWhitespace(String(compact[valueRange]))
    }

    private static func usedPercent(in section: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(100|\d{1,2})(?:\.\d+)?\s*%\s*used"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(section.startIndex..., in: section)
        guard let match = regex.firstMatch(in: section, range: range),
              let valueRange = Range(match.range(at: 1), in: section),
              let value = Double(section[valueRange])
        else { return nil }
        return min(max(value, 0), 100)
    }

    private static func resetDetail(in section: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(Resets(?: at| [A-Z][a-z]{2}| [A-Z][a-z]+)? [^%]+?)(?=\s+\d{1,3}(?:\.\d+)?\s*%\s*used|\s+Get |$)"#) else { return nil }
        let range = NSRange(section.startIndex..., in: section)
        guard let match = regex.firstMatch(in: section, range: range),
              let detailRange = Range(match.range(at: 1), in: section)
        else { return nil }
        return collapseWhitespace(String(section[detailRange]))
    }

    private static func parseUsage(
        label: (id: String, title: String, match: String),
        lines: [String]
    ) -> (usedPercent: Double, detail: String?)? {
        guard let labelIndex = lines.firstIndex(where: { normalizedLabel($0).contains(label.match) }) else {
            return nil
        }

        let searchEnd = min(lines.count, labelIndex + 10)
        let candidates = Array(lines[labelIndex..<searchEnd])
        guard let usedPercent = firstUsedPercent(in: candidates, label: label.match) else { return nil }
        let detail = firstResetDetail(in: candidates)
        return (usedPercent, detail)
    }

    private static func firstUsedPercent(in lines: [String], label: String) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("available"), !lower.contains("used") {
                continue
            }
            if let value = firstPercent(in: line) {
                return value
            }
        }
        return nil
    }

    private static func firstPercent(in line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d.])(100|\d{1,2})(?:\.\d+)?\s*%"#) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line),
              let value = Double(line[valueRange])
        else { return nil }
        return min(max(value, 0), 100)
    }

    private static func firstResetDetail(in lines: [String]) -> String? {
        lines.first { line in
            let lower = line.lowercased()
            return lower.contains("reset") || lower.contains("renews") || lower.contains("refresh")
        }
    }

    private static func normalizedVisibleLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .newlines)
            .map(collapseWhitespace)
            .filter { !$0.isEmpty && isVisibleUsageLine($0) }
    }

    private static func isVisibleUsageLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if line.contains("<") || line.contains(">") || line.contains("{") || line.contains("}") { return false }
        if lower.contains("script") || lower.contains("doctype") || lower.contains("google tag manager") { return false }
        if lower.contains("function(") || lower.contains("window.") || lower.contains("javascript") { return false }
        if line.count > 160 { return false }
        return true
    }

    private static func normalizedLabel(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: #"[^a-z ]"#, with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum GeminiUsageError: LocalizedError {
    case missingSession
    case cliCredentialsMissing
    case safariSnapshotMissing
    case notLoggedIn
    case expiredOAuthToken
    case noUsageFound
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Gemini session is not configured. Sign in from settings."
        case .cliCredentialsMissing:
            return "Gemini CLI credentials are not used for Gemini Web Session refresh."
        case .safariSnapshotMissing:
            return "Gemini sign-in required. Sign in to Gemini from settings, then refresh Model Meter."
        case .notLoggedIn:
            return "Gemini sign-in required. Sign in to Gemini from settings, then refresh Model Meter."
        case .expiredOAuthToken:
            return "Gemini sign-in required. Sign in to Gemini from settings, then refresh Model Meter."
        case .noUsageFound:
            return "Gemini web usage percentages were not found in the rendered usage page. Sign in again or open the usage page from settings."
        case .invalidResponse(let detail):
            return detail
        }
    }
}
