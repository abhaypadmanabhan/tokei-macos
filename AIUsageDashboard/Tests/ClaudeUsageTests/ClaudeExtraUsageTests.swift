import XCTest
@testable import AIUsageDashboardCore

final class ClaudeExtraUsageTests: XCTestCase {
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
