import XCTest
@testable import AIUsageDashboardCore

@MainActor
final class DashboardViewModelAnalyticsTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        today = day("2026-07-10")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "provider_hidden_codex")
        super.tearDown()
    }

    func testAnalyticsSurfaceDerivesRangedOverviewAndExcludesHiddenProviders() {
        UserDefaults.standard.set(true, forKey: "provider_hidden_codex")
        let vm = makeViewModel()
        vm.range = .sevenDay
        vm.snapshots = [
            snapshot(.claudeCode, dailyTotals: [
                day("2026-07-02"): 15,
                day("2026-07-09"): 20,
                day("2026-07-10"): 10
            ]),
            snapshot(.codex, dailyTotals: [
                day("2026-07-10"): 500
            ])
        ]

        XCTAssertEqual(vm.range, .sevenDay)
        XCTAssertEqual(vm.overviewTrend.map(\.tokens), [20, 10])
        XCTAssertEqual(vm.providerSplit.map(\.provider), [.claudeCode])
        XCTAssertEqual(vm.providerSplit.map(\.tokens), [30])
        XCTAssertEqual(vm.overviewDelta, 100)
        XCTAssertEqual(vm.streak.current, 2)
        XCTAssertEqual(vm.streak.longest, 2)
        XCTAssertEqual(vm.bestDay?.tokens, 20)
        XCTAssertEqual(vm.bestDay?.date, day("2026-07-09"))
        XCTAssertEqual(vm.leastActiveDay?.tokens, 10)
        XCTAssertEqual(vm.dailyAverage, 15)
    }

    func testProviderDetailAnalyticsReturnRealDataAndNilHonestly() {
        let hour = date("2026-07-10", hour: 9)
        let vm = makeViewModel()
        vm.snapshots = [
            snapshot(.claudeCode, dailyTotals: [
                day("2026-07-02"): 15,
                day("2026-07-09"): 20,
                day("2026-07-10"): 10
            ], hourlyTotals: [
                hour: 30
            ]),
            ProviderSnapshot(
                providerID: .antigravity,
                displayName: "Antigravity",
                authStatus: .authenticated,
                todayUsage: .unavailable,
                weekUsage: .unavailable
            )
        ]

        XCTAssertEqual(vm.trend(for: .claudeCode).map(\.tokens), [20, 10])

        let week = vm.thisWeek(for: .claudeCode)
        XCTAssertEqual(week?.peakDayTokens, 20)
        XCTAssertEqual(week?.dailyAverage, 15)
        XCTAssertEqual(week?.delta, 100)
        XCTAssertEqual(week?.peakDayWeekday, calendar.component(.weekday, from: day("2026-07-09")))

        let heatmap = vm.heatmap(for: .claudeCode)
        XCTAssertEqual(heatmap?.count, 7)
        XCTAssertEqual(heatmap?[calendar.component(.weekday, from: hour) - 1][9], 30)
        XCTAssertEqual(vm.peakHour(for: .claudeCode)?.hour, 9)
        XCTAssertEqual(vm.peakHour(for: .claudeCode)?.tokens, 30)

        XCTAssertNil(vm.thisWeek(for: .antigravity))
        XCTAssertNil(vm.heatmap(for: .antigravity))
        XCTAssertNil(vm.peakHour(for: .antigravity))
    }

    private func snapshot(
        _ providerID: ProviderID,
        dailyTotals: [Date: Int],
        hourlyTotals: [Date: Int]? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: dailyTotals[today] ?? 0, confidence: .localParsed),
            weekUsage: TokenUsage(inputTokens: dailyTotals.values.reduce(0, +), confidence: .localParsed),
            lifetimeUsage: TokenUsage(inputTokens: dailyTotals.values.reduce(0, +), confidence: .localParsed),
            dailyTotals: dailyTotals,
            hourlyTotals: hourlyTotals
        )
    }

    private func makeViewModel() -> DashboardViewModel {
        let fixedToday = today!
        return DashboardViewModel(calendar: calendar, now: { fixedToday })
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
