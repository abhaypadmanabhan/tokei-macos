import XCTest
@testable import AIUsageDashboardCore

/// The `reason` string has to explain an exclusion in terms a reader can act on.
/// (`AgentRecommendationEngineTests` owns the routing contract itself and stays
/// untouched; this file covers the wording of the explanation.)
final class AgentRecommendationReasonTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let names: [ProviderID: String] = [
        .claudeCode: "Claude Code", .codex: "OpenAI Codex"
    ]

    /// A future-dated reading is excluded as a clock problem, so the reason must say
    /// that. Reporting an age ("reading is 0s old") would contradict the exclusion it
    /// is meant to explain and send the reader looking for a staleness bug instead of
    /// a skewed clock.
    func testFutureDatedReadingIsExplainedAsAClockProblemNotAnAge() {
        let rec = AgentRecommendationEngine.recommend(
            from: [
                Utilization(providerID: .claudeCode, window: .weekly, usedPercent: 5,
                            confidence: .providerReported,
                            observedAt: now.addingTimeInterval(3 * 3_600)),
                Utilization(providerID: .codex, window: .weekly, usedPercent: 75,
                            confidence: .providerReported, observedAt: now)
            ],
            displayNames: names,
            now: now
        )
        let reason = rec?.reason ?? ""
        XCTAssertNil(rec?.routeTo)
        XCTAssertTrue(reason.contains("Claude Code excluded from routing"), reason)
        XCTAssertTrue(reason.contains("timestamped in the future"), reason)
        XCTAssertFalse(reason.contains("old"), "must not report a bogus age, got: \(reason)")
    }
}
