import Foundation

final class CodexLiveUsageClient: Sendable {
    private struct AuthFile: Decodable {
        let tokens: Tokens?
        let apiKey: String?
        let lastRefresh: Date?

        enum CodingKeys: String, CodingKey {
            case tokens
            case apiKey = "OPENAI_API_KEY"
            case lastRefresh = "last_refresh"
        }
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let idToken: String?
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case accountId = "account_id"
        }
    }

    private struct Credentials {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let accountId: String?
        let lastRefresh: Date?
        let authURL: URL

        var shouldRefresh: Bool {
            guard refreshToken?.isEmpty == false else { return false }
            guard let lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
        }
    }

    private struct UsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimitPayload?
        let credits: CreditsPayload?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case credits
        }
    }

    private struct RateLimitPayload: Decodable {
        let primaryWindow: WindowPayload?
        let secondaryWindow: WindowPayload?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct WindowPayload: Decodable {
        let usedPercent: Double
        let resetAt: Int64
        let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    private struct CreditsPayload: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let balance: Double?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = try container.decodeIfPresent(Bool.self, forKey: .hasCredits)
            unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
            if let number = try? container.decodeIfPresent(Double.self, forKey: .balance) {
                balance = number
            } else if let string = try? container.decodeIfPresent(String.self, forKey: .balance) {
                balance = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                balance = nil
            }
        }
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    fileprivate struct HTTPResponse {
        let data: Data
        let statusCode: Int
    }

    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let decoder: JSONDecoder

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
        }
        self.decoder = decoder
    }

    func loadRateLimits(codexHome: String) throws -> CodexRateLimits {
        AppLog.codex.info("Live OAuth refresh starting; codexHome=\(codexHome, privacy: .public)")
        var credentials = try loadCredentials(codexHome: codexHome)
        AppLog.codex.info("Codex auth loaded; hasRefreshToken=\((credentials.refreshToken?.isEmpty == false), privacy: .public); hasAccountId=\((credentials.accountId?.isEmpty == false), privacy: .public)")
        if credentials.shouldRefresh {
            AppLog.codex.info("Codex access token is stale; refreshing with OAuth refresh token")
            credentials = try refresh(credentials)
            try save(credentials, to: credentials.authURL)
        }

        do {
            let limits = try fetchUsage(credentials: credentials)
            AppLog.codex.info("Live OAuth refresh succeeded; plan=\(limits.displayPlan, privacy: .public); primary=\(limits.primary.usedPercent, privacy: .public); secondary=\(limits.secondary.usedPercent, privacy: .public)")
            return limits
        } catch CodexLiveUsageError.unauthorized where credentials.refreshToken?.isEmpty == false {
            AppLog.codex.warning("Live OAuth usage returned unauthorized; refreshing token and retrying")
            let refreshed = try refresh(credentials)
            try save(refreshed, to: refreshed.authURL)
            let limits = try fetchUsage(credentials: refreshed)
            AppLog.codex.info("Live OAuth retry succeeded; plan=\(limits.displayPlan, privacy: .public); primary=\(limits.primary.usedPercent, privacy: .public); secondary=\(limits.secondary.usedPercent, privacy: .public)")
            return limits
        }
    }

    private func loadCredentials(codexHome: String) throws -> Credentials {
        let authURL = URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            AppLog.codex.error("Codex auth file missing at \(authURL.path, privacy: .public)")
            throw CodexLiveUsageError.missingAuth
        }

        let data = try Data(contentsOf: authURL)
        let auth = try decoder.decode(AuthFile.self, from: data)
        if let accessToken = auth.tokens?.accessToken?.nonEmpty {
            return Credentials(
                accessToken: accessToken,
                refreshToken: auth.tokens?.refreshToken?.nonEmpty,
                idToken: auth.tokens?.idToken?.nonEmpty,
                accountId: auth.tokens?.accountId?.nonEmpty,
                lastRefresh: auth.lastRefresh,
                authURL: authURL
            )
        }
        if let apiKey = auth.apiKey?.nonEmpty {
            return Credentials(
                accessToken: apiKey,
                refreshToken: nil,
                idToken: nil,
                accountId: nil,
                lastRefresh: nil,
                authURL: authURL
            )
        }
        throw CodexLiveUsageError.missingToken
    }

    private func fetchUsage(credentials: Credentials) throws -> CodexRateLimits {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("model-meter", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountId?.nonEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let response = try send(request)
        AppLog.codex.info("Codex live usage HTTP status=\(response.statusCode, privacy: .public)")
        switch response.statusCode {
        case 200...299:
            let payload = try decoder.decode(UsageResponse.self, from: response.data)
            return try makeRateLimits(from: payload)
        case 401, 403:
            throw CodexLiveUsageError.unauthorized
        default:
            throw CodexLiveUsageError.server(response.statusCode, bodyPreview(response.data))
        }
    }

    private func refresh(_ credentials: Credentials) throws -> Credentials {
        guard let refreshToken = credentials.refreshToken?.nonEmpty else {
            return credentials
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ])

        let response = try send(request)
        AppLog.codex.info("Codex OAuth token refresh HTTP status=\(response.statusCode, privacy: .public)")
        guard response.statusCode == 200 else {
            throw CodexLiveUsageError.refreshFailed(response.statusCode, bodyPreview(response.data))
        }

        let refreshed = try decoder.decode(RefreshResponse.self, from: response.data)
        return Credentials(
            accessToken: refreshed.accessToken?.nonEmpty ?? credentials.accessToken,
            refreshToken: refreshed.refreshToken?.nonEmpty ?? credentials.refreshToken,
            idToken: refreshed.idToken?.nonEmpty ?? credentials.idToken,
            accountId: credentials.accountId,
            lastRefresh: Date(),
            authURL: credentials.authURL
        )
    }

    private func save(_ credentials: Credentials, to authURL: URL) throws {
        guard let data = try? Data(contentsOf: authURL),
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var tokens = (json["tokens"] as? [String: Any]) ?? [:]
        tokens["access_token"] = credentials.accessToken
        if let refreshToken = credentials.refreshToken {
            tokens["refresh_token"] = refreshToken
        }
        if let idToken = credentials.idToken {
            tokens["id_token"] = idToken
        }
        if let accountId = credentials.accountId {
            tokens["account_id"] = accountId
        }
        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: authURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
    }

    private func makeRateLimits(from payload: UsageResponse) throws -> CodexRateLimits {
        let windows = [
            makeWindow(payload.rateLimit?.primaryWindow),
            makeWindow(payload.rateLimit?.secondaryWindow),
        ].compactMap { $0 }

        let primary = windows
            .filter { $0.windowMinutes != 10_080 }
            .min { $0.windowMinutes < $1.windowMinutes }
        let secondary = windows
            .filter { $0.windowMinutes == 10_080 }
            .first ?? windows.max { $0.windowMinutes < $1.windowMinutes }

        guard windows.count >= 2, let primary, let secondary else {
            throw CodexLiveUsageError.noRateLimits
        }

        return CodexRateLimits(
            primary: primary,
            secondary: secondary,
            credits: makeCredits(payload.credits),
            planType: payload.planType,
            capturedAt: Date(),
            sourcePath: "codex oauth wham/usage"
        )
    }

    private func makeWindow(_ payload: WindowPayload?) -> RateLimitWindow? {
        guard let payload else { return nil }
        return RateLimitWindow(
            usedPercent: payload.usedPercent,
            windowMinutes: max(payload.limitWindowSeconds / 60, 1),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(payload.resetAt))
        )
    }

    private func makeCredits(_ payload: CreditsPayload?) -> CreditBalance? {
        guard let payload else { return nil }
        return CreditBalance(
            hasCredits: payload.hasCredits ?? false,
            unlimited: payload.unlimited ?? false,
            balance: payload.balance
        )
    }

    private func send(_ request: URLRequest) throws -> HTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let box = CodexHTTPResponseBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.set(.failure(error))
            } else if let http = response as? HTTPURLResponse {
                box.set(.success(HTTPResponse(data: data ?? Data(), statusCode: http.statusCode)))
            } else {
                box.set(.failure(CodexLiveUsageError.invalidResponse))
            }
            semaphore.signal()
        }.resume()

        if semaphore.wait(timeout: .now() + 25) == .timedOut {
            throw CodexLiveUsageError.timeout
        }
        guard let result = box.get() else {
            throw CodexLiveUsageError.invalidResponse
        }
        return try result.get()
    }

    private func bodyPreview(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(text.prefix(300))
    }
}

enum CodexLiveUsageError: LocalizedError {
    case missingAuth
    case missingToken
    case unauthorized
    case refreshFailed(Int, String)
    case server(Int, String)
    case noRateLimits
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingAuth:
            return "Codex auth.json was not found. Run `codex` and sign in with ChatGPT."
        case .missingToken:
            return "Codex auth.json exists but does not contain a ChatGPT access token."
        case .unauthorized:
            return "Codex ChatGPT token is expired or unauthorized. Run `codex` to sign in again."
        case .refreshFailed(let code, let body):
            return "Codex token refresh failed (\(code)): \(body)"
        case .server(let code, let body):
            return "Codex live usage endpoint failed (\(code)): \(body)"
        case .noRateLimits:
            return "Codex live usage endpoint did not return rate-limit balances."
        case .invalidResponse:
            return "Codex live usage endpoint returned an invalid response."
        case .timeout:
            return "Codex live usage endpoint timed out."
        }
    }
}

private final class CodexHTTPResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<CodexLiveUsageClient.HTTPResponse, Error>?

    func set(_ value: Result<CodexLiveUsageClient.HTTPResponse, Error>) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Result<CodexLiveUsageClient.HTTPResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
