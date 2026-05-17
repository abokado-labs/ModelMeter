import Foundation

final class ClaudeUsageClient: Sendable {
    private struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?
        let extraUsage: ExtraUsage?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case extraUsage = "extra_usage"
        }
    }

    private struct Window: Decodable {
        let utilizationPct: Double?
        let utilization: Double?
        let resetAt: String?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilizationPct = "utilization_pct"
            case utilization
            case resetAt = "reset_at"
            case resetsAt = "resets_at"
        }
    }

    private struct ExtraUsage: Decodable {
        let currentSpending: Double?
        let budgetLimit: Double?

        enum CodingKeys: String, CodingKey {
            case currentSpending = "current_spending"
            case budgetLimit = "budget_limit"
        }
    }

    private struct Organization: Decodable {
        let uuid: String?
        let id: String?
    }

    func fetch(organizationID: String, sessionKey: String, cfClearance: String) async throws -> ClaudeUsageSnapshot {
        guard !organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageError.missingOrganization
        }
        guard !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageError.missingSessionKey
        }

        let url = URL(string: "https://claude.ai/api/organizations/\(organizationID)/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookieHeader(sessionKey: sessionKey, cfClearance: cfClearance), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) LLMUsageTracker/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeUsageError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        guard let session = makeWindow(decoded.fiveHour, defaultMinutes: 300),
              let weekly = makeWindow(decoded.sevenDay, defaultMinutes: 10_080)
        else {
            throw ClaudeUsageError.invalidResponse
        }

        return ClaudeUsageSnapshot(
            rateLimits: ClaudeRateLimits(
                session: session,
                weekly: weekly,
                opusWeekly: makeWindow(decoded.sevenDayOpus, defaultMinutes: 10_080),
                extraUsage: decoded.extraUsage.map {
                    ClaudeExtraUsage(currentSpending: $0.currentSpending, budgetLimit: $0.budgetLimit)
                }
            ),
            updatedAt: Date(),
            errorMessage: nil
        )
    }

    func discoverOrganizationID(sessionKey: String, cfClearance: String) async throws -> String {
        guard !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageError.missingSessionKey
        }

        let url = URL(string: "https://claude.ai/api/organizations")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookieHeader(sessionKey: sessionKey, cfClearance: cfClearance), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) LLMUsageTracker/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeUsageError.httpStatus(http.statusCode)
        }

        let organizations = try JSONDecoder().decode([Organization].self, from: data)
        guard let orgID = organizations.compactMap({ $0.uuid ?? $0.id }).first else {
            throw ClaudeUsageError.organizationNotFound
        }
        return orgID
    }

    private func cookieHeader(sessionKey: String, cfClearance: String) -> String {
        var cookies = ["sessionKey=\(sessionKey)"]
        if !cfClearance.isEmpty {
            cookies.append("cf_clearance=\(cfClearance)")
        }
        return cookies.joined(separator: "; ")
    }

    private func makeWindow(_ window: Window?, defaultMinutes: Int) -> RateLimitWindow? {
        guard let window,
              let used = window.utilizationPct ?? window.utilization
        else {
            return nil
        }
        return RateLimitWindow(
            usedPercent: used,
            windowMinutes: defaultMinutes,
            resetsAt: parseDate(window.resetAt ?? window.resetsAt) ?? Date()
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum ClaudeUsageError: LocalizedError {
    case missingOrganization
    case missingSessionKey
    case invalidResponse
    case organizationNotFound
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingOrganization:
            return "Claude organization ID is not configured"
        case .missingSessionKey:
            return "Claude session key is not configured"
        case .invalidResponse:
            return "Claude usage response was not recognized"
        case .organizationNotFound:
            return "Claude organization could not be discovered"
        case .httpStatus(let status):
            return "Claude usage request failed with HTTP \(status)"
        }
    }
}
