import XCTest
@testable import AIUsageDashboardCore

/// The forecast words on every gauge. Expected strings are written by hand from the
/// fixed clock below, never produced by the formatter under test.
final class PaceCopyForecastTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let twelveHour = Locale(identifier: "en_US")
    private let twentyFourHour = Locale(identifier: "en_GB")
    /// Wednesday 2026-10-28 09:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_178_000)

    private func at(hour: Int, minute: Int, dayOffset: Int = 0) -> Date {
        now.addingTimeInterval(TimeInterval(dayOffset * 86_400 + (hour - 9) * 3_600 + minute * 60))
    }

    /// macOS formats a 12-hour time with a narrow no-break space before the day period.
    private func ampm(_ clock: String, _ period: String) -> String { "\(clock)\u{202F}\(period)" }

    func testRunsOutSameDayNamesTimeAndLeadIn12Hour() {
        let text = PaceCopy.forecast(
            .runsOut(at: at(hour: 15, minute: 40)),
            resetAt: at(hour: 21, minute: 40),
            now: now, locale: twelveHour, timeZone: utc
        )
        XCTAssertEqual(text, "Runs out ~\(ampm("3:40", "PM")), 6 h before reset")
    }

    func testRunsOutUses24HourClockWhereTheLocaleDoes() {
        let text = PaceCopy.forecast(
            .runsOut(at: at(hour: 15, minute: 40)),
            resetAt: at(hour: 21, minute: 40),
            now: now, locale: twentyFourHour, timeZone: utc
        )
        XCTAssertEqual(text, "Runs out ~15:40, 6 h before reset")
    }

    func testRunsOutRoundsTheProjectionToFiveMinutes() {
        // 15:38:40 rounds to 15:40, not 15:38; the lead counts from the shown 15:40.
        let text = PaceCopy.forecast(
            .runsOut(at: at(hour: 15, minute: 38).addingTimeInterval(40)),
            resetAt: at(hour: 16, minute: 20),
            now: now, locale: twentyFourHour, timeZone: utc
        )
        XCTAssertEqual(text, "Runs out ~15:40, 40 min before reset")
    }

    func testRunsOutOnAnotherDayCarriesTheWeekday() {
        // Thursday 29 Oct 02:15, reset Saturday 31 Oct 02:15 = 48 h later.
        let text = PaceCopy.forecast(
            .runsOut(at: at(hour: 2, minute: 15, dayOffset: 1)),
            resetAt: at(hour: 2, minute: 15, dayOffset: 3),
            now: now, locale: twentyFourHour, timeZone: utc
        )
        XCTAssertEqual(text, "Runs out ~Thu 02:15, 2 d before reset")
    }

    func testRunsOutWithoutResetNamesOnlyTheTime() {
        let text = PaceCopy.forecast(
            .runsOut(at: at(hour: 15, minute: 40)), resetAt: nil,
            now: now, locale: twentyFourHour, timeZone: utc
        )
        XCTAssertEqual(text, "Runs out ~15:40")
    }

    func testLastsToReset() {
        let ninePM = at(hour: 21, minute: 0)
        let text = PaceCopy.forecast(.lastsToReset, resetAt: ninePM, now: now, locale: twelveHour, timeZone: utc)
        XCTAssertEqual(text, "Lasts to reset")
    }

    func testExhaustedSaysWhenItRefills() {
        let ninePM = at(hour: 21, minute: 0)
        let twelve = PaceCopy.forecast(.exhausted, resetAt: ninePM, now: now, locale: twelveHour, timeZone: utc)
        XCTAssertEqual(twelve, "Out until \(ampm("9:00", "PM"))")
        let twentyFour = PaceCopy.forecast(.exhausted, resetAt: ninePM, now: now, locale: twentyFourHour, timeZone: utc)
        XCTAssertEqual(twentyFour, "Out until 21:00")
        let noReset = PaceCopy.forecast(.exhausted, resetAt: nil, now: now, locale: twentyFourHour, timeZone: utc)
        XCTAssertEqual(noReset, "Out until reset")
    }

    func testTooEarlySaysNothing() {
        let text = PaceCopy.forecast(
            .tooEarly, resetAt: at(hour: 21, minute: 0), now: now, locale: twelveHour, timeZone: utc
        )
        XCTAssertNil(text)
    }

    func testOnlyRunsOutAndExhaustedAreUrgent() {
        XCTAssertTrue(PaceCopy.isUrgent(.runsOut(at: now)))
        XCTAssertTrue(PaceCopy.isUrgent(.exhausted))
        XCTAssertFalse(PaceCopy.isUrgent(.lastsToReset))
        XCTAssertFalse(PaceCopy.isUrgent(.tooEarly))
    }

    /// End to end from a real window: weekly, 3.5 days in, 80% used. At 80% per 3.5 days
    /// the last 20% lasts 0.875 days (21 h), so it runs out at 06:00 Thursday, 2.625 days
    /// (63 h, shown as 3 d) before the reset at 21:00 Saturday.
    func testForecastFromAWindowReadsOffQuotaPace() throws {
        let reset = now.addingTimeInterval(3.5 * 86_400)
        let window = QuotaWindow(
            providerID: .claudeCode, type: .weekly, used: 80, limit: 100,
            resetAt: reset, confidence: .providerReported, source: "test"
        )
        let pace = try XCTUnwrap(QuotaPace(window: window, now: now))
        XCTAssertEqual(
            PaceCopy.forecast(pace.forecast, resetAt: reset, now: now, locale: twentyFourHour, timeZone: utc),
            "Runs out ~Thu 06:00, 3 d before reset"
        )
    }
}
