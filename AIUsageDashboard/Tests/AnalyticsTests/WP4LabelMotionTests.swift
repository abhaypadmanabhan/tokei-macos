import XCTest
@testable import AIUsageDashboardCore

/// WP-4 label and motion contracts (t01 D6/D8/D12/D13, t02 F6).
/// Fixture values are the research probes, not live logs.
@MainActor
final class WP4LabelMotionTests: XCTestCase {
    private let hiddenClaudeKey = "provider_hidden_claude_code"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: hiddenClaudeKey)
        super.tearDown()
    }

    /// D6: "This week" is a rolling seven days, not a calendar week.
    func testD6_weekLabelIsLast7DaysNotThisWeek() {
        XCTAssertEqual(UsageAnalytics.rollingSevenDayLabel, "Last 7 days")
        XCTAssertFalse(UsageAnalytics.rollingSevenDayLabel.localizedCaseInsensitiveContains("this week"))
        XCTAssertEqual(
            UsageAnalytics.dailyHistoryTitle(for: .sevenDay),
            "Daily history · last 7 days"
        )
        XCTAssertEqual(
            UsageAnalytics.dailyHistoryTitle(for: .ninetyDay),
            "Daily history · last 90 days"
        )
        XCTAssertFalse(UsageAnalytics.dailyHistoryTitle(for: .thirtyDay).contains("30d"))
    }

    /// D8, superseded by WP-3 (2026-10-28 Bible §3 AC3): the quota hero and the menu-bar
    /// "Tightest quota" read one definition. With accounts at 80% and 20%, both say 80%
    /// and name the busy account; the old best-account (20%) hero is gone.
    func testD8_eightyTwentyHeroAndMenuBothNameTheTightestAccount() {
        let vm = DashboardViewModel()
        vm.snapshots = [claudeEightyTwenty()]

        XCTAssertEqual(vm.tightestAccountPressure?.usedPercent, 80)
        XCTAssertEqual(vm.tightestAccountPressure?.accountLabel, "busy")
        XCTAssertEqual(vm.tightestAccountPressure?.providerName, "Claude Code")
        XCTAssertEqual(vm.tightestAccountPressure?.namesAccount, true)
    }

    /// D8: an extra Codex 50 must not hide the 80.
    func testD8_codexFiftyDoesNotHideTightest() {
        let vm = DashboardViewModel()
        vm.snapshots = [
            claudeEightyTwenty(),
            provider(.codex, name: "Codex", today: 40, windowUsed: 50),
        ]

        XCTAssertEqual(vm.tightestAccountPressure?.usedPercent, 80)
        XCTAssertEqual(vm.tightestAccountPressure?.providerID, .claudeCode)
    }

    /// D12: today 10, the 30 full days to yesterday 990, the 30 before them 100: the delta is
    /// +890% of the complete-day totals (WP-3 AC2, like for like), not growth of today's 10.
    func testD12_deltaIsNotGrowthOfTodayHeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 16))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        // First day of the previous 30 complete days (07-18), so that period counts as recorded
        // (a history starting later makes no claim); outside the ranged 30 days.
        let previousStart = calendar.date(byAdding: .day, value: -60, to: today)!
        let vm = DashboardViewModel(calendar: calendar, now: { today })
        vm.range = .thirtyDay
        vm.snapshots = [
            ProviderSnapshot(
                providerID: .claudeCode,
                displayName: "Claude Code",
                authStatus: .authenticated,
                todayUsage: TokenUsage(inputTokens: 10, confidence: .exact),
                weekUsage: TokenUsage(inputTokens: 1000, confidence: .exact),
                dailyTotals: [
                    today: 10,
                    yesterday: 990,
                    previousStart: 100,
                ]
            ),
        ]

        XCTAssertEqual(vm.overviewRangedTotal, 1000)
        XCTAssertEqual(vm.overviewDelta, 890)
        XCTAssertEqual(vm.snapshots[0].todayUsage.totalTokens, 10)
        XCTAssertNotEqual(vm.overviewRangedTotal, vm.snapshots[0].todayUsage.totalTokens)
    }

    /// D13: hidden Claude 100 / 80% must not inflate the menu total or the pressure figure.
    func testD13_hiddenProviderMenuTotalMatchesVisibleOverview() {
        UserDefaults.standard.set(true, forKey: hiddenClaudeKey)
        let vm = DashboardViewModel()
        vm.snapshots = [
            provider(.claudeCode, name: "Claude Code", today: 100, windowUsed: 80),
            provider(.codex, name: "Codex", today: 20, windowUsed: 10),
        ]

        XCTAssertEqual(vm.menuBarTodayTotal, 20)
        XCTAssertEqual(vm.tightestAccountPressure?.usedPercent, 10)
        XCTAssertEqual(vm.tightestAccountPressure?.providerID, .codex)
    }

    /// F6: 60 hidden ticks apply nothing; a visible tick returns the same date.
    func testF6_hiddenStatusStripDoesNotMutate() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in 0..<60 {
            let date = start.addingTimeInterval(TimeInterval(offset))
            XCTAssertNil(StatusStripTickGate.appliedDate(date, dashboardVisible: false))
        }
        let visible = start.addingTimeInterval(60)
        XCTAssertEqual(StatusStripTickGate.appliedDate(visible, dashboardVisible: true), visible)
    }

    /// D9: the view-model calendar hook adopts the new zone. Parser rebuild is WP-1.
    func testD9_calendarChangeHookUpdatesViewModelCalendar() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let vm = DashboardViewModel(calendar: losAngeles)
        XCTAssertEqual(vm.analyticsTimeZone.identifier, "America/Los_Angeles")

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        vm.noteEffectiveTimezoneChange(tokyo)
        XCTAssertEqual(vm.analyticsTimeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(vm.calendarGeneration, 1)
    }

    /// Live-number motion stays inside 200–300ms and snaps when Reduce Motion is on.
    func testLiveNumbersRollAtMost300msAndSnapWhenReduced() {
        XCTAssertGreaterThanOrEqual(PadzyMotion.numberRollDuration, 0.2)
        XCTAssertLessThanOrEqual(PadzyMotion.numberRollDuration, 0.3)
        XCTAssertNil(LiveNumberMotion.animation(reduceMotion: true))
        XCTAssertNotNil(LiveNumberMotion.animation(reduceMotion: false))
    }

    // MARK: - Fixtures

    private func claudeEightyTwenty() -> ProviderSnapshot {
        let busy = ProviderAccountUsage(
            id: "busy",
            label: "busy",
            quotaWindows: [window(.claudeCode, used: 80)],
            todayUsage: TokenUsage(inputTokens: 80, confidence: .exact)
        )
        let best = ProviderAccountUsage(
            id: "best",
            label: "best",
            quotaWindows: [window(.claudeCode, used: 20)],
            todayUsage: TokenUsage(inputTokens: 20, confidence: .exact)
        )
        return ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            quotaWindows: [window(.claudeCode, used: 20)],
            todayUsage: TokenUsage(inputTokens: 100, confidence: .exact),
            weekUsage: TokenUsage(inputTokens: 100, confidence: .exact),
            accounts: [busy, best],
            headlineAccountID: "best"
        )
    }

    private func provider(
        _ id: ProviderID,
        name: String,
        today: Int,
        windowUsed: Double
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: name,
            authStatus: .authenticated,
            quotaWindows: [window(id, used: windowUsed)],
            todayUsage: TokenUsage(inputTokens: today, confidence: .exact),
            weekUsage: TokenUsage(inputTokens: today, confidence: .exact)
        )
    }

    private func window(_ id: ProviderID, used: Double) -> QuotaWindow {
        QuotaWindow(
            providerID: id,
            type: .weekly,
            used: used,
            limit: 100,
            confidence: .providerReported,
            source: "fixture"
        )
    }
}
