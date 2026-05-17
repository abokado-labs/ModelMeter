import Foundation

final class UsageReader: Sendable {
    private struct SessionEvent: Decodable {
        let timestamp: String?
        let payload: Payload?
        let rateLimits: RateLimitsPayload?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case payload
            case rateLimits = "rate_limits"
        }
    }

    private struct Payload: Decodable {
        let rateLimits: RateLimitsPayload?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }

    private struct RateLimitsPayload: Decodable {
        let primary: RateLimitWindowPayload?
        let secondary: RateLimitWindowPayload?
        let credits: CreditsPayload?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case primary
            case secondary
            case credits
            case planType = "plan_type"
        }
    }

    private struct RateLimitWindowPayload: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        let resetsAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
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
    }

    private struct SumRow: Decodable {
        let tokens: Int?
        let threads: Int?
    }

    private struct ThreadRow: Decodable {
        let id: String?
        let title: String?
        let tokens: Int?
        let updatedAtMs: Int64?
        let updatedAt: Int64?
        let model: String?
        let cwd: String?
    }

    private struct ModelRow: Decodable {
        let model: String?
        let tokens: Int?
        let threads: Int?
    }

    func loadSnapshot(settings: SettingsStore = .shared) throws -> UsageSnapshot {
        try loadSnapshot(codexHome: settings.codexHome)
    }

    func loadBalanceSnapshot(codexHome: String) -> UsageSnapshot {
        let codexHomeURL = URL(fileURLWithPath: codexHome)
        return UsageSnapshot(
            rateLimits: latestRateLimits(codexHomeURL: codexHomeURL),
            updatedAt: Date(),
            errorMessage: nil
        )
    }

    func loadRateLimitsForTesting(fileURL: URL) -> CodexRateLimits? {
        latestRateLimits(in: fileURL)
    }

    func loadSnapshot(codexHome: String) throws -> UsageSnapshot {
        let codexHomeURL = URL(fileURLWithPath: codexHome)
        let databaseURL = codexHomeURL.appendingPathComponent("state_5.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw UsageReaderError.missingDatabase(databaseURL.path)
        }

        let now = Date()
        let sessionCutoff = Int64(now.addingTimeInterval(-5 * 60 * 60).timeIntervalSince1970 * 1000)
        let dayCutoff = Int64(Calendar.current.startOfDay(for: now).timeIntervalSince1970 * 1000)
        let weekCutoff = Int64(now.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970 * 1000)

        let session = try sum(databaseURL: databaseURL, cutoff: sessionCutoff)
        let today = try sum(databaseURL: databaseURL, cutoff: dayCutoff)
        let weekly = try sum(databaseURL: databaseURL, cutoff: weekCutoff)
        let total = try total(databaseURL: databaseURL)

        return UsageSnapshot(
            sessionTokens: session.tokens,
            weeklyTokens: weekly.tokens,
            todayTokens: today.tokens,
            totalTokens: total.tokens,
            activeThreads: session.threads,
            recentThreads: try recentThreads(databaseURL: databaseURL),
            modelBreakdown: try modelBreakdown(databaseURL: databaseURL, cutoff: weekCutoff),
            rateLimits: latestRateLimits(codexHomeURL: codexHomeURL),
            updatedAt: now,
            errorMessage: nil
        )
    }

    private func sum(databaseURL: URL, cutoff: Int64) throws -> (tokens: Int, threads: Int) {
        let query = """
        select coalesce(sum(tokens_used), 0) as tokens, count(*) as threads
        from threads
        where coalesce(updated_at_ms, updated_at * 1000) >= \(cutoff);
        """
        let rows = try runJSON([SumRow].self, databaseURL: databaseURL, query: query)
        return (rows.first?.tokens ?? 0, rows.first?.threads ?? 0)
    }

    private func total(databaseURL: URL) throws -> (tokens: Int, threads: Int) {
        let query = "select coalesce(sum(tokens_used), 0) as tokens, count(*) as threads from threads;"
        let rows = try runJSON([SumRow].self, databaseURL: databaseURL, query: query)
        return (rows.first?.tokens ?? 0, rows.first?.threads ?? 0)
    }

    private func recentThreads(databaseURL: URL) throws -> [ThreadUsage] {
        let query = """
        select id,
               coalesce(nullif(title, ''), 'Untitled thread') as title,
               tokens_used as tokens,
               updated_at_ms as updatedAtMs,
               updated_at as updatedAt,
               coalesce(model, 'unknown') as model,
               cwd
        from threads
        where tokens_used > 0
        order by coalesce(updated_at_ms, updated_at * 1000) desc
        limit 8;
        """
        return try runJSON([ThreadRow].self, databaseURL: databaseURL, query: query).compactMap { row in
            guard let id = row.id else { return nil }
            let milliseconds = row.updatedAtMs ?? ((row.updatedAt ?? 0) * 1000)
            return ThreadUsage(
                id: id,
                title: row.title ?? "Untitled thread",
                tokens: row.tokens ?? 0,
                updatedAt: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
                model: row.model ?? "unknown",
                cwd: row.cwd ?? ""
            )
        }
    }

    private func modelBreakdown(databaseURL: URL, cutoff: Int64) throws -> [ModelUsage] {
        let query = """
        select coalesce(model, 'unknown') as model,
               coalesce(sum(tokens_used), 0) as tokens,
               count(*) as threads
        from threads
        where coalesce(updated_at_ms, updated_at * 1000) >= \(cutoff)
        group by coalesce(model, 'unknown')
        order by tokens desc
        limit 6;
        """
        return try runJSON([ModelRow].self, databaseURL: databaseURL, query: query).map {
            ModelUsage(model: $0.model ?? "unknown", tokens: $0.tokens ?? 0, threads: $0.threads ?? 0)
        }
    }

    private func runJSON<T: Decodable>(_ type: T.Type, databaseURL: URL, query: String) throws -> T {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databaseURL.path, query]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "sqlite3 failed"
            throw UsageReaderError.sqlite(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try JSONDecoder().decode(type, from: data.isEmpty ? Data("[]".utf8) : data)
    }

    private func latestRateLimits(codexHomeURL: URL) -> CodexRateLimits? {
        let sessionsURL = codexHomeURL.appendingPathComponent("sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            return url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") ? url : nil
        }
        .sorted { lhs, rhs in
            modificationDate(lhs) > modificationDate(rhs)
        }

        for file in files.prefix(40) {
            if let snapshot = latestRateLimits(in: file) {
                return snapshot
            }
        }
        return nil
    }

    private func latestRateLimits(in fileURL: URL) -> CodexRateLimits? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        var fallback: CodexRateLimits?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains(#""payload":{"type":"token_count""#) else {
                continue
            }
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(SessionEvent.self, from: lineData),
                  let rateLimits = event.payload?.rateLimits ?? event.rateLimits,
                  let primaryPayload = rateLimits.primary,
                  let secondaryPayload = rateLimits.secondary,
                  let primary = makeWindow(primaryPayload),
                  let secondary = makeWindow(secondaryPayload)
            else {
                continue
            }

            let capturedAt = parseTimestamp(event.timestamp) ?? modificationDate(fileURL)
            let snapshot = CodexRateLimits(
                primary: primary,
                secondary: secondary,
                credits: makeCredits(rateLimits.credits),
                planType: rateLimits.planType,
                capturedAt: capturedAt,
                sourcePath: fileURL.path
            )

            if isEmptyPlaceholder(primary: primary, secondary: secondary, capturedAt: capturedAt) {
                fallback = fallback ?? snapshot
                continue
            }

            return snapshot
        }
        return fallback
    }


    private func isEmptyPlaceholder(primary: RateLimitWindow, secondary: RateLimitWindow, capturedAt: Date) -> Bool {
        guard primary.usedPercent == 0, secondary.usedPercent == 0 else { return false }
        return resetMatchesFullWindow(primary, capturedAt: capturedAt)
            && resetMatchesFullWindow(secondary, capturedAt: capturedAt)
    }

    private func resetMatchesFullWindow(_ window: RateLimitWindow, capturedAt: Date) -> Bool {
        let expectedReset = capturedAt.addingTimeInterval(TimeInterval(window.windowMinutes * 60))
        return abs(window.resetsAt.timeIntervalSince(expectedReset)) < 120
    }

    private func makeWindow(_ payload: RateLimitWindowPayload) -> RateLimitWindow? {
        guard let usedPercent = payload.usedPercent,
              let windowMinutes = payload.windowMinutes,
              let resetsAt = payload.resetsAt
        else {
            return nil
        }
        return RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt))
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

    private func parseTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }

    private func modificationDate(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
    }
}

enum UsageReaderError: LocalizedError {
    case missingDatabase(String)
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .missingDatabase(let path):
            return "Codex database not found at \(path)"
        case .sqlite(let message):
            return message.isEmpty ? "Unable to read Codex database" : message
        }
    }
}
