import Foundation

struct ProviderStatusClient {
    private let decoder = JSONDecoder()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAll() async -> ProviderStatusSnapshot {
        async let openAI = fetchStatusPage(
            provider: .codex,
            url: URL(string: "https://status.openai.com/api/v2/summary.json")!,
            matching: ["codex", "chatgpt", "api", "login"]
        )
        async let claude = fetchStatusPage(
            provider: .claude,
            url: URL(string: "https://status.claude.com/api/v2/summary.json")!,
            matching: ["api", "claude", "console", "web"]
        )
        async let gemini = fetchGoogleWorkspaceStatus()

        return ProviderStatusSnapshot(
            codex: await openAI,
            claude: await claude,
            gemini: await gemini,
            updatedAt: Date()
        )
    }

    private func fetchStatusPage(provider: ProviderKind, url: URL, matching keywords: [String]) async -> ProviderOperationalStatus {
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLog.status.warning("\(provider.rawValue, privacy: .public) status fetch returned a non-HTTP response")
                return .unknown(provider: provider, source: url.absoluteString)
            }
            AppLog.status.info("\(provider.rawValue, privacy: .public) status HTTP status=\(httpResponse.statusCode, privacy: .public)")
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .unknown(provider: provider, source: url.absoluteString)
            }

            let summary = try decoder.decode(StatusPageSummary.self, from: data)
            let matchingComponents = summary.components.filter { component in
                let name = component.name.lowercased()
                return keywords.contains { name.contains($0) }
            }
            let componentsToEvaluate = matchingComponents.isEmpty ? summary.components : matchingComponents
            let componentStates = componentsToEvaluate.map { ProviderStatusSeverity(statusPageStatus: $0.status) }
            let severity = componentStates.max() ?? ProviderStatusSeverity(statusPageIndicator: summary.status.indicator)
            let message = issueMessage(summary: summary, components: matchingComponents, severity: severity)
            AppLog.status.info("\(provider.rawValue, privacy: .public) status severity=\(severity.rawValue, privacy: .public); message=\(message ?? "none", privacy: .public)")
            return ProviderOperationalStatus(
                provider: provider,
                severity: severity,
                message: message,
                source: url.absoluteString,
                checkedAt: Date()
            )
        } catch {
            AppLog.status.error("\(provider.rawValue, privacy: .public) status fetch failed: \(error.localizedDescription, privacy: .public)")
            return .unknown(provider: provider, source: url.absoluteString)
        }
    }

    private func fetchGoogleWorkspaceStatus() async -> ProviderOperationalStatus {
        let url = URL(string: "https://www.google.com/appsstatus/dashboard/summary")!
        AppLog.status.info("Gemini status skipped; Google Workspace summary is incident history, not a reliable current-state feed")
        return ProviderOperationalStatus(
            provider: .gemini,
            severity: .unknown,
            message: "No reliable Gemini current-status feed is configured yet.",
            source: url.absoluteString,
            checkedAt: Date()
        )
    }

    private func issueMessage(
        summary: StatusPageSummary,
        components: [StatusPageComponent],
        severity: ProviderStatusSeverity
    ) -> String? {
        guard severity.isIssue else { return nil }
        let affected = components
            .filter { ProviderStatusSeverity(statusPageStatus: $0.status).isIssue }
            .map(\.name)
        if affected.isEmpty {
            return summary.status.description
        }
        return affected.joined(separator: ", ")
    }
}

private struct StatusPageSummary: Decodable {
    let status: StatusPageStatus
    let components: [StatusPageComponent]
}

private struct StatusPageStatus: Decodable {
    let indicator: String
    let description: String
}

private struct StatusPageComponent: Decodable {
    let name: String
    let status: String
}
