import Foundation

final class CodexAppServerClient: Sendable {
    private struct AccountResponse: Decodable {
        let account: AccountDetails?
    }

    private struct AccountDetails: Decodable {
        let type: String?
        let email: String?
        let planType: String?
    }

    private struct RateLimitsResponse: Decodable {
        let rateLimits: RateLimitsPayload
    }

    private struct RateLimitsPayload: Decodable {
        let primary: RateLimitWindowPayload?
        let secondary: RateLimitWindowPayload?
        let credits: CreditsPayload?
        let planType: String?
    }

    private struct RateLimitWindowPayload: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let windowMinutes: Int?
        let resetsAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent
            case windowDurationMins
            case windowMinutes = "window_minutes"
            case resetsAt
        }
    }

    private struct CreditsPayload: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let balance: String?
    }

    private let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval = 4) {
        self.requestTimeout = requestTimeout
    }

    func loadRateLimits() throws -> CodexRateLimits {
        let transport = try Transport()
        defer { transport.shutdown() }

        try transport.sendRequest(id: 1, method: "initialize", params: [
            "clientInfo": [
                "name": "model-meter",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ]
        ])
        _ = try transport.readResponse(id: 1, timeout: requestTimeout)
        try transport.sendNotification(method: "initialized")

        try transport.sendRequest(id: 2, method: "account/rateLimits/read")
        let limitsResponse: RateLimitsResponse = try transport.decodeResponse(
            try transport.readResponse(id: 2, timeout: requestTimeout)
        )

        var accountPlan: String?
        try? transport.sendRequest(id: 3, method: "account/read")
        if let message = try? transport.readResponse(id: 3, timeout: requestTimeout),
           let accountResponse: AccountResponse = try? transport.decodeResponse(message),
           accountResponse.account?.type?.lowercased() == "chatgpt" {
            accountPlan = accountResponse.account?.planType
        }

        guard let primary = makeWindow(limitsResponse.rateLimits.primary),
              let secondary = makeWindow(limitsResponse.rateLimits.secondary) else {
            throw CodexAppServerError.noRateLimits
        }

        return CodexRateLimits(
            primary: primary,
            secondary: secondary,
            credits: makeCredits(limitsResponse.rateLimits.credits),
            planType: firstNonEmpty(limitsResponse.rateLimits.planType, accountPlan),
            capturedAt: Date(),
            sourcePath: "codex app-server"
        )
    }

    private func makeWindow(_ payload: RateLimitWindowPayload?) -> RateLimitWindow? {
        guard let payload,
              let windowMinutes = payload.windowDurationMins ?? payload.windowMinutes,
              let resetsAt = payload.resetsAt else {
            return nil
        }
        return RateLimitWindow(
            usedPercent: payload.usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt))
        )
    }

    private func makeCredits(_ payload: CreditsPayload?) -> CreditBalance? {
        guard let payload else { return nil }
        return CreditBalance(
            hasCredits: payload.hasCredits ?? false,
            unlimited: payload.unlimited ?? false,
            balance: payload.balance.flatMap(Double.init)
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }
}

enum CodexAppServerError: LocalizedError {
    case notInstalled
    case startFailed(String)
    case closed
    case timeout
    case malformed(String)
    case rpc(String)
    case noRateLimits
    case unsupportedCLI

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Codex CLI was not found on PATH."
        case .startFailed(let message):
            return "Codex app-server could not start: \(message)"
        case .closed:
            return "Codex app-server closed before returning usage data."
        case .timeout:
            return "Codex app-server timed out while reading usage data."
        case .malformed(let message):
            return "Codex app-server returned invalid data: \(message)"
        case .rpc(let message):
            return "Codex app-server error: \(message)"
        case .noRateLimits:
            return "Codex app-server did not return rate-limit balances."
        case .unsupportedCLI:
            return "This Codex CLI does not support app-server live usage."
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<[String: Any], Error>?

    func set(_ value: Result<[String: Any], Error>) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Result<[String: Any], Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class Transport: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let error = Pipe()
    private var bufferedOutput = Data()

    init() throws {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [environment["PATH"], defaultPath]
            .compactMap { $0 }
            .joined(separator: ":")

        guard Self.supportsAppServer(environment: environment) else {
            throw CodexAppServerError.unsupportedCLI
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw CodexAppServerError.startFailed(error.localizedDescription)
        }
    }

    private static func supportsAppServer(environment: [String: String]) -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = ["codex", "help", "app-server"]
        probe.environment = environment
        probe.standardOutput = Pipe()
        probe.standardError = Pipe()
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }

    func shutdown() {
        if process.isRunning {
            process.terminate()
        }
    }

    func sendNotification(method: String, params: [String: Any] = [:]) throws {
        try send(["method": method, "params": params])
    }

    func sendRequest(id: Int, method: String, params: [String: Any] = [:]) throws {
        try send(["id": id, "method": method, "params": params])
    }

    func decodeResponse<T: Decodable>(_ message: [String: Any]) throws -> T {
        guard let result = message["result"] else {
            throw CodexAppServerError.malformed("missing result field")
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func readResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        let response = ResponseBox()

        DispatchQueue.global(qos: .utility).async {
            response.set(Result { try self.readResponseBlocking(id: id) })
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            shutdown()
            throw CodexAppServerError.timeout
        }

        guard let resolved = response.get() else {
            throw CodexAppServerError.closed
        }
        return try resolved.get()
    }

    private func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data([0x0A]))
    }

    private func readResponseBlocking(id: Int) throws -> [String: Any] {
        while true {
            guard let line = try readLine() else {
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let stderr, stderr.localizedCaseInsensitiveContains("not found") {
                    throw CodexAppServerError.notInstalled
                }
                throw CodexAppServerError.closed
            }

            guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }

            if let error = message["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw CodexAppServerError.rpc(message)
            }

            guard numericID(message["id"]) == id else {
                continue
            }
            return message
        }
    }

    private func readLine() throws -> Data? {
        while true {
            if let newline = bufferedOutput.firstIndex(of: 0x0A) {
                let line = Data(bufferedOutput[..<newline])
                bufferedOutput.removeSubrange(...newline)
                return line.isEmpty ? nil : line
            }

            let data = output.fileHandleForReading.availableData
            if data.isEmpty {
                return nil
            }
            bufferedOutput.append(data)
        }
    }

    private func numericID(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }
}
