import XCTest
@testable import AIUsageDashboardCore

final class ProviderModelTests: XCTestCase {
    func testProviderIDRawValues() {
        XCTAssertEqual(ProviderID.claudeCode.rawValue, "claude_code")
        XCTAssertEqual(ProviderID.codex.rawValue, "codex")
        XCTAssertEqual(ProviderID.cursor.rawValue, "cursor")
        XCTAssertEqual(ProviderID.antigravity.rawValue, "antigravity")
        XCTAssertEqual(ProviderID.cline.rawValue, "cline")
        XCTAssertEqual(ProviderID.opencode.rawValue, "opencode")
    }

    func testMetricConfidenceDisplayName() {
        XCTAssertEqual(MetricConfidence.localParsed.displayName, "Local Parsed")
        XCTAssertEqual(MetricConfidence.unavailable.displayName, "Unavailable")
    }

    func testQuotaWindowID() {
        let window = QuotaWindow(
            providerID: .claudeCode,
            type: .session,
            used: 10,
            limit: 100,
            confidence: .localParsed,
            source: "test"
        )
        XCTAssertEqual(window.id, "claude_code_session")
    }

    func testQuotaWindowIDPrefersBucketKey() {
        let window = QuotaWindow(
            providerID: .antigravity,
            type: .weekly,
            used: 8,
            limit: 100,
            confidence: .providerReported,
            source: "test",
            label: "Gemini Models",
            bucketKey: "gemini-weekly"
        )
        XCTAssertEqual(window.id, "gemini-weekly")
        XCTAssertEqual(window.label, "Gemini Models")
        XCTAssertEqual(window.bucketKey, "gemini-weekly")
    }

    func testTokenUsageMerging() {
        let a = TokenUsage(inputTokens: 10, outputTokens: 5, confidence: .localParsed)
        let b = TokenUsage(inputTokens: 20, outputTokens: 10, confidence: .localParsed)
        let merged = a.merging(b)
        XCTAssertEqual(merged.inputTokens, 30)
        XCTAssertEqual(merged.outputTokens, 15)
    }

    func testProviderSnapshotIdentifiable() {
        let snapshot = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .unknown,
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
        XCTAssertEqual(snapshot.id, .claudeCode)
    }
}
