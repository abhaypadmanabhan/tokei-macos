import XCTest
@testable import AIUsageDashboardCore

final class UsageAnalyticsTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        now = date("2026-07-10", hour: 12)
    }

    func testCurrentStreakCountsConsecutiveActiveDaysThroughToday() {
        let totals = [
            day("2026-07-08"): 30,
            day("2026-07-09"): 20,
            day("2026-07-10"): 10,
            day("2026-07-01"): 5,
            day("2026-07-02"): 6
        ]

        let streak = UsageAnalytics.streak(dailyTotals: totals, calendar: calendar, now: now)

        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.longest, 3)
    }

    func testCurrentStreakIsZeroWhenTodayIsInactive() {
        let totals = [
            day("2026-07-08"): 30,
            day("2026-07-09"): 20,
            day("2026-07-10"): 0
        ]

        let streak = UsageAnalytics.streak(dailyTotals: totals, calendar: calendar, now: now)

        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.longest, 2)
    }

    func testStreakHandlesAllZeroAndSingleDay() {
        XCTAssertEqual(
            UsageAnalytics.streak(
                dailyTotals: [day("2026-07-10"): 0, day("2026-07-09"): 0],
                calendar: calendar,
                now: now
            ).longest,
            0
        )

        let single = UsageAnalytics.streak(
            dailyTotals: [day("2026-07-10"): 42],
            calendar: calendar,
            now: now
        )
        XCTAssertEqual(single.current, 1)
        XCTAssertEqual(single.longest, 1)
    }

    func testBestAndLeastActiveDayUseEarliestTieAndEmptyNil() {
        let totals = [
            day("2026-07-01"): 10,
            day("2026-07-02"): 50,
            day("2026-07-03"): 50,
            day("2026-07-04"): 5,
            day("2026-07-05"): 5
        ]

        let best = UsageAnalytics.bestDay(dailyTotals: totals)
        let least = UsageAnalytics.leastActiveDay(dailyTotals: totals)

        XCTAssertEqual(best?.0, day("2026-07-02"))
        XCTAssertEqual(best?.1, 50)
        XCTAssertEqual(least?.0, day("2026-07-04"))
        XCTAssertEqual(least?.1, 5)
        XCTAssertNil(UsageAnalytics.bestDay(dailyTotals: [:]))
        XCTAssertNil(UsageAnalytics.leastActiveDay(dailyTotals: [:]))
    }

    func testDeltaHandlesZeroPreviousNegativeAndExact() {
        XCTAssertNil(UsageAnalytics.delta(current: 10, previous: 0))
        XCTAssertNil(UsageAnalytics.delta(current: 10, previous: nil))
        XCTAssertEqual(UsageAnalytics.delta(current: 50, previous: 100), -50)
        XCTAssertEqual(UsageAnalytics.delta(current: 125, previous: 100), 25)
        XCTAssertEqual(UsageAnalytics.delta(current: 100, previous: 100), 0)
    }

    func testDailyAverageUsesWindowedPresentDays() {
        let totals = [
            day("2026-07-08"): 30,
            day("2026-07-09"): 20,
            day("2026-07-10"): 10,
            day("2026-07-01"): 999
        ]

        XCTAssertEqual(
            UsageAnalytics.dailyAverage(dailyTotals: totals, window: 3, calendar: calendar, now: now),
            20
        )
        XCTAssertNil(UsageAnalytics.dailyAverage(dailyTotals: [:], window: 7, calendar: calendar, now: now))
    }

    func testPeakDayAggregatesByWeekday() {
        let mondayA = day("2026-07-06")
        let mondayB = day("2026-07-13")
        let tuesday = day("2026-07-07")
        let totals = [
            mondayA: 40,
            mondayB: 40,
            tuesday: 70
        ]

        let peak = UsageAnalytics.peakDay(dailyTotals: totals, calendar: calendar)

        XCTAssertEqual(peak?.weekday, calendar.component(.weekday, from: mondayA))
        XCTAssertEqual(peak?.tokens, 80)
    }

    func testProviderSplitExcludesHiddenAndUsesRequestedRange() {
        let snapshots = [
            snapshot(.claudeCode, dailyTotals: [
                day("2026-07-09"): 20,
                day("2026-07-10"): 10
            ]),
            snapshot(.codex, dailyTotals: [
                day("2026-07-10"): 999
            ]),
            snapshot(.cline, dailyTotals: [
                day("2026-07-10"): 0
            ])
        ]

        let split = UsageAnalytics.providerSplit(
            snapshots: snapshots,
            range: .sevenDay,
            calendar: calendar,
            now: now,
            hiddenProviders: [.codex]
        )

        XCTAssertEqual(split.map(\.0), [.claudeCode])
        XCTAssertEqual(split.map(\.1), [30])
    }

    func testRollingSumsVisibleWindows() {
        let snapshots = [
            snapshot(.claudeCode, dailyTotals: [
                day("2026-07-10"): 10,
                day("2026-07-04"): 20,
                day("2026-07-03"): 30,
                day("2026-06-20"): 40
            ], lifetimeTokens: 100),
            snapshot(.codex, dailyTotals: [
                day("2026-07-10"): 999
            ], lifetimeTokens: 999)
        ]

        let rolling = UsageAnalytics.rolling(
            snapshots: snapshots,
            calendar: calendar,
            now: now,
            hiddenProviders: [.codex]
        )

        XCTAssertEqual(rolling.sevenDay, 30)
        XCTAssertEqual(rolling.thirtyDay, 100)
        XCTAssertEqual(rolling.lifetime, 100)
    }

    func testHeatmapMatrixUsesFixedCalendarWeekdayHour() {
        let monday = date("2026-07-06", hour: 9)
        let nextMonday = date("2026-07-13", hour: 9)
        let friday = date("2026-07-10", hour: 17)
        let weekdayIndex = calendar.component(.weekday, from: monday) - 1
        let fridayIndex = calendar.component(.weekday, from: friday) - 1

        let matrix = UsageAnalytics.heatmapMatrix(
            hourlyTotals: [
                monday: 10,
                nextMonday: 20,
                friday: 5
            ],
            calendar: calendar
        )

        XCTAssertEqual(matrix.count, 7)
        XCTAssertTrue(matrix.allSatisfy { $0.count == 24 })
        XCTAssertEqual(matrix[weekdayIndex][9], 30)
        XCTAssertEqual(matrix[fridayIndex][17], 5)
        XCTAssertNil(matrix[weekdayIndex][8])
    }

    func testHeatmapMatrixRestrictsFoldToRangeWindow() {
        // now = 2026-07-10 12:00 (a Friday). Slots span 90 days back at hour 9.
        let today = date("2026-07-10", hour: 9)          // 0 days back — in every range
        let eightDaysAgo = date("2026-07-02", hour: 9)    // out of 7-day, in 30/90
        let fortyDaysAgo = date("2026-05-31", hour: 9)    // out of 7/30-day, in 90
        let hourly = [today: 10, eightDaysAgo: 20, fortyDaysAgo: 40]

        let weekdayToday = calendar.component(.weekday, from: today) - 1
        let weekday8 = calendar.component(.weekday, from: eightDaysAgo) - 1
        let weekday40 = calendar.component(.weekday, from: fortyDaysAgo) - 1

        let seven = UsageAnalytics.heatmapMatrix(hourlyTotals: hourly, range: .sevenDay, calendar: calendar, now: now)
        let thirty = UsageAnalytics.heatmapMatrix(hourlyTotals: hourly, range: .thirtyDay, calendar: calendar, now: now)
        let ninety = UsageAnalytics.heatmapMatrix(hourlyTotals: hourly, range: .ninetyDay, calendar: calendar, now: now)

        // 7-day: only today's slot survives; the older slots are excluded (nil).
        XCTAssertEqual(seven[weekdayToday][9], 10)
        XCTAssertNil(seven[weekday8][9])
        XCTAssertNil(seven[weekday40][9])

        // 30-day: today + 8-days-ago; 40-days-ago still excluded.
        XCTAssertEqual(thirty[weekdayToday][9], 10)
        XCTAssertEqual(thirty[weekday8][9], 20)
        XCTAssertNil(thirty[weekday40][9])

        // 90-day: all three fold in.
        XCTAssertEqual(ninety[weekday40][9], 40)

        // The three ranges produce genuinely different grids.
        XCTAssertNotEqual(seven, thirty)
        XCTAssertNotEqual(thirty, ninety)

        // Default range keeps the all-time fold (existing callers unchanged).
        let all = UsageAnalytics.heatmapMatrix(hourlyTotals: hourly, calendar: calendar, now: now)
        XCTAssertEqual(all[weekday40][9], 40)
    }

    func testPeakHourAggregatesAndUsesEarliestTie() {
        let peak = UsageAnalytics.peakHour(
            hourlyTotals: [
                date("2026-07-06", hour: 9): 10,
                date("2026-07-07", hour: 9): 20,
                date("2026-07-08", hour: 10): 30
            ],
            calendar: calendar
        )

        XCTAssertEqual(peak?.hour, 9)
        XCTAssertEqual(peak?.tokens, 30)
        XCTAssertNil(UsageAnalytics.peakHour(hourlyTotals: [:], calendar: calendar))
    }

    private func snapshot(
        _ providerID: ProviderID,
        dailyTotals: [Date: Int],
        lifetimeTokens: Int? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: dailyTotals[calendar.startOfDay(for: now)] ?? 0, confidence: .localParsed),
            weekUsage: TokenUsage(inputTokens: dailyTotals.values.reduce(0, +), confidence: .localParsed),
            lifetimeUsage: TokenUsage(inputTokens: lifetimeTokens ?? dailyTotals.values.reduce(0, +), confidence: .localParsed),
            dailyTotals: dailyTotals
        )
    }

    private func day(_ dayString: String) -> Date {
        date(dayString, hour: 0)
    }

    private func date(_ dayString: String, hour: Int) -> Date {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: hour
        ))!
    }
}
