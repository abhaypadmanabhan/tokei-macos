import XCTest
@testable import AIUsageDashboardCore

final class PricingEngineTests: XCTestCase {
    func testCostPricesAnthropicCacheReadAtReducedRateAndOutputAtOutputRate() {
        let tokens = TokenUsage(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 200_000,
            cacheCreationTokens: 100_000,
            confidence: .localParsed
        )

        let amount = PricingEngine().cost(model: "claude-sonnet-4-6", tokens: tokens)

        XCTAssertNotNil(amount)
        // input: 1,000,000 * 3.00 = 3.00
        // cache creation: 100,000 * 3.75 = 0.375
        // cache read: 200,000 * 0.30 = 0.06
        // output: 500,000 * 15.00 = 7.50
        // total = 10.935
        XCTAssertEqual(amount!, 10.935, accuracy: 0.000_001)
    }

    func testCostAggregatesAllTokenFieldsAndReasoningAsOutput() {
        let tokens = TokenUsage(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 200_000,
            cacheCreationTokens: 100_000,
            reasoningTokens: 100_000,
            confidence: .localParsed
        )

        let amount = PricingEngine().cost(model: "gpt-4.1", tokens: tokens)

        XCTAssertNotNil(amount)
        // input: 1,000,000 * 2.00 = 2.00
        // cache creation: 100,000 * 2.00 = 0.20
        // cache read: 200,000 * 0.50 = 0.10
        // output+reasoning: 600,000 * 8.00 = 4.80
        // total = 7.10
        XCTAssertEqual(amount!, 7.10, accuracy: 0.000_001)
    }

    func testUnknownUnpricedSlugReturnsNil() {
        let tokens = TokenUsage(inputTokens: 100, outputTokens: 50, confidence: .localParsed)

        XCTAssertNil(PricingEngine().cost(model: "gpt-6-ultra", tokens: tokens))
        XCTAssertNil(PricingEngine().cost(model: "claude-unknown-9", tokens: tokens))
        XCTAssertNil(PricingEngine().cost(model: "some-random-local-model", tokens: tokens))
    }

    func testUnknownMinorIsUnpricedInsteadOfUsingFamilyRate() {
        let table = PricingSeed.defaultTable

        let base = table.resolveRate(for: "claude-opus-4")
        let newerMinor = table.resolveRate(for: "claude-opus-4-8")

        XCTAssertNotNil(base)
        XCTAssertNil(newerMinor)
    }

    func testFuzzyMatcherDoesNotResolveUnknownFamily() {
        let table = PricingSeed.defaultTable

        XCTAssertNil(table.resolveRate(for: "claude-lyric-1"))
        XCTAssertNil(table.resolveRate(for: "gpt-50"))
    }

    func testCurrentOfflineSeedPricesAllFourTokenCategories() throws {
        let expected: [(String, [Double])] = [
            ("claude-opus-5-5", [4, 0.2, 5, 20]),
            ("claude-opus-5", [5, 0.5, 6.25, 25]),
            ("claude-fable-5-1", [10, 0.25, 12.5, 50]),
            ("claude-sonnet-5-5", [2, 0.1, 2.5, 10]),
            ("claude-haiku-5-5", [0.1, 0.01, 0.125, 0.5]),
            ("gpt-6.1-sol", [2, 0.1, 2.5, 10]),
            ("gpt-6-astra", [10, 1, 12.5, 50]),
            ("gpt-6-sol", [2, 0.2, 2.5, 10])
        ]
        for (model, prices) in expected {
            let rate = try XCTUnwrap(PricingSeed.defaultTable.resolveRate(for: model), model)
            XCTAssertEqual(rate.inputPerMillion, prices[0])
            XCTAssertEqual(rate.cachedInputPerMillion, prices[1])
            XCTAssertEqual(rate.cacheCreationInputPerMillion, prices[2])
            XCTAssertEqual(rate.outputPerMillion, prices[3])
        }
    }

    func testExactRateWinsAndOnlyDocumentedSuffixesNormalize() throws {
        let family = PricingRate(inputPerMillion: 1, cachedInputPerMillion: 1, outputPerMillion: 1)
        let exact = PricingRate(inputPerMillion: 2, cachedInputPerMillion: 0.1, outputPerMillion: 10)
        let dated = PricingRate(inputPerMillion: 3, cachedInputPerMillion: 3, outputPerMillion: 3)
        let table = PricingTable(rates: [
            "claude-sonnet-5": family, "claude-sonnet-5-5": exact,
            "claude-sonnet-5-5-20261001": dated
        ])
        XCTAssertEqual(table.resolveRate(for: "claude-sonnet-5-5"), exact)
        XCTAssertEqual(table.resolveRate(for: "CLAUDE-SONNET-5-5[1m]"), exact)
        XCTAssertEqual(table.resolveRate(for: "claude-sonnet-5-5-20261002[1m]"), exact)
        XCTAssertEqual(table.resolveRate(for: "claude-sonnet-5-5-20261001[1m]"), dated)
        XCTAssertNil(table.resolveRate(for: "claude-sonnet-5-9"))
        XCTAssertNil(table.resolveRate(for: "claude-sonnet-5-5-preview"))
    }

    func testVariantTableEntryCannotOverwriteTheBaseTier() {
        let base = PricingRate(inputPerMillion: 2, cachedInputPerMillion: 0.1, outputPerMillion: 10)
        let variant = PricingRate(inputPerMillion: 99, cachedInputPerMillion: 99, outputPerMillion: 99)
        let table = PricingTable(rates: ["custom-model": base, "custom-model[1m]": variant])
        XCTAssertEqual(table.rates.count, 2)
        XCTAssertEqual(table.resolveRate(for: "custom-model[1m]"), base)
    }

    func testAPIEquivalentCostCarriesCoverageFlagAndConfidence() {
        let result = APIEquivalentCost(
            amountUSD: 12.34,
            confidence: .estimated,
            hasUnpricedTokens: true
        )

        XCTAssertEqual(result.amountUSD, 12.34)
        XCTAssertEqual(result.confidence, .estimated)
        XCTAssertTrue(result.hasUnpricedTokens)
    }
}
