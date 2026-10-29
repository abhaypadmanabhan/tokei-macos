import XCTest
@testable import AIUsageDashboardCore

final class WP1PricingTests: XCTestCase {
    func testOneHourCacheIsSubsetAndHandPricedAtSixDollarsPerMillion() throws {
        let tokens = TokenUsage(inputTokens: 1_000_000, outputTokens: 100_000,
                                cacheReadTokens: 200_000, cacheCreationTokens: 1_000_000,
                                cacheCreation1hTokens: 600_000, confidence: .localParsed)
        // $3 input + $1.50 output + $0.06 read + $1.50 five-minute + $3.60 one-hour.
        XCTAssertEqual(try XCTUnwrap(PricingEngine().cost(model: "claude-sonnet-4-6", tokens: tokens)),
                       9.66, accuracy: 0.000001)
    }

    func testDatedAndNamespacedTierUsesExactBaseAndUnknownStaysUnpriced() throws {
        let engine = PricingEngine()
        let tokens = TokenUsage(inputTokens: 1_000_000, confidence: .localParsed)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "anthropic/claude-opus-5-5-20261001[1m]@fast",
                                               tokens: tokens)), 8, accuracy: 0.000001)
        XCTAssertNil(engine.cost(model: "unpriced-model@priority", tokens: tokens))
    }

    func testClaudeFallbackCacheTiersAndExplicitOneHourRate() throws {
        let data = Data((#"{"claude-fixture":{"input_cost_per_token":0.000003,"output_cost_per_token":0.000015,"#
            + #""cache_creation_input_token_cost_above_1hr":0.000009},"#
            + #""claude-fallback":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000010}}"#).utf8)
        let engine = PricingEngine(table: PricingTable(rates: PricingService.parseLiteLLM(data)))
        let split = TokenUsage(cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 600_000,
                               confidence: .localParsed)
        // 400k at $3.75/M plus 600k at the explicit $9/M.
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "claude-fixture", tokens: split)), 6.9, accuracy: 0.000001)
        let oneHour = TokenUsage(cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 1_000_000,
                                 confidence: .localParsed)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "claude-fallback", tokens: oneHour)), 4, accuracy: 0.000001)
    }

    func testMissingTierFallsBackToStandardAndPartialTierScalesOutputAndCache() throws {
        let data = Data((#"{"sample":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000010,"#
            + #""cache_read_input_token_cost":0.0000002,"input_cost_per_token_priority":0.000005}}"#).utf8)
        let engine = PricingEngine(table: PricingTable(rates: PricingService.parseLiteLLM(data)))
        let tokens = TokenUsage(inputTokens: 1_000_000, outputTokens: 100_000,
                                cacheReadTokens: 1_000_000, confidence: .localParsed)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "sample@priority", tokens: tokens)), 8, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "sample@ultrafast", tokens: tokens)), 3.2, accuracy: 0.000001)
    }

    func testCacheOnlyTierRateOverridesCacheWhileOtherRatesStayStandard() throws {
        let data = Data((#"{"sample":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000010,"#
            + #""cache_read_input_token_cost":0.0000002,"cache_read_input_token_cost_priority":0.0000001}}"#).utf8)
        let engine = PricingEngine(table: PricingTable(rates: PricingService.parseLiteLLM(data)))
        let tokens = TokenUsage(inputTokens: 1_000_000, outputTokens: 100_000,
                                cacheReadTokens: 1_000_000, confidence: .localParsed)
        // $2 input + $1 output + $0.10 tier cache read.
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "sample@priority", tokens: tokens)), 3.1, accuracy: 0.000001)
    }

    func testLiteLLMTiersAndMissingCacheTierScaleFromInput() throws {
        let data = Data(
            (#"{"sample":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000010,"cache_read_input_t"#
            + #"oken_cost":0.0000002,"cache_creation_input_token_cost":0.0000025,"cache_creation_input_token_co"#
            + #"st_above_1hr":0.000004,"input_cost_per_token_priority":0.000005,"output_cost_per_token_priority"#
            + #"":0.000025,"input_cost_per_token_ultrafast":0.000012,"output_cost_per_token_ultrafast":0.000060"#
            + #","provider_specific_entry":{"fast":2}}}"#).utf8)
        let table = PricingTable(rates: PricingService.parseLiteLLM(data))
        let engine = PricingEngine(table: table)
        let tokens = TokenUsage(inputTokens: 1_000_000, outputTokens: 100_000,
                                cacheReadTokens: 1_000_000, confidence: .localParsed)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "sample@priority", tokens: tokens)), 8, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "sample@ultrafast", tokens: tokens)), 19.2, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(engine.cost(model: "sample@fast", tokens: tokens)), 6.4, accuracy: 0.000001)
        let cached = PricingService.parseLiteLLM(try JSONEncoder().encode(PricingService.slim(table)))
        XCTAssertEqual(cached["sample"], table.rates["sample"])
    }
}
