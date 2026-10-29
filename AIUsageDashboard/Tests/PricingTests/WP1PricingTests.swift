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
