import XCTest
@testable import AIUsageDashboardCore

/// `QuotaPace`: used share vs elapsed share of a window, ±5-point band (T3 rule).
final class QuotaPaceTests: XCTestCase {
    // Fixed anchor so no assertion depends on the wall clock.
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let week: TimeInterval = 7 * 86_400

    private func window(
        _ type: QuotaWindowType = .weekly,
        used: Double? = 50,
        limit: Double? = 100,
        remaining: Double? = nil,
        resetIn: TimeInterval? = 7 * 86_400 / 2,
        duration: TimeInterval? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .claudeCode,
            type: type,
            used: used,
            limit: limit,
            remaining: remaining,
            resetAt: resetIn.map { now.addingTimeInterval($0) },
            confidence: .providerReported,
            source: "test",
            windowDuration: duration
        )
    }

    // MARK: - Window length

    func testImpliedDurationsByType() {
        XCTAssertEqual(QuotaPace.duration(for: .session, reported: nil), 5 * 3_600)
        XCTAssertEqual(QuotaPace.duration(for: .fiveHour, reported: nil), 5 * 3_600)
        XCTAssertEqual(QuotaPace.duration(for: .daily, reported: nil), 24 * 3_600)
        XCTAssertEqual(QuotaPace.duration(for: .weekly, reported: nil), week)
        for type in [QuotaWindowType.monthly, .credits, .lifetime, .perModel] {
            XCTAssertNil(QuotaPace.duration(for: type, reported: nil), "\(type) has no fixed length")
        }
    }

    func testReportedDurationWinsOverType() {
        XCTAssertEqual(QuotaPace.duration(for: .monthly, reported: 30 * 86_400), 30 * 86_400)
        XCTAssertEqual(QuotaPace.duration(for: .session, reported: week), week)
        XCTAssertNil(QuotaPace.duration(for: .weekly, reported: 0), "a zero length is not a window")
        XCTAssertNil(QuotaPace.duration(for: .weekly, reported: -60))
    }

    func testReportedDurationDrivesElapsedShare() throws {
        // A "session" the provider says lasts 7 days, half gone: 50%. The implied 5 h would clamp to 0.
        let pace = try XCTUnwrap(QuotaPace(window: window(.session, resetIn: week / 2, duration: week), now: now))
        XCTAssertEqual(pace.elapsedPercent, 50, accuracy: 1e-9)
    }

    func testMonthlyGetsPaceOnlyWhenDurationReported() throws {
        XCTAssertNil(QuotaPace(window: window(.monthly, resetIn: 10 * 86_400), now: now))
        let pace = try XCTUnwrap(QuotaPace(window: window(.monthly, used: 10, resetIn: 10 * 86_400,
                                                          duration: 30 * 86_400), now: now))
        XCTAssertEqual(pace.elapsedPercent, 200.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(pace.state, .behind)
    }

    // MARK: - Elapsed share

    func testElapsedShareFormula() throws {
        // 5 h window resetting in 1 h: (5 h − 1 h) / 5 h = 80%.
        let pace = try XCTUnwrap(QuotaPace(window: window(.fiveHour, used: 80, resetIn: 3_600), now: now))
        XCTAssertEqual(pace.elapsedPercent, 80, accuracy: 1e-9)
        XCTAssertEqual(pace.delta, 0, accuracy: 1e-9)
        XCTAssertEqual(pace.state, .onPace)
    }

    func testElapsedClampsToHundredWhenResetPassed() throws {
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 40, resetIn: -3_600), now: now))
        XCTAssertEqual(pace.elapsedPercent, 100, accuracy: 1e-9)
        XCTAssertEqual(pace.state, .behind)
    }

    func testElapsedClampsToZeroWhenResetBeyondOneWindow() throws {
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 10, resetIn: 2 * week), now: now))
        XCTAssertEqual(pace.elapsedPercent, 0, accuracy: 1e-9)
        XCTAssertEqual(pace.state, .ahead)
    }

    func testUsedShareClampsToHundred() throws {
        let pace = try XCTUnwrap(QuotaPace(usedPercent: 140, windowType: .weekly, windowDuration: nil,
                                           resetAt: now.addingTimeInterval(week / 2), now: now))
        XCTAssertEqual(pace.usedPercent, 100, accuracy: 1e-9)
    }

    // MARK: - State band (half the week gone → elapsed 50%)

    func testBandEdgesStayOnPace() {
        XCTAssertEqual(QuotaPace(window: window(used: 55), now: now)?.state, .onPace)
        XCTAssertEqual(QuotaPace(window: window(used: 45), now: now)?.state, .onPace)
        XCTAssertEqual(QuotaPace(window: window(used: 50), now: now)?.state, .onPace)
    }

    func testJustPastTheBandTips() {
        XCTAssertEqual(QuotaPace(window: window(used: 55.01), now: now)?.state, .ahead)
        XCTAssertEqual(QuotaPace(window: window(used: 44.99), now: now)?.state, .behind)
    }

    func testDeltaIsSignedPoints() throws {
        let ahead = try XCTUnwrap(QuotaPace(window: window(used: 62), now: now))
        XCTAssertEqual(ahead.delta, 12, accuracy: 1e-9)
        let behind = try XCTUnwrap(QuotaPace(window: window(used: 32), now: now))
        XCTAssertEqual(behind.delta, -18, accuracy: 1e-9)
    }

    func testNilWhenOnlyRemainingIsReported() {
        // The drill-in gauge shows a remaining-only window's usage as unknown, so pace
        // must not derive a used share from `limit - remaining` and claim "room to use".
        XCTAssertNil(QuotaPace(window: window(used: nil, remaining: 70), now: now))
    }

    // MARK: - No honest pace → nil

    func testNilWhenResetMissing() {
        XCTAssertNil(QuotaPace(window: window(resetIn: nil), now: now))
    }

    func testNilWhenUsedMissing() {
        XCTAssertNil(QuotaPace(window: window(used: nil), now: now))
        XCTAssertNil(QuotaPace(usedPercent: nil, windowType: .weekly, windowDuration: nil,
                               resetAt: now.addingTimeInterval(60), now: now))
        XCTAssertNil(QuotaPace(usedPercent: .nan, windowType: .weekly, windowDuration: nil,
                               resetAt: now.addingTimeInterval(60), now: now))
    }

    func testNilWhenNotAPercentGauge() {
        XCTAssertNil(QuotaPace(window: window(limit: nil), now: now), "no denominator")
        XCTAssertNil(QuotaPace(window: window(limit: 0), now: now))
        XCTAssertNil(QuotaPace(window: window(.credits, used: 40, limit: 100, duration: week), now: now),
                     "a credit balance is not a window that refills on a clock")
    }

    func testNilWhenLengthUnknown() {
        XCTAssertNil(QuotaPace(window: window(.lifetime), now: now))
        XCTAssertNil(QuotaPace(window: window(.perModel), now: now))
    }

    // MARK: - Run-out forecast (expected instants worked by hand, not by the formula)

    private func assertRunsOut(_ pace: QuotaPace, after seconds: TimeInterval,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        guard case let .runsOut(at) = pace.forecast else {
            return XCTFail("expected a run-out, got \(pace.forecast)", file: file, line: line)
        }
        XCTAssertEqual(at.timeIntervalSince(now), seconds, accuracy: 1e-6, file: file, line: line)
    }

    func testRunsOutBeforeResetAtTheAverageBurn() throws {
        // Weekly, half gone (302,400 s), 80% used: 80 points took 302,400 s, so the last 20
        // take 75,600 s (21 h), well inside the 302,400 s left.
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 80, resetIn: week / 2), now: now))
        try assertRunsOut(pace, after: 75_600)
    }

    func testLastsToResetWhenTheBurnLeavesRoom() throws {
        // Half gone, 40% used: the remaining 60 points would take 453,600 s; only 302,400 s are left.
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 40, resetIn: week / 2), now: now))
        XCTAssertEqual(pace.forecast, .lastsToReset)
    }

    func testEmptyingExactlyAtTheResetLastsToReset() throws {
        // Half gone, half used: it empties at the reset instant, which still counts as lasting.
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 50, resetIn: week / 2), now: now))
        XCTAssertEqual(pace.forecast, .lastsToReset)
    }

    func testNothingUsedLastsToReset() throws {
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 0, resetIn: week / 2), now: now))
        XCTAssertEqual(pace.forecast, .lastsToReset)
    }

    func testFullyUsedIsExhaustedEvenEarlyInTheWindow() throws {
        let pace = try XCTUnwrap(QuotaPace(window: window(used: 100, resetIn: week - 60), now: now))
        XCTAssertEqual(pace.forecast, .exhausted)
    }

    func testNoForecastInTheFirstFivePercentOfTheWindow() throws {
        // 4% of a week gone (24,192 s) with 3% used would project a run-out in under a day.
        let early = try XCTUnwrap(QuotaPace(window: window(used: 3, resetIn: week * 0.96), now: now))
        XCTAssertEqual(early.forecast, .tooEarly)
        // At 6% gone (36,288 s), 3% used: the other 97 points take 1,173,312 s, past the reset.
        let later = try XCTUnwrap(QuotaPace(window: window(used: 3, resetIn: week * 0.94), now: now))
        XCTAssertEqual(later.forecast, .lastsToReset)
    }

    func testSessionWindowRunOut() throws {
        // 5 h session resetting in 3 h (2 h = 7,200 s gone), 60% used: 40 points take 4,800 s.
        let pace = try XCTUnwrap(QuotaPace(window: window(.session, used: 60, resetIn: 3 * 3_600), now: now))
        try assertRunsOut(pace, after: 4_800)
    }
}
