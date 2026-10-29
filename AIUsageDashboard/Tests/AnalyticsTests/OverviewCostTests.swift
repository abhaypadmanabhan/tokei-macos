import XCTest
@testable import AIUsageDashboardCore

/// WP-3 addendum 2: Overview › Cost. Dollars are worked by hand from two made-up rates:
/// alpha $3/M input, $15/M output; beta $1/M input, $5/M output; gamma has no rate.
final class OverviewCostTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let pricing = PricingEngine(table: PricingTable(rates: [
        "alpha": PricingRate(inputPerMillion: 3, cachedInputPerMillion: 0.3, outputPerMillion: 15),
        "beta": PricingRate(inputPerMillion: 1, cachedInputPerMillion: 0.1, outputPerMillion: 5)
    ]))

    /// 2026-10-28 15:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 10, day: 28, hour: 15))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    private func input(_ tokens: Int, output: Int? = nil) -> TokenUsage {
        TokenUsage(inputTokens: tokens, outputTokens: output, confidence: .localParsed)
    }

    private func snapshot(
        _ id: ProviderID,
        models: [Date: [String: TokenUsage]]? = nil,
        totals: [Date: Int],
        cost: CostUsage? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id, displayName: id.rawValue, authStatus: .authenticated,
            todayUsage: input(totals[day(0)] ?? 0), weekUsage: input(0), costUsage: cost,
            dailyTotals: totals, dailyModelUsage: models
        )
    }

    private func summary(_ snapshots: [ProviderSnapshot], range: UsageRange = .sevenDay) -> CostSummary {
        UsageAnalytics.costSummary(snapshots: snapshots, range: range, pricing: pricing, calendar: calendar, now: now)
    }

    /// alpha 1M in + 100k out = $3.00 + $1.50; beta 2M in = $2.00. Today = $6.50, nothing left out.
    func testTwoModelDay() throws {
        let claude = snapshot(.claudeCode, models: [
            day(0): ["alpha": input(1_000_000, output: 100_000), "beta": input(2_000_000)]
        ], totals: [day(0): 3_100_000])
        let cost = summary([claude])
        XCTAssertEqual(try XCTUnwrap(cost.todayUSD), 6.50, accuracy: 0.000_001)
        XCTAssertEqual(cost.todayExcludedShare, 0)
        XCTAssertEqual(cost.providers[.claudeCode], .priced(usd: 6.50, partial: false))
    }

    /// Claude: alpha $4.50 (1.1M tokens) + gamma 500k with no rate; Cursor: 400k tokens and no
    /// per-model data. Left out: (500k + 400k) / (1.1M + 500k + 400k) = 0.9M / 2.0M = 45%.
    func testUnpricedTokensAreLeftOutAndCounted() throws {
        let claude = snapshot(.claudeCode, models: [
            day(0): ["alpha": input(1_000_000, output: 100_000), "gamma": input(500_000)]
        ], totals: [day(0): 1_600_000])
        let cursor = snapshot(.cursor, totals: [day(0): 400_000])
        let cost = summary([claude, cursor])
        XCTAssertEqual(try XCTUnwrap(cost.todayUSD), 4.50, accuracy: 0.000_001)
        XCTAssertEqual(cost.todayExcludedShare, 0.45, accuracy: 0.000_001)
        XCTAssertEqual(cost.providers[.claudeCode], .priced(usd: 4.50, partial: true))
        XCTAssertEqual(cost.providers[.cursor], .noPriceData)
    }

    /// Per-model data starts 3 days ago (alpha 1M = $3.00) and today has beta 1M = $1.00; 5 days
    /// ago had 2M tokens with no per-model data. The chart starts at the first priced day: no
    /// $0 point for the gap, the total is $4.00 and says the range reaches before pricing.
    func testDaysBeforePerModelDataAreAGapNotZero() throws {
        let claude = snapshot(.claudeCode, models: [
            day(-3): ["alpha": input(1_000_000)], day(0): ["beta": input(1_000_000)]
        ], totals: [day(-5): 2_000_000, day(-3): 1_000_000, day(0): 1_000_000])
        let cost = summary([claude])
        XCTAssertEqual(cost.pricedFrom, day(-3))
        XCTAssertEqual(cost.trend.map(\.date), [day(-3), day(-2), day(-1), day(0)])
        XCTAssertEqual(cost.trend.map(\.usd), [3, 0, 0, 1])
        XCTAssertEqual(try XCTUnwrap(cost.rangeUSD), 4.00, accuracy: 0.000_001)
        XCTAssertTrue(cost.rangeStartsBeforePricing)
        XCTAssertNil(cost.delta, "the earlier 7 days are not priced, so there is nothing to compare")
        XCTAssertEqual(cost.providers[.claudeCode], .priced(usd: 4.00, partial: true))
    }

    /// $1 a day for the 7 days before last week, $2 a day last week, $9 so far today: complete
    /// days only, $14 against $7 is +100%. Drop the oldest day and the earlier period is no
    /// longer wholly priced: no change is claimed.
    func testChangeIsLikeForLikeAndNeedsBothPeriodsPriced() {
        var models: [Date: [String: TokenUsage]] = [day(0): ["beta": input(9_000_000)]]
        for offset in -14 ... -8 { models[day(offset)] = ["beta": input(1_000_000)] }
        for offset in -7 ... -1 { models[day(offset)] = ["beta": input(2_000_000)] }
        let totals = models.mapValues { $0.values.compactMap(\.totalTokens).reduce(0, +) }
        let cost = summary([snapshot(.claudeCode, models: models, totals: totals)])
        XCTAssertEqual(cost.delta ?? .nan, 100, accuracy: 0.000_001)
        XCTAssertEqual(cost.rangeUSD ?? .nan, 21, accuracy: 0.000_001) // 6 days × $2 + today's $9
        XCTAssertFalse(cost.rangeStartsBeforePricing)

        models[day(-14)] = nil
        XCTAssertNil(summary([snapshot(.claudeCode, models: models, totals: totals)]).delta)
    }

    /// Cline's logs carry each request's API cost: shown as reported, all time, not added to the
    /// priced total. Cursor's cost is the billed amount, not an API estimate: no price data.
    func testReportedCostIsLabelledAndBilledCostIsNotUsed() {
        let logged = CostUsage(amount: 12.34, currency: "USD", confidence: .localParsed)
        let billed = CostUsage(amount: 5, currency: "USD", confidence: .providerReported)
        let cline = snapshot(.cline, totals: [day(0): 1_000], cost: logged)
        let cursor = snapshot(.cursor, totals: [day(0): 1_000], cost: billed)
        let cost = summary([cline, cursor])
        XCTAssertEqual(cost.providers[.cline], .reportedAllTime(usd: 12.34))
        XCTAssertEqual(cost.providers[.cursor], .noPriceData)
        XCTAssertNil(cost.todayUSD, "no per-model data anywhere: the headline is unknown, never $0")
        XCTAssertNil(cost.rangeUSD)
        XCTAssertEqual(cost.trend, [])
    }
}
