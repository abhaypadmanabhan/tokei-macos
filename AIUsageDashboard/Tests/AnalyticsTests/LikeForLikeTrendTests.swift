import XCTest
@testable import AIUsageDashboardCore

/// WP-3 AC2: Overview's "vs prev N days" compares like for like, and the trend never draws
/// a line across a day that had no tokens.
@MainActor
final class LikeForLikeTrendTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-28 15:00 UTC: today is a part-day.
    private lazy var now = calendar.date(
        from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 10, day: 28, hour: 15)
    )!

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    private func model(_ dailyTotals: [Date: Int]) -> DashboardViewModel {
        let fixed = now
        let model = DashboardViewModel(calendar: calendar, now: { fixed })
        model.range = .sevenDay
        model.snapshots = [
            ProviderSnapshot(
                providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                todayUsage: TokenUsage(inputTokens: dailyTotals[day(0)] ?? 0, confidence: .exact),
                weekUsage: TokenUsage(inputTokens: 0, confidence: .exact),
                dailyTotals: dailyTotals
            )
        ]
        return model
    }

    /// A steady 100 a day for two weeks, and 10 so far today. Counting today's part-day
    /// against a full day read as -12.9% (610 vs 700); like for like it is flat.
    func testSteadyUsageReadsFlatWhileTodayIsPartial() throws {
        var totals: [Date: Int] = [day(0): 10]
        for offset in 1...14 { totals[day(-offset)] = 100 }
        let model = model(totals)
        XCTAssertEqual(try XCTUnwrap(model.overviewDelta), 0, accuracy: 1e-9)
    }

    /// 7 full days at 150 against 7 at 100 is +50%, whatever today holds so far.
    func testDeltaUsesOnlyCompleteDays() throws {
        var totals: [Date: Int] = [day(0): 1_000_000]
        for offset in 1...7 { totals[day(-offset)] = 150 }
        for offset in 8...14 { totals[day(-offset)] = 100 }
        XCTAssertEqual(try XCTUnwrap(model(totals).overviewDelta), 50, accuracy: 1e-9)
    }

    /// Claude Code deletes old session logs, so an earlier period can be only partly recorded:
    /// the 30-day view read "▲ 2175.9%" on real logs (capture, 2026-10-29). 150 a day for the
    /// last 7 full days against an earlier week recorded only from 3 days in (8, 9, 10 days ago
    /// at 100) is not like for like: no change is claimed. Record its first day too and it is.
    func testPartlyRecordedEarlierPeriodMeansNoDelta() throws {
        var totals: [Date: Int] = [day(0): 10]
        for offset in 1...7 { totals[day(-offset)] = 150 }
        for offset in 8...10 { totals[day(-offset)] = 100 }
        XCTAssertNil(model(totals).overviewDelta)

        totals[day(-14)] = 400 // the earlier week: 300 + 400 = 700 against 1,050 → +50%
        XCTAssertEqual(try XCTUnwrap(model(totals).overviewDelta), 50, accuracy: 1e-9)
    }

    func testNoEarlierPeriodMeansNoDelta() {
        XCTAssertNil(model([day(0): 10, day(-1): 20]).overviewDelta)
    }

    /// The day between 50 and 30 had no tokens: it is drawn as 0, not bridged.
    func testInteriorGapIsAZeroDay() {
        let model = model([day(-3): 50, day(-1): 30, day(0): 10])
        XCTAssertEqual(model.overviewTrend.map(\.tokens), [50, 0, 30, 10])
        XCTAssertEqual(model.overviewTrend.map(\.date), [day(-3), day(-2), day(-1), day(0)])
    }

    /// Days before the first active day are "no data yet", not zeros.
    func testLeadingDaysWithoutDataStayOut() {
        XCTAssertEqual(model([day(-1): 30, day(0): 10]).overviewTrend.map(\.tokens), [30, 10])
    }
}
