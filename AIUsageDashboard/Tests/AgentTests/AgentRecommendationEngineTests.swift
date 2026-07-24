import XCTest
@testable import AIUsageDashboardCore

final class AgentRecommendationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func util(
        _ providerID: ProviderID,
        _ percent: Double,
        window: QuotaWindowType = .weekly,
        resetAt: Date? = nil
    ) -> Utilization {
        Utilization(providerID: providerID, window: window, usedPercent: percent, resetAt: resetAt, confidence: .exact)
    }

    private let names: [ProviderID: String] = [
        .claudeCode: "Claude Code", .codex: "OpenAI Codex", .antigravity: "Antigravity"
    ]

    func testRoutesToLeastFilledAndAvoidsOverThreshold() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.antigravity, 92), util(.codex, 31), util(.claudeCode, 60)],
            displayNames: names,
            now: now
        )
        XCTAssertEqual(rec?.routeTo, "codex")
        XCTAssertEqual(rec?.avoid, ["antigravity"])
        XCTAssertTrue(rec?.reason.contains("Antigravity") == true)
        XCTAssertTrue(rec?.reason.contains("route to OpenAI Codex") == true)
    }

    func testPeakWindowPerProviderDrivesRouting() {
        // Codex has a tight weekly window too — its peak (95) must count, not the low one.
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.codex, 20, window: .daily), util(.codex, 95, window: .weekly), util(.claudeCode, 40)],
            displayNames: names,
            now: now
        )
        XCTAssertEqual(rec?.routeTo, "claude_code")
        XCTAssertEqual(rec?.avoid, ["codex"])
    }

    func testNoRouteTargetWithSingleProvider() {
        // One provider, below threshold → nothing to avoid, not enough to route → nil.
        let rec = AgentRecommendationEngine.recommend(from: [util(.codex, 20)], displayNames: names, now: now)
        XCTAssertNil(rec)
    }

    func testSingleProviderOverThresholdStillWarns() {
        // One provider, but it's maxed → avoid it even though there's no routeTo.
        let rec = AgentRecommendationEngine.recommend(from: [util(.antigravity, 90)], displayNames: names, now: now)
        XCTAssertNil(rec?.routeTo)
        XCTAssertEqual(rec?.avoid, ["antigravity"])
    }

    func testNoRouteWhenAllProvidersAreMaxed() {
        // Least-filled is still over threshold → no safe target, both avoided.
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.antigravity, 92), util(.codex, 88)],
            displayNames: names,
            now: now
        )
        XCTAssertNil(rec?.routeTo)
        XCTAssertEqual(rec?.avoid.sorted(), ["antigravity", "codex"])
    }

    func testEmptyUtilizationsProduceNoRecommendation() {
        XCTAssertNil(AgentRecommendationEngine.recommend(from: [], displayNames: names, now: now))
    }

    func testReasonIncludesResetDeltaWhenAvailable() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.antigravity, 92, resetAt: now.addingTimeInterval(3 * 3600)), util(.codex, 31)],
            displayNames: names,
            now: now
        )
        XCTAssertTrue(rec?.reason.contains("resets in 3h") == true)
    }
}
