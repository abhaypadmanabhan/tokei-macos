import XCTest
@testable import AIUsageDashboardCore

/// Unit tests for the pure Token-Maxxer math (`MaxxerMath`), compiled into this
/// test bundle from `UI/MenuBar/MaxxerMath.swift` (see project.yml) so the
/// previous-period span + tightest-window logic is covered without any UI snapshotting.
final class MaxxerMathTests: XCTestCase {

    // Fixed epoch anchor keeps every assertion deterministic (no wall clock).
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Canonical window duration

    func testCanonicalDurationsForRollingWindows() {
        XCTAssertEqual(MaxxerMath.canonicalWindowDuration(for: .fiveHour), 5 * 3_600)
        XCTAssertEqual(MaxxerMath.canonicalWindowDuration(for: .daily), 24 * 3_600)
        XCTAssertEqual(MaxxerMath.canonicalWindowDuration(for: .weekly), 7 * 86_400)
        XCTAssertEqual(MaxxerMath.canonicalWindowDuration(for: .monthly), 30 * 86_400)
    }

    func testNoCanonicalDurationForNonLinearWindows() {
        for type in [QuotaWindowType.session, .credits, .perModel, .lifetime] {
            XCTAssertNil(MaxxerMath.canonicalWindowDuration(for: type),
                         "\(type) has no fixed linear span")
        }
    }

    // MARK: - Tightest window selection (#38)

    private func util(_ id: ProviderID, _ window: QuotaWindowType, _ percent: Double) -> Utilization {
        Utilization(providerID: id, window: window, usedPercent: percent, confidence: .providerReported)
    }

    func testTightestWindowNilWhenEmpty() {
        XCTAssertNil(MaxxerMath.tightestWindow(in: []))
    }

    func testTightestWindowPicksHighestUtilization() {
        let picked = MaxxerMath.tightestWindow(in: [
            util(.cursor, .monthly, 30),
            util(.claudeCode, .weekly, 92),
            util(.antigravity, .fiveHour, 61)
        ])
        XCTAssertEqual(picked?.providerID, .claudeCode)
        XCTAssertEqual(picked?.usedPercent, 92)
    }

    func testTightestWindowTieKeepsFirstSeen() {
        // Two equal maxima: the first in input order wins (deterministic, no flicker).
        let picked = MaxxerMath.tightestWindow(in: [
            util(.cursor, .monthly, 80),
            util(.claudeCode, .weekly, 80)
        ])
        XCTAssertEqual(picked?.providerID, .cursor)
    }

    // MARK: - Route-here target (#37)

    func testRouteTargetNilWithFewerThanTwoReadings() {
        XCTAssertNil(MaxxerMath.routeTarget(in: [], now: now))
        XCTAssertNil(MaxxerMath.routeTarget(in: [util(.cursor, .monthly, 10)], now: now))
    }

    func testRouteTargetPicksLeastFilledWithHeadroomAndSpread() {
        let target = MaxxerMath.routeTarget(in: [
            util(.claudeCode, .weekly, 92),
            util(.cursor, .monthly, 20),
            util(.antigravity, .fiveHour, 55)
        ], now: now)
        XCTAssertEqual(target?.providerID, .cursor)
    }

    func testRouteTargetNilWhenSpreadTooSmall() {
        // All bunched together → routing advice is noise → no chip.
        XCTAssertNil(MaxxerMath.routeTarget(in: [
            util(.cursor, .monthly, 60),
            util(.claudeCode, .weekly, 68)
        ], now: now))
    }

    func testRouteTargetNilWhenLeastFilledStillTooFull() {
        // Big spread, but even the emptiest (75%) is past the headroom bar → no chip.
        XCTAssertNil(MaxxerMath.routeTarget(in: [
            util(.claudeCode, .weekly, 98),
            util(.cursor, .monthly, 75)
        ], now: now))
    }

    func testRouteTargetTieKeepsFirstSeen() {
        let target = MaxxerMath.routeTarget(in: [
            util(.cursor, .monthly, 10),
            util(.antigravity, .fiveHour, 10),
            util(.claudeCode, .weekly, 90)
        ], now: now)
        XCTAssertEqual(target?.providerID, .cursor)
    }

    // MARK: - Route-here target is trust-gated (WP-3)

    private func util(
        _ id: ProviderID,
        _ window: QuotaWindowType,
        _ percent: Double,
        confidence: MetricConfidence,
        observedAt: Date? = nil
    ) -> Utilization {
        Utilization(providerID: id, window: window, usedPercent: percent,
                    confidence: confidence, observedAt: observedAt)
    }

    /// The 2026-07-27 bug, applied to the human-facing chip: a `local_estimate` 0% is
    /// absence of data, not free quota. It must never win the chip, and with only one
    /// trusted reading left there is nothing to be least of, so there is no chip at all.
    func testRouteTargetIgnoresLocalEstimateReading() {
        let target = MaxxerMath.routeTarget(in: [
            util(.claudeCode, .weekly, 0, confidence: .estimated),
            util(.cursor, .monthly, 75, confidence: .providerReported)
        ], now: now)
        XCTAssertNil(target)
    }

    /// With two trusted readings present, an untrusted lower one is ignored rather
    /// than poisoning the pick.
    func testRouteTargetPicksLeastFilledTrustedIgnoringLowerUntrustedOne() {
        let target = MaxxerMath.routeTarget(in: [
            util(.claudeCode, .weekly, 2, confidence: .localParsed),
            util(.cursor, .monthly, 20, confidence: .providerReported),
            util(.antigravity, .fiveHour, 88, confidence: .providerReported)
        ], now: now)
        XCTAssertEqual(target?.providerID, .cursor)
    }

    /// An officially-labelled but hours-old reading is not live data either.
    func testRouteTargetIgnoresStaleOfficialReading() {
        let target = MaxxerMath.routeTarget(in: [
            util(.claudeCode, .weekly, 5, confidence: .providerReported,
                 observedAt: now.addingTimeInterval(-2 * 3_600)),
            util(.cursor, .monthly, 60, confidence: .providerReported, observedAt: now)
        ], now: now)
        XCTAssertNil(target)
    }

    /// Peak-then-gate reaches the chip too: a provider whose *tightest* window is
    /// untrusted is not routable on the strength of a looser confirmed one.
    func testRouteTargetDoesNotRescueProviderViaLooserTrustedWindow() {
        let target = MaxxerMath.routeTarget(in: [
            util(.claudeCode, .weekly, 10, confidence: .providerReported),
            util(.claudeCode, .fiveHour, 30, confidence: .estimated),
            util(.cursor, .monthly, 80, confidence: .providerReported),
            util(.antigravity, .fiveHour, 40, confidence: .providerReported)
        ], now: now)
        // Claude's peak (30) is untrusted → excluded. Antigravity (40) is the least
        // trusted peak; 80 - 40 = 40 ≥ 15 spread and 40 ≤ 70 → it takes the chip.
        XCTAssertEqual(target?.providerID, .antigravity)
    }

    /// A provider is represented by its tightest window, not its friendliest one.
    func testRouteTargetUsesPerProviderPeak() {
        let target = MaxxerMath.routeTarget(in: [
            util(.cursor, .monthly, 5, confidence: .providerReported),
            util(.cursor, .weekly, 90, confidence: .providerReported),
            util(.claudeCode, .weekly, 20, confidence: .providerReported)
        ], now: now)
        XCTAssertEqual(target?.providerID, .claudeCode)
    }
}
