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

    func testFuzzyMatcherResolvesNewerMinorUnderKnownFamily() {
        let table = PricingSeed.defaultTable

        let base = table.resolveRate(for: "claude-opus-4")
        let newerMinor = table.resolveRate(for: "claude-opus-4-8")

        XCTAssertNotNil(base)
        XCTAssertEqual(newerMinor, base)
    }

    func testFuzzyMatcherDoesNotResolveUnknownFamily() {
        let table = PricingSeed.defaultTable

        XCTAssertNil(table.resolveRate(for: "claude-lyric-1"))
        XCTAssertNil(table.resolveRate(for: "gpt-50"))
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
