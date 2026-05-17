import Foundation
@testable import ModelMeter
import XCTest

final class UsageReaderTests: XCTestCase {
    func testSkipsZeroRateLimitPlaceholderAfterRealSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-placeholder-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let real = #"{"timestamp":"2026-05-17T15:20:04.087Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1779032052},"secondary":{"used_percent":9,"window_minutes":10080,"resets_at":1779577219},"plan_type":"prolite"}}}"#
        let placeholder = #"{"timestamp":"2026-05-17T15:20:19.304Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":0,"window_minutes":300,"resets_at":1779049219},"secondary":{"used_percent":0,"window_minutes":10080,"resets_at":1779636019},"plan_type":"prolite"}}}"#
        try [real, placeholder].joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let rateLimits = UsageReader().loadRateLimitsForTesting(fileURL: fileURL)

        XCTAssertEqual(rateLimits?.primary.usedPercent, 25)
        XCTAssertEqual(rateLimits?.secondary.usedPercent, 9)
        XCTAssertEqual(rateLimits?.displayPlan, "prolite")
    }

    func testKeepsRealZeroAfterWindowReset() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollout-real-zero-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let stalePreviousWindow = #"{"timestamp":"2026-05-17T15:31:17.476Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":26,"window_minutes":300,"resets_at":1779032051},"secondary":{"used_percent":9,"window_minutes":10080,"resets_at":1779577218},"plan_type":"prolite"}}}"#
        let currentWindow = #"{"timestamp":"2026-05-17T15:38:27.572Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":0,"window_minutes":300,"resets_at":1779050062},"secondary":{"used_percent":9,"window_minutes":10080,"resets_at":1779577221},"plan_type":"prolite"}}}"#
        try [stalePreviousWindow, currentWindow].joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let rateLimits = UsageReader().loadRateLimitsForTesting(fileURL: fileURL)

        XCTAssertEqual(rateLimits?.primary.usedPercent, 0)
        XCTAssertEqual(rateLimits?.secondary.usedPercent, 9)
        XCTAssertEqual(try XCTUnwrap(rateLimits?.primary.resetsAt).timeIntervalSince1970, 1_779_050_062, accuracy: 0.1)
    }

}
