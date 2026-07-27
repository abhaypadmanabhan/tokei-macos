import XCTest
@testable import AIUsageDashboardCore

/// Contract tests for the ONE canonical "where should work go" rule (WP-3).
///
/// `AgentRecommendationEngineTests` covers the agent-facing wrapper and
/// `MaxxerMathTests` covers the UI-facing one; this file pins the shared rule itself,
/// including the two invariants that must never be "simplified":
/// peak-then-gate ordering, and the avoid-from-all / routeTo-from-trusted asymmetry.
final class RouteTargetPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func util(
        _ providerID: ProviderID,
        _ percent: Double,
        window: QuotaWindowType = .weekly,
        confidence: MetricConfidence = .exact,
        observedAt: Date? = nil
    ) -> Utilization {
        Utilization(providerID: providerID, window: window, usedPercent: percent,
                    confidence: confidence, observedAt: observedAt)
    }

    // MARK: - Peaking

    func testPeaksReduceEachProviderToItsTightestWindow() {
        let peaks = RouteTargetPolicy.peaks(in: [
            util(.codex, 20, window: .daily),
            util(.codex, 95, window: .weekly),
            util(.claudeCode, 40),
        ])
        XCTAssertEqual(peaks.map(\.providerID), [.claudeCode, .codex])
        XCTAssertEqual(peaks.first(where: { $0.providerID == .codex })?.usedPercent, 95)
    }

    func testPeaksAreInStableProviderOrder() {
        let peaks = RouteTargetPolicy.peaks(in: [
            util(.antigravity, 10), util(.cursor, 10), util(.claudeCode, 10),
        ])
        XCTAssertEqual(peaks.map(\.providerID), [.claudeCode, .cursor, .antigravity])
    }

    // MARK: - Invariant: peak-then-gate ordering

    /// The ordering that must not be flipped. Claude's *tightest* window is an
    /// untrusted 30%; its confirmed weekly 10% must not rescue it into routability,
    /// because the window about to run out is the unknown one.
    func testUntrustedPeakIsNotRescuedByALooserTrustedWindow() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.claudeCode, 10, window: .weekly),
            util(.claudeCode, 30, window: .fiveHour, confidence: .estimated),
            util(.codex, 40),
            util(.cursor, 55),
        ], now: now)
        XCTAssertEqual(decision.routeTo?.providerID, .codex)
        XCTAssertEqual(decision.excluded.map(\.providerID), [.claudeCode])
    }

    // MARK: - Invariant: avoid from all, routeTo from trusted

    func testAvoidIncludesUntrustedReadingsButRoutingDoesNot() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.antigravity, 92, confidence: .estimated),
            util(.claudeCode, 5, confidence: .estimated),
            util(.codex, 31),
            util(.cursor, 60),
        ], now: now)
        XCTAssertEqual(decision.avoid.map(\.providerID), [.antigravity])
        XCTAssertEqual(decision.routeTo?.providerID, .codex)
        // Antigravity is already named in `avoid`, so it isn't repeated as excluded.
        XCTAssertEqual(decision.excluded.map(\.providerID), [.claudeCode])
    }

    // MARK: - Trust gate

    func testLocalEstimateIsNeverARouteTarget() {
        for confidence in [MetricConfidence.estimated, .localParsed, .unavailable] {
            let decision = RouteTargetPolicy.agent.evaluate([
                util(.claudeCode, 0, confidence: confidence),
                util(.codex, 75),
                util(.cursor, 60),
            ], now: now)
            XCTAssertEqual(decision.routeTo?.providerID, .cursor,
                           "\(confidence) must not be routable")
        }
    }

    func testOfficialButStaleReadingIsNotRoutable() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.claudeCode, 0, observedAt: now.addingTimeInterval(-2 * 3_600)),
            util(.codex, 75, observedAt: now),
        ], now: now)
        XCTAssertNil(decision.routeTo)
    }

    func testReadingWithUnknownAgeStaysRoutable() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.codex, 31), util(.claudeCode, 60),
        ], now: now)
        XCTAssertEqual(decision.routeTo?.providerID, .codex)
    }

    func testReadingInsideMaxRoutableAgeStaysRoutable() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.codex, 31, observedAt: now.addingTimeInterval(-29 * 60)),
            util(.claudeCode, 60, observedAt: now),
        ], now: now)
        XCTAssertEqual(decision.routeTo?.providerID, .codex)
    }

    // MARK: - Thresholds

    func testNoTargetWhenFewerThanTwoTrustedProviders() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.claudeCode, 0, confidence: .estimated), util(.codex, 75),
        ], now: now)
        XCTAssertNil(decision.routeTo)
    }

    func testNoTargetWhenLeastFilledIsAtTheAvoidThreshold() {
        let decision = RouteTargetPolicy.agent.evaluate([
            util(.codex, 85), util(.claudeCode, 92),
        ], now: now)
        XCTAssertNil(decision.routeTo)
        XCTAssertEqual(decision.avoid.map(\.providerID), [.claudeCode, .codex])
    }

    // MARK: - The two tunings

    /// The spread gate is a UI-presentation choice and must not leak into the agent
    /// rule: an agent wants the best available answer even in a tight field.
    func testSpreadGateAppliesToUITuningOnly() {
        let bunched = [util(.codex, 60), util(.claudeCode, 68)]
        XCTAssertEqual(RouteTargetPolicy.agent.evaluate(bunched, now: now).routeTo?.providerID, .codex)
        XCTAssertNil(RouteTargetPolicy.ui.evaluate(bunched, now: now).routeTo)
    }

    /// Likewise the stricter 70% chip ceiling: 75% is routable for an agent (below the
    /// 85% avoid line) but not worth a chip.
    func testRouteTargetCeilingAppliesToUITuningOnly() {
        let readings = [util(.codex, 75), util(.claudeCode, 98)]
        XCTAssertEqual(RouteTargetPolicy.agent.evaluate(readings, now: now).routeTo?.providerID, .codex)
        XCTAssertNil(RouteTargetPolicy.ui.evaluate(readings, now: now).routeTo)
    }

    func testUITuningKeepsTheAgentTrustGate() {
        XCTAssertEqual(RouteTargetPolicy.ui.routableConfidences,
                       RouteTargetPolicy.agent.routableConfidences)
        XCTAssertEqual(RouteTargetPolicy.ui.maxRoutableAge,
                       RouteTargetPolicy.agent.maxRoutableAge)
    }

    // MARK: - Nothing to say

    func testEmptyInputProducesAnEmptyDecision() {
        let decision = RouteTargetPolicy.agent.evaluate([], now: now)
        XCTAssertTrue(decision.hasNothingToSay)
    }

    func testSingleHealthyProviderHasNothingToSay() {
        XCTAssertTrue(RouteTargetPolicy.agent.evaluate([util(.codex, 20)], now: now).hasNothingToSay)
    }
}
