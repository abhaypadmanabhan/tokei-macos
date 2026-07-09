import XCTest
@testable import AIUsageDashboardCore

/// Unit tests for the pure Token-Maxxer math (`MaxxerMath`), compiled into this
/// test bundle from `UI/MenuBar/MaxxerMath.swift` (see project.yml) so the pace
/// notch + tightest-window logic is covered without any UI snapshotting.
final class MaxxerMathTests: XCTestCase {

    // Fixed epoch anchor keeps every pace assertion deterministic (no wall clock).
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let week: TimeInterval = 7 * 86_400

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

    // MARK: - Pace: degradation (no crash, returns nil → UI shows "—")

    func testPaceNilWhenResetMissing() {
        XCTAssertNil(MaxxerMath.pace(usedPercent: 40, windowType: .weekly, resetAt: nil, now: now))
    }

    func testPaceNilForNonLinearWindow() {
        let reset = now.addingTimeInterval(3_600)
        XCTAssertNil(MaxxerMath.pace(usedPercent: 40, windowType: .session, resetAt: reset, now: now))
        XCTAssertNil(MaxxerMath.pace(usedPercent: 40, windowType: .credits, resetAt: reset, now: now))
    }

    // MARK: - Pace: verdicts around the tolerance band

    /// resetAt at the window midpoint → 50% elapsed → expected 50%.
    private func midWeek() -> Date { now.addingTimeInterval(week / 2) }

    func testOnPaceWhenUsageMatchesElapsed() {
        let pace = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 50, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(pace.elapsedFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pace.expectedPercent, 50, accuracy: 1e-9)
        XCTAssertEqual(pace.delta, 0, accuracy: 1e-9)
        XCTAssertEqual(pace.verdict, .onPace)
    }

    func testAheadWhenUsageOutrunsElapsed() {
        let pace = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 58, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(pace.verdict, .ahead)
        XCTAssertEqual(pace.delta, 8, accuracy: 1e-9)
    }

    func testHeadroomWhenUsageTrailsElapsed() {
        let pace = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 42, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(pace.verdict, .headroom)
        XCTAssertEqual(pace.delta, -8, accuracy: 1e-9)
    }

    func testToleranceBoundaryIsInclusiveOnPace() {
        // delta == +5 (the band edge) stays on-pace; +5.01 tips to ahead.
        let edge = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 55, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(edge.verdict, .onPace)
        let over = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 55.01, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(over.verdict, .ahead)
        // Symmetric on the low side.
        let lowEdge = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 45, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(lowEdge.verdict, .onPace)
        let under = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 44.99, windowType: .weekly, resetAt: midWeek(), now: now))
        XCTAssertEqual(under.verdict, .headroom)
    }

    func testCustomToleranceWidensBand() {
        // delta +8 is ahead at default 5, but on-pace with a 10pt tolerance.
        let pace = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 58, windowType: .weekly,
                                                  resetAt: midWeek(), now: now, tolerance: 10))
        XCTAssertEqual(pace.verdict, .onPace)
    }

    // MARK: - Pace: elapsed-fraction clamping

    func testElapsedClampsToOneWhenResetInPast() {
        // reset already passed → fully elapsed → expected 100; any real usage trails it.
        let pace = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 40, windowType: .weekly,
                                                  resetAt: now.addingTimeInterval(-3_600), now: now))
        XCTAssertEqual(pace.elapsedFraction, 1, accuracy: 1e-9)
        XCTAssertEqual(pace.expectedPercent, 100, accuracy: 1e-9)
        XCTAssertEqual(pace.verdict, .headroom)
    }

    func testElapsedClampsToZeroWhenResetBeyondOneSpan() {
        // reset two weeks out (> one 7d span) → not yet started → expected 0.
        let pace = try! XCTUnwrap(MaxxerMath.pace(usedPercent: 10, windowType: .weekly,
                                                  resetAt: now.addingTimeInterval(2 * week), now: now))
        XCTAssertEqual(pace.elapsedFraction, 0, accuracy: 1e-9)
        XCTAssertEqual(pace.expectedPercent, 0, accuracy: 1e-9)
        XCTAssertEqual(pace.verdict, .ahead)
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
            util(.antigravity, .fiveHour, 61),
        ])
        XCTAssertEqual(picked?.providerID, .claudeCode)
        XCTAssertEqual(picked?.usedPercent, 92)
    }

    func testTightestWindowTieKeepsFirstSeen() {
        // Two equal maxima: the first in input order wins (deterministic, no flicker).
        let picked = MaxxerMath.tightestWindow(in: [
            util(.cursor, .monthly, 80),
            util(.claudeCode, .weekly, 80),
        ])
        XCTAssertEqual(picked?.providerID, .cursor)
    }
}
