import XCTest
@testable import AIUsageDashboardCore

final class MaxxerValueEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_438_400)
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var planCosts: MaxxerPlanCostStore!

    override func setUp() {
        super.setUp()
        suiteName = "ai.padzy.tokei.tests.maxxer.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        planCosts = MaxxerPlanCostStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        planCosts = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testKnownPriceProvidersProducePerProviderAndTotalMultiples() throws {
        planCosts.setMonthlyUSD(1.50, for: ProviderID.claudeCode.rawValue)
        planCosts.setMonthlyUSD(2.50, for: ProviderID.codex.rawValue)

        let scorecard = MaxxerValueEngine.scorecard(
            snapshots: [
                snapshot(.claudeCode, monthUsage: tokens(input: 1_000_000)),
                snapshot(.codex, monthUsage: tokens(input: 2_000_000)),
            ],
            planCosts: planCosts,
            now: now
        )

        XCTAssertEqual(scorecard.providers.count, 2)
        let claude = try XCTUnwrap(scorecard.providers.first { $0.providerID == "claude_code" })
        XCTAssertEqual(try XCTUnwrap(claude.apiEquivalentUSD), 3.00, accuracy: 0.000_001)
        XCTAssertEqual(claude.planMonthlyUSD, 1.50)
        XCTAssertEqual(try XCTUnwrap(claude.valueMultiple), 2.00, accuracy: 0.000_001)
        XCTAssertEqual(claude.confidence, .estimated)
        XCTAssertFalse(claude.hasUnpricedTokens)

        let codex = try XCTUnwrap(scorecard.providers.first { $0.providerID == "codex" })
        XCTAssertEqual(try XCTUnwrap(codex.apiEquivalentUSD), 2.50, accuracy: 0.000_001)
        XCTAssertEqual(codex.planMonthlyUSD, 2.50)
        XCTAssertEqual(try XCTUnwrap(codex.valueMultiple), 1.00, accuracy: 0.000_001)
        XCTAssertEqual(codex.confidence, .estimated)
        XCTAssertFalse(codex.hasUnpricedTokens)

        XCTAssertEqual(try XCTUnwrap(scorecard.totalAPIEquivalentUSD), 5.50, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(scorecard.totalPlanUSD), 4.00, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(scorecard.totalValueMultiple), 1.375, accuracy: 0.000_001)
        XCTAssertEqual(scorecard.tier, .breakEven)
    }

    func testUnconfiguredPlanProducesNilMultipleAndNoTotalPlan() throws {
        let scorecard = MaxxerValueEngine.scorecard(
            snapshots: [snapshot(.claudeCode, monthUsage: tokens(input: 1_000_000))],
            planCosts: planCosts,
            now: now
        )

        let provider = try XCTUnwrap(scorecard.providers.first)
        XCTAssertEqual(try XCTUnwrap(provider.apiEquivalentUSD), 3.00, accuracy: 0.000_001)
        XCTAssertNil(provider.planMonthlyUSD)
        XCTAssertNil(provider.valueMultiple)
        XCTAssertEqual(try XCTUnwrap(scorecard.totalAPIEquivalentUSD), 3.00, accuracy: 0.000_001)
        XCTAssertNil(scorecard.totalPlanUSD)
        XCTAssertNil(scorecard.totalValueMultiple)
        XCTAssertNil(scorecard.tier)
    }

    func testAllUnavailableProvidersProduceEmptySafeScorecard() {
        planCosts.setMonthlyUSD(20, for: ProviderID.antigravity.rawValue)
        planCosts.setMonthlyUSD(30, for: ProviderID.gemini.rawValue)

        let scorecard = MaxxerValueEngine.scorecard(
            snapshots: [
                snapshot(.antigravity, monthUsage: nil),
                snapshot(.gemini, monthUsage: .unavailable),
            ],
            planCosts: planCosts,
            now: now
        )

        XCTAssertEqual(scorecard.providers.count, 2)
        XCTAssertTrue(scorecard.providers.allSatisfy { $0.apiEquivalentUSD == nil })
        XCTAssertTrue(scorecard.providers.allSatisfy { $0.valueMultiple == nil })
        XCTAssertTrue(scorecard.providers.allSatisfy { $0.confidence == .unavailable })
        XCTAssertNil(scorecard.totalAPIEquivalentUSD)
        XCTAssertNil(scorecard.totalPlanUSD)
        XCTAssertNil(scorecard.totalValueMultiple)
        XCTAssertNil(scorecard.tier)
    }

    func testUnknownProviderPricingMarksTokensUnpriced() throws {
        planCosts.setMonthlyUSD(20, for: ProviderID.cline.rawValue)

        let scorecard = MaxxerValueEngine.scorecard(
            snapshots: [snapshot(.cline, monthUsage: tokens(input: 1_000))],
            planCosts: planCosts,
            now: now
        )

        let provider = try XCTUnwrap(scorecard.providers.first)
        XCTAssertNil(provider.apiEquivalentUSD)
        XCTAssertNil(provider.valueMultiple)
        XCTAssertEqual(provider.confidence, .unavailable)
        XCTAssertTrue(provider.hasUnpricedTokens)
        XCTAssertNil(scorecard.totalAPIEquivalentUSD)
        XCTAssertNil(scorecard.totalPlanUSD)
    }

    func testScorecardUsesOnlyCurrentCalendarMonthWhenDailyTotalsAreAvailable() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let julyNow = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19))!
        let juneDay = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        let julyDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))!
        planCosts.setMonthlyUSD(1, for: ProviderID.claudeCode.rawValue)

        let scorecard = MaxxerValueEngine.scorecard(
            snapshots: [snapshot(
                .claudeCode,
                monthUsage: tokens(input: 1_000_000),
                dailyTotals: [juneDay: 750_000, julyDay: 250_000]
            )],
            planCosts: planCosts,
            now: julyNow
        )

        let provider = try XCTUnwrap(scorecard.providers.first)
        XCTAssertEqual(try XCTUnwrap(provider.apiEquivalentUSD), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(provider.valueMultiple), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(scorecard.tier, .warming)
    }

    func testTierBoundaries() throws {
        let cases: [(multiple: Double, expected: MaxxerTier)] = [
            (0.249, .idle),
            (0.25, .warming),
            (1.0, .breakEven),
            (2.0, .maxxing),
            (5.0, .goblinMode),
        ]

        for testCase in cases {
            planCosts.setMonthlyUSD(3.0 / testCase.multiple, for: ProviderID.claudeCode.rawValue)
            let scorecard = MaxxerValueEngine.scorecard(
                snapshots: [snapshot(.claudeCode, monthUsage: tokens(input: 1_000_000))],
                planCosts: planCosts,
                now: now
            )

            XCTAssertEqual(
                scorecard.tier,
                testCase.expected,
                "Expected \(testCase.multiple)x to map to \(testCase.expected)"
            )
        }
    }

    func testPlanCostStorePersistsPositiveValuesAndRemovesUnsetOrZero() {
        planCosts.setMonthlyUSD(42.50, for: "codex")
        XCTAssertEqual(defaults.double(forKey: "maxxer.planCost.codex"), 42.50)
        XCTAssertEqual(MaxxerPlanCostStore(defaults: defaults).monthlyUSD(for: "codex"), 42.50)

        planCosts.setMonthlyUSD(nil, for: "codex")
        XCTAssertNil(planCosts.monthlyUSD(for: "codex"))

        planCosts.setMonthlyUSD(0, for: "claude_code")
        XCTAssertNil(planCosts.monthlyUSD(for: "claude_code"))
        XCTAssertNil(defaults.object(forKey: "maxxer.planCost.claude_code"))
    }

    private func snapshot(
        _ providerID: ProviderID,
        monthUsage: TokenUsage?,
        dailyTotals: [Date: Int]? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: monthUsage,
            dailyTotals: dailyTotals
        )
    }

    private func tokens(input: Int = 0, output: Int = 0) -> TokenUsage {
        TokenUsage(
            inputTokens: input,
            outputTokens: output,
            confidence: .localParsed
        )
    }
}
