import XCTest
@testable import AIUsageDashboardCore

/// WP-3 AC6: Claude's extra usage reads "Extra usage $21.52 of $50.00 · off, out of
/// credits" from the §4.3 window. Amounts are the saved real response's 2152 and 5000
/// minor USD (tasks/research/claude-usage-response.json).
final class ExtraUsageCopyTests: XCTestCase {
    private func window(source: String, used: Double? = 21.52, limit: Double? = 50) -> QuotaWindow {
        QuotaWindow(
            providerID: .claudeCode, type: .credits, used: used, limit: limit,
            remaining: zip(limit, used).map { $0 - $1 }, confidence: .providerReported,
            source: source, label: "Extra usage", bucketKey: "claude_extra_usage"
        )
    }

    func testDisabledOutOfCredits() {
        let source = "oauth/usage extra_usage is_enabled=false disabled_reason=out_of_credits"
        let line = ExtraUsageCopy.line(window(source: source))
        XCTAssertEqual(line, "Extra usage $21.52 of $50.00 · off, out of credits")
    }

    func testNoStatusWordsShowsOnlyTheAmounts() {
        XCTAssertEqual(ExtraUsageCopy.line(window(source: "oauth/usage extra_usage")), "Extra usage $21.52 of $50.00")
    }

    func testWithoutALimitSaysUsed() {
        XCTAssertEqual(ExtraUsageCopy.line(window(source: "x", limit: nil)), "Extra usage $21.52 used")
    }

    func testNoAmountMeansNoLine() {
        XCTAssertNil(ExtraUsageCopy.line(window(source: "x", used: nil, limit: nil)))
    }

    func testFoundInAccountsAndOnlyForItsBucket() {
        let other = QuotaWindow(
            providerID: .cursor, type: .credits, used: 5, limit: 10, confidence: .providerReported, source: "x"
        )
        let snapshot = ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            quotaWindows: [other], todayUsage: .unavailable, weekUsage: .unavailable,
            accounts: [ProviderAccountUsage(
                id: "/a", label: "default", quotaWindows: [window(source: "x")], todayUsage: .unavailable
            )]
        )
        XCTAssertEqual(ExtraUsageCopy.window(in: snapshot)?.bucketKey, "claude_extra_usage")
        XCTAssertFalse(ExtraUsageCopy.isExtraUsage(other))
        XCTAssertEqual(try XCTUnwrap(ExtraUsageCopy.fraction(window(source: "x"))), 0.4304, accuracy: 1e-9)
    }
}

private func zip(_ lhs: Double?, _ rhs: Double?) -> (Double, Double)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}
