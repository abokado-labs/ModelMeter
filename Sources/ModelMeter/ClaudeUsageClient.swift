import Foundation

final class ClaudeUsageClient: Sendable {
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private struct Organization: Decodable {
        let uuid: String?
        let id: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case uuid
            case id
            case name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            if let stringID = try? container.decodeIfPresent(String.self, forKey: .id) {
                id = stringID
            } else if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
                id = String(intID)
            } else {
                id = nil
            }
        }
    }

    func fetch(organizationID: String, sessionKey: String, cfClearance: String) async throws -> ClaudeUsageSnapshot {
        guard !organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageError.missingOrganization
        }
        guard !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageError.missingSessionKey
        }

        let encodedOrganizationID = organizationID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? ""
        guard !encodedOrganizationID.isEmpty else {
            throw ClaudeUsageError.invalidResponse("Claude organization ID contains unsupported characters")
        }

        let data = try await performRequest(
            url: URL(string: "https://claude.ai/api/organizations/\(encodedOrganizationID)/usage")!,
            sessionKey: sessionKey,
            cfClearance: cfClearance,
            referer: "https://claude.ai/settings/usage",
            label: "usage"
        )
        return try parseUsageSnapshot(data)
    }

    func discoverOrganizationID(sessionKey: String, cfClearance: String) async throws -> String {
        guard !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageError.missingSessionKey
        }

        let data = try await performRequest(
            url: URL(string: "https://claude.ai/api/organizations")!,
            sessionKey: sessionKey,
            cfClearance: cfClearance,
            referer: "https://claude.ai",
            label: "organizations"
        )

        do {
            let organizations = try JSONDecoder().decode([Organization].self, from: data)
            guard let orgID = organizations.compactMap({ $0.uuid ?? $0.id }).first else {
                throw ClaudeUsageError.organizationNotFound
            }
            return orgID
        } catch let error as ClaudeUsageError {
            throw error
        } catch {
            throw ClaudeUsageError.decodeFailed("organizations", preview(data), error.localizedDescription)
        }
    }

    private func performRequest(url: URL, sessionKey: String, cfClearance: String, referer: String, label: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(cookieHeader(sessionKey: sessionKey, cfClearance: cfClearance), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse("No HTTP response for \(label)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeUsageError.httpStatus(http.statusCode, label, preview(data))
        }
        return data
    }

    private func parseUsageSnapshot(_ data: Data) throws -> ClaudeUsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.decodeFailed("usage", preview(data), "Top-level JSON was not an object")
        }

        guard let session = makeWindow(json["five_hour"] as? [String: Any], defaultMinutes: 300),
              let weekly = makeWindow(json["seven_day"] as? [String: Any], defaultMinutes: 10_080)
        else {
            let keys = json.keys.sorted().joined(separator: ", ")
            throw ClaudeUsageError.invalidResponse("Claude usage response did not include readable five_hour and seven_day windows. Keys: \(keys)")
        }

        let opus = makeWindow(json["seven_day_opus"] as? [String: Any], defaultMinutes: 10_080)
        let extra = makeExtraUsage(json["extra_usage"] as? [String: Any])

        return ClaudeUsageSnapshot(
            rateLimits: ClaudeRateLimits(
                session: session,
                weekly: weekly,
                opusWeekly: opus,
                extraUsage: extra
            ),
            updatedAt: Date(),
            errorMessage: nil
        )
    }

    private func makeWindow(_ window: [String: Any]?, defaultMinutes: Int) -> RateLimitWindow? {
        guard let window else { return nil }
        guard let used = parsePercent(window["utilization"] ?? window["utilization_pct"]) else {
            return nil
        }
        return RateLimitWindow(
            usedPercent: used,
            windowMinutes: defaultMinutes,
            resetsAt: parseDate(window["resets_at"] as? String ?? window["reset_at"] as? String) ?? Date()
        )
    }

    private func makeExtraUsage(_ value: [String: Any]?) -> ClaudeExtraUsage? {
        guard let value else { return nil }
        return ClaudeExtraUsage(
            currentSpending: parseDouble(value["current_spending"]),
            budgetLimit: parseDouble(value["budget_limit"])
        )
    }

    private func parsePercent(_ value: Any?) -> Double? {
        guard let parsed = parseDouble(value) else { return nil }
        return min(max(parsed, 0), 100)
    }

    private func parseDouble(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as String:
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
            return Double(cleaned)
        default:
            return nil
        }
    }

    private func cookieHeader(sessionKey: String, cfClearance: String) -> String {
        var cookies = ["sessionKey=\(sessionKey)"]
        if !cfClearance.isEmpty {
            cookies.append("cf_clearance=\(cfClearance)")
        }
        return cookies.joined(separator: "; ")
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

    private func preview(_ data: Data) -> String {
        guard let string = String(data: data, encoding: .utf8) else { return "<non-utf8 response>" }
        let singleLine = string.replacingOccurrences(of: "\n", with: " ")
        return String(singleLine.prefix(300))
    }
}

enum ClaudeUsageError: LocalizedError {
    case missingOrganization
    case missingSessionKey
    case invalidResponse(String)
    case organizationNotFound
    case httpStatus(Int, String, String)
    case decodeFailed(String, String, String)

    var errorDescription: String? {
        switch self {
        case .missingOrganization:
            return "Claude organization ID is not configured"
        case .missingSessionKey:
            return "Claude session key is not configured"
        case .invalidResponse(let detail):
            return detail
        case .organizationNotFound:
            return "Claude organization could not be discovered"
        case .httpStatus(let status, let label, _):
            return "Claude \(label) request failed with HTTP \(status)"
        case .decodeFailed(let label, _, let error):
            return "Claude \(label) response was not recognized: \(error)"
        }
    }
}
