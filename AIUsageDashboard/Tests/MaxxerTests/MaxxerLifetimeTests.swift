import XCTest
@testable import AIUsageDashboardCore

/// Unit tests for the lifetime aggregation (#41) and value-surface number
/// formatting (#23) in `MaxxerMath`, compiled into this test bundle from
/// `UI/MenuBar/MaxxerMath.swift` (see project.yml).
///
/// The lifetime rules exist because the providers genuinely disagree: Claude
/// Code / Codex / Cline / Opencode report a real `lifetimeUsage`, while Cursor,
/// Antigravity and Gemini report `nil` on purpose. Everything below pins the
/// behaviour at that seam.
final class MaxxerLifetimeTests: XCTestCase {

    // MARK: - Fixtures

    private func snapshot(
        _ id: ProviderID,
        lifetime: TokenUsage? = nil,
        dailyTotals: [Date: Int]? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: id.rawValue,
            authStatus: .authenticated,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            lifetimeUsage: lifetime,
            dailyTotals: dailyTotals
        )
    }

    private func days(_ values: [Int]) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for (index, value) in values.enumerated() {
            totals[Date(timeIntervalSince1970: Double(index) * 86_400)] = value
        }
        return totals
    }

    // MARK: - Provider-reported lifetime wins

    func testPrefersProviderReportedLifetimeOverDailyTotals() {
        let result = MaxxerMath.lifetimeTotal(in: [
            snapshot(.claudeCode,
                     lifetime: TokenUsage(inputTokens: 900, outputTokens: 100, confidence: .exact),
                     dailyTotals: days([1, 2, 3]))
        ])

        // 1_000 from lifetimeUsage, NOT 6 from the daily buckets.
        XCTAssertEqual(result?.tokens, 1_000)
        XCTAssertEqual(result?.confidence, .exact)
        XCTAssertEqual(result?.usedDailyFallback, false)
        XCTAssertEqual(result?.contributingProviders, 1)
    }

    // MARK: - Daily-totals fallback (mirrors UsageAnalytics.swift:247)

    func testFallsBackToSummedDailyTotalsWhenLifetimeAbsent() {
        let result = MaxxerMath.lifetimeTotal(in: [
            snapshot(.cursor, lifetime: nil, dailyTotals: days([10, 20, 30]))
        ])

        XCTAssertEqual(result?.tokens, 60)
        XCTAssertEqual(result?.confidence, .localParsed, "summed day buckets are locally parsed")
        XCTAssertEqual(result?.usedDailyFallback, true)
    }

    func testMixedSourcesSumAndFlagTheFallback() {
        let result = MaxxerMath.lifetimeTotal(in: [
            snapshot(.claudeCode, lifetime: TokenUsage(inputTokens: 1_000, confidence: .exact)),
            snapshot(.cursor, lifetime: nil, dailyTotals: days([25, 25])),
        ])

        XCTAssertEqual(result?.tokens, 1_050)
        XCTAssertEqual(result?.contributingProviders, 2)
        XCTAssertEqual(result?.usedDailyFallback, true)
        XCTAssertEqual(result?.confidence, .localParsed,
                       "aggregate degrades to the weakest contributor")
    }

    // MARK: - Providers with neither source contribute nothing

    func testProviderWithNoLifetimeAndNoDailyTotalsIsExcludedNotZeroed() {
        let result = MaxxerMath.lifetimeTotal(in: [
            snapshot(.claudeCode, lifetime: TokenUsage(inputTokens: 500, confidence: .exact)),
            snapshot(.antigravity),
            snapshot(.gemini),
        ])

        XCTAssertEqual(result?.tokens, 500)
        XCTAssertEqual(result?.contributingProviders, 1,
                       "nil-lifetime providers must not pad the contributor count")
        XCTAssertEqual(result?.confidence, .exact,
                       "an excluded provider must not drag confidence down")
    }

    func testEmptyDailyTotalsDoNotCountAsAContribution() {
        XCTAssertNil(MaxxerMath.lifetimeTotal(in: [snapshot(.cursor, dailyTotals: [:])]))
    }

    func testNilWhenNoProviderContributes() {
        XCTAssertNil(MaxxerMath.lifetimeTotal(in: []))
        XCTAssertNil(MaxxerMath.lifetimeTotal(in: [snapshot(.gemini), snapshot(.antigravity)]),
                     "no data at all must read as unknown, never a confident 0")
    }

    // MARK: - Hidden providers

    func testHiddenProvidersAreExcluded() {
        let snapshots = [
            snapshot(.claudeCode, lifetime: TokenUsage(inputTokens: 1_000, confidence: .exact)),
            snapshot(.codex, lifetime: TokenUsage(inputTokens: 500, confidence: .localParsed)),
        ]

        let result = MaxxerMath.lifetimeTotal(in: snapshots, hiddenProviders: [.codex])

        XCTAssertEqual(result?.tokens, 1_000)
        XCTAssertEqual(result?.contributingProviders, 1)
        XCTAssertEqual(result?.confidence, .exact,
                       "a hidden provider must not influence the badge")
    }

    func testAllHiddenYieldsNil() {
        let snapshots = [snapshot(.claudeCode, lifetime: TokenUsage(inputTokens: 1_000, confidence: .exact))]
        XCTAssertNil(MaxxerMath.lifetimeTotal(in: snapshots, hiddenProviders: [.claudeCode]))
    }

    // MARK: - Confidence degradation

    func testWorstConfidenceTakesTheWeakest() {
        XCTAssertEqual(MaxxerMath.worstConfidence([.exact, .providerReported]), .providerReported)
        XCTAssertEqual(MaxxerMath.worstConfidence([.exact, .estimated, .localParsed]), .estimated)
        XCTAssertEqual(MaxxerMath.worstConfidence([.exact, .unavailable]), .unavailable)
        XCTAssertEqual(MaxxerMath.worstConfidence([.exact]), .exact)
    }

    func testWorstConfidenceOfNothingIsUnavailable() {
        XCTAssertEqual(MaxxerMath.worstConfidence([]), .unavailable)
    }

    // MARK: - USD formatting

    func testFormatUSDIsFixedTwoDecimalsWithGrouping() {
        XCTAssertEqual(MaxxerMath.formatUSD(684.2), "$684.20")
        XCTAssertEqual(MaxxerMath.formatUSD(0), "$0.00")
        XCTAssertEqual(MaxxerMath.formatUSD(1_234.567), "$1,234.57")
        XCTAssertEqual(MaxxerMath.formatUSD(1_000_000), "$1,000,000.00")
    }

    func testFormatUSDPlaceholderForUnknownAndNonFinite() {
        XCTAssertEqual(MaxxerMath.formatUSD(nil), "—")
        XCTAssertEqual(MaxxerMath.formatUSD(.infinity), "—")
        XCTAssertEqual(MaxxerMath.formatUSD(.nan), "—")
    }

    // MARK: - Multiple formatting

    func testFormatMultipleUsesTrueMultiplicationSign() {
        XCTAssertEqual(MaxxerMath.formatMultiple(3.42), "3.4\u{00D7}")
        XCTAssertEqual(MaxxerMath.formatMultiple(1), "1.0\u{00D7}")
        XCTAssertEqual(MaxxerMath.formatMultiple(12.35), "12.4\u{00D7}")
        XCTAssertFalse(MaxxerMath.formatMultiple(3.4).contains("x"), "must not use the letter x")
    }

    func testFormatMultiplePlaceholderForUnknownAndNonFinite() {
        XCTAssertEqual(MaxxerMath.formatMultiple(nil), "—")
        // A multiple over a zero plan cost is undefined — never "∞×".
        XCTAssertEqual(MaxxerMath.formatMultiple(.infinity), "—")
        XCTAssertEqual(MaxxerMath.formatMultiple(.nan), "—")
    }

    func testUnknownPlaceholderIsTheEmDashUsedAcrossTheApp() {
        XCTAssertEqual(MaxxerMath.unknownPlaceholder, "—")
    }
}
