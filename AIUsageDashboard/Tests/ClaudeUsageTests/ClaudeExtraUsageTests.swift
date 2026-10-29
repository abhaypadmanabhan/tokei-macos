import XCTest
@testable import AIUsageDashboardCore

final class ClaudeExtraUsageTests: XCTestCase {
    func testExtraUsageAloneIsNotARecognizedRateLimitResponse() {
        let json = """
        {"extra_usage":{"is_enabled":false,"monthly_limit":5000,"used_credits":2152,
         "currency":"USD","decimal_places":2,"disabled_reason":"out_of_credits"}}
        """
        XCTAssertThrowsError(try ClaudeUsageClientImpl.decodeQuotaWindows(Data(json.utf8))) { error in
            guard case ClaudeUsageError.unrecognizedResponse = error else {
                return XCTFail("Expected unrecognizedResponse, got \(error)")
            }
        }
    }

    func testCapturedExtraUsageUsesDollarsAndPreservesDisabledState() throws {
        // Mirrors tasks/research/claude-usage-response.json, without opening Downloads at runtime.
        let data = Data(ClaudeFixtures.oauthUsageResponse.utf8)
        let windows = try ClaudeUsageClientImpl.decodeQuotaWindows(data, providerID: .claudeCode)
        let extra = try XCTUnwrap(windows.first { $0.bucketKey == "claude_extra_usage" })
        XCTAssertEqual(extra.type, .credits)
        XCTAssertEqual(extra.used, 21.52)
        XCTAssertEqual(extra.limit, 50)
        XCTAssertEqual(extra.remaining, 28.48)
        XCTAssertTrue(extra.source.contains("disabled"))
        XCTAssertTrue(extra.source.contains("out_of_credits"))
        XCTAssertNil(extra.windowDuration)
    }
}
