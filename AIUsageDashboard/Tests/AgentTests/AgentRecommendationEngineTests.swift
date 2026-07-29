import XCTest
@testable import AIUsageDashboardCore

final class AgentRecommendationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func util(
        _ providerID: ProviderID,
        _ percent: Double,
        window: QuotaWindowType = .weekly,
        resetAt: Date? = nil,
        confidence: MetricConfidence = .exact,
        observedAt: Date? = nil
    ) -> Utilization {
        Utilization(
            providerID: providerID,
            window: window,
            usedPercent: percent,
            resetAt: resetAt,
            confidence: confidence,
            observedAt: observedAt
        )
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

    // MARK: - Trust gating (a stale reading is absence of data, not free quota)

    /// The 2026-07-27 bug: Claude's only window was a stale cached 0% (`.estimated`),
    /// Codex reported an official 75%, and the engine routed fan-out work to Claude.
    /// A `local_estimate` must never win routing — least-utilized is only meaningful
    /// among providers we actually have numbers for.
    func testStaleEstimateDoesNotWinRoutingOverOfficialReading() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 0, confidence: .estimated), util(.codex, 75)],
            displayNames: names,
            now: now
        )
        XCTAssertNotEqual(rec?.routeTo, "claude_code")
    }

    /// Only Codex is trusted here, so there is no second trusted reading to compare
    /// against — the honest answer is "no target", not "the one I can't see".
    func testNoRouteTargetWhenFewerThanTwoTrustedReadings() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 0, confidence: .estimated), util(.codex, 75)],
            displayNames: names,
            now: now
        )
        XCTAssertNil(rec?.routeTo)
    }

    /// The exclusion must be visible. A silently-dropped provider reads as
    /// "considered and rejected on the numbers", which is a different claim.
    func testReasonNamesAProviderExcludedForLowConfidence() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 0, confidence: .estimated), util(.codex, 75)],
            displayNames: names,
            now: now
        )
        let reason = rec?.reason ?? ""
        XCTAssertTrue(reason.contains("Claude Code"), "should name the provider, got: \(reason)")
        XCTAssertTrue(reason.contains("excluded"), "should say it was excluded, got: \(reason)")
        XCTAssertTrue(reason.contains("local estimate"), "should give the cause, got: \(reason)")
    }

    /// Asymmetric on purpose: an untrusted number is not evidence of headroom, but a
    /// high one is still evidence of pressure. Avoid must stay inclusive.
    func testUntrustedProviderOverThresholdIsStillAvoided() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.antigravity, 92, confidence: .estimated), util(.codex, 31), util(.claudeCode, 40)],
            displayNames: names,
            now: now
        )
        XCTAssertEqual(rec?.avoid, ["antigravity"])
        XCTAssertEqual(rec?.routeTo, "codex")
    }

    /// With two trusted readings present, an untrusted low reading is ignored for
    /// routing rather than poisoning it.
    func testRoutesToLeastFilledTrustedProviderIgnoringLowerUntrustedOne() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 5, confidence: .estimated), util(.codex, 31), util(.antigravity, 60)],
            displayNames: names,
            now: now
        )
        XCTAssertEqual(rec?.routeTo, "codex")
    }

    /// `.providerReported` is an official number (that's what a healthy live fetch
    /// produces) and must remain routable — the gate is on trust, not on `.exact`.
    func testProviderReportedConfidenceIsTrustedForRouting() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.codex, 31, confidence: .providerReported),
                   util(.claudeCode, 60, confidence: .providerReported)],
            displayNames: names,
            now: now
        )
        XCTAssertEqual(rec?.routeTo, "codex")
    }

    /// Belt-and-braces behind the confidence gate: a provider could serve a cached
    /// reading *without* downgrading its confidence (nothing in the codebase enforces
    /// that convention — `ClaudeUsageClient` and `AntigravityQuotaClient` each do it by
    /// hand). An officially-labelled but hours-old number is still not live data.
    func testOfficialButStaleReadingIsNotRoutable() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.claudeCode, 0, observedAt: now.addingTimeInterval(-2 * 3600)),
                   util(.codex, 75, observedAt: now)],
            displayNames: names,
            now: now
        )
        XCTAssertNil(rec?.routeTo)
    }

    /// A reading with no `observedAt` at all (providers that don't report one yet) must
    /// stay routable — the gate is "known to be old", not "not known to be fresh".
    func testMissingObservedAtDoesNotBlockRouting() {
        let rec = AgentRecommendationEngine.recommend(
            from: [util(.codex, 31), util(.claudeCode, 60)],
            displayNames: names,
            now: now
        )
        XCTAssertEqual(rec?.routeTo, "codex")
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
