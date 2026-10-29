import Foundation

public protocol PricingTableRefreshing: Sendable {
    func refresh(current table: PricingTable) async throws -> PricingTable
}

public struct NoOpPricingTableRefresher: PricingTableRefreshing {
    public init() {}

    public func refresh(current table: PricingTable) async throws -> PricingTable {
        table
    }
}

/// Bundled offline API-equivalent price seed.
///
/// Updated 2026-10-20 from the local LiteLLM table. Anthropic rows use first-party Claude API pricing; cache
/// creation uses the 5-minute cache-write column and cache reads use the cache-hit
/// column. OpenAI/Codex rows mirror `CodexPricing` captured 2026-07-06. Cursor,
/// Kimi, Cline, and GLM rows are curated overrides so local model slugs can resolve
/// without a network refresh on first run.
public enum PricingSeed {
    public static let capturedAt = "2026-10-20"

    public static let defaultTable: PricingTable = {
        var rates = standardRates
        let priorityModels = ["gpt-5", "gpt-5.1", "gpt-5.3-codex", "gpt-5.4",
                              "gpt-6-astra", "gpt-6.1-sol", "gpt-6-sol", "gpt-5.5"]
        for model in priorityModels {
            guard let rate = rates[model] else { continue }
            rates[model + "@priority"] = PricingTierRates.scale(rate, by: model == "gpt-5.5" ? 2.5 : 2)
        }
        for model in ["gpt-6-astra", "gpt-6.1-sol"] {
            if let rate = rates[model] { rates[model + "@ultrafast"] = PricingTierRates.scale(rate, by: 6) }
        }
        for model in ["claude-opus-5", "claude-opus-5-5"] {
            if let rate = rates[model] { rates[model + "@fast"] = PricingTierRates.scale(rate, by: 2) }
        }
        return PricingTable(rates: rates)
    }()

    private static let standardRates: [String: PricingRate] = [
        // Anthropic Claude.
        "claude-opus-5-5": rate(input: 4.00, cachedInput: 0.20, cacheCreation: 5.00, output: 20.00),
        "claude-opus-5": rate(input: 5.00, cachedInput: 0.50, cacheCreation: 6.25, output: 25.00),
        "claude-fable-5-1": rate(input: 10.00, cachedInput: 0.25, cacheCreation: 12.50, output: 50.00),
        "claude-sonnet-5-5": rate(input: 2.00, cachedInput: 0.10, cacheCreation: 2.50, output: 10.00),
        "claude-haiku-5-5": rate(input: 0.10, cachedInput: 0.01, cacheCreation: 0.125, output: 0.50),
        "claude-opus-4-6": rate(input: 5.00, cachedInput: 0.50, cacheCreation: 6.25, output: 25.00),
        "claude-opus-4-5": rate(input: 5.00, cachedInput: 0.50, cacheCreation: 6.25, output: 25.00),
        "claude-opus-4": rate(input: 5.00, cachedInput: 0.50, cacheCreation: 6.25, output: 25.00),
        "claude-opus-4-20250514": rate(input: 15.00, cachedInput: 1.50, cacheCreation: 18.75, output: 75.00),
        "claude-opus-4-1": rate(input: 15.00, cachedInput: 1.50, cacheCreation: 18.75, output: 75.00),
        "claude-opus-4-1-20250805": rate(input: 15.00, cachedInput: 1.50, cacheCreation: 18.75, output: 75.00),
        "claude-sonnet-5": rate(input: 2.00, cachedInput: 0.20, cacheCreation: 2.50, output: 10.00),
        "claude-sonnet-4": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "claude-sonnet-4-6": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "claude-sonnet-4-5": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "claude-sonnet-4-20250514": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "claude-3-7-sonnet": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "claude-3-5-sonnet": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "claude-haiku-4": rate(input: 1.00, cachedInput: 0.10, cacheCreation: 1.25, output: 5.00),
        "claude-haiku-4-5": rate(input: 1.00, cachedInput: 0.10, cacheCreation: 1.25, output: 5.00),
        "claude-3-5-haiku": rate(input: 0.80, cachedInput: 0.08, cacheCreation: 1.00, output: 4.00),
        "claude-3-haiku": rate(input: 0.25, cachedInput: 0.03, cacheCreation: 0.30, output: 1.25),

        // OpenAI / Codex. Explicit rows replace the former family-rate guess.
        "gpt-6.1-sol": rate(input: 2.00, cachedInput: 0.10, cacheCreation: 2.50, output: 10.00),
        "gpt-6-astra": rate(input: 10.00, cachedInput: 1.00, cacheCreation: 12.50, output: 50.00),
        "gpt-6-sol": rate(input: 2.00, cachedInput: 0.20, cacheCreation: 2.50, output: 10.00),
        "gpt-5.5": rate(input: 5.00, cachedInput: 0.50, output: 30.00),
        "gpt-5.4": rate(input: 2.50, cachedInput: 0.25, output: 15.00),
        "gpt-5.3-codex": rate(input: 1.75, cachedInput: 0.175, output: 14.00),
        "gpt-5.2-codex": rate(input: 1.75, cachedInput: 0.175, output: 14.00),
        "gpt-5.2": rate(input: 1.75, cachedInput: 0.175, output: 14.00),
        "gpt-5.1-codex": rate(input: 1.25, cachedInput: 0.125, output: 10.00),
        "gpt-5.1-codex-max": rate(input: 1.25, cachedInput: 0.125, output: 10.00),
        "gpt-5.1-codex-mini": rate(input: 0.25, cachedInput: 0.025, output: 2.00),
        "gpt-5.1": rate(input: 1.25, cachedInput: 0.125, output: 10.00),
        "gpt-5-codex": rate(input: 1.25, cachedInput: 0.125, output: 10.00),
        "gpt-5": rate(input: 1.25, cachedInput: 0.125, output: 10.00),
        "gpt-5-mini": rate(input: 0.25, cachedInput: 0.025, output: 2.00),
        "gpt-5-nano": rate(input: 0.05, cachedInput: 0.005, output: 0.40),
        "gpt-4.1": rate(input: 2.00, cachedInput: 0.50, output: 8.00),
        "gpt-4.1-mini": rate(input: 0.40, cachedInput: 0.10, output: 1.60),
        "gpt-4.1-nano": rate(input: 0.10, cachedInput: 0.025, output: 0.40),
        "gpt-4o": rate(input: 2.50, cachedInput: 1.25, output: 10.00),
        "gpt-4o-mini": rate(input: 0.15, cachedInput: 0.075, output: 0.60),
        "o3": rate(input: 2.00, cachedInput: 0.50, output: 8.00),
        "o3-mini": rate(input: 1.10, cachedInput: 0.55, output: 4.40),
        "o4-mini": rate(input: 1.10, cachedInput: 0.275, output: 4.40),

        // Antigravity display-name aliases, research 2026-10-28, LiteLLM public table.
        "gemini-3.5-flash": rate(input: 1.50, cachedInput: 0.15, output: 9.00),
        "gemini-3.6-flash": rate(input: 0.75, cachedInput: 0.075, output: 3.75),

        // Cursor Composer API-equivalent overrides.
        "cursor-composer": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),
        "cursor/composer": rate(input: 3.00, cachedInput: 0.30, cacheCreation: 3.75, output: 15.00),

        // Kimi / Moonshot overrides seen through Cline and OpenAI-compatible routes.
        "kimi-k2": rate(input: 0.15, cachedInput: 0.15, output: 2.50),
        "moonshotai/kimi-k2": rate(input: 0.15, cachedInput: 0.15, output: 2.50),
        "moonshot/kimi-k2": rate(input: 0.15, cachedInput: 0.15, output: 2.50),
        "cline-pass/kimi-k2": rate(input: 0.15, cachedInput: 0.15, output: 2.50),
        "cline/kimi-k2": rate(input: 0.15, cachedInput: 0.15, output: 2.50),

        // GLM / Z.ai overrides.
        "glm-4.5": rate(input: 0.60, cachedInput: 0.60, output: 2.20),
        "zai/glm-4.5": rate(input: 0.60, cachedInput: 0.60, output: 2.20),
        "zhipu/glm-4.5": rate(input: 0.60, cachedInput: 0.60, output: 2.20),
        "cline/glm-4.5": rate(input: 0.60, cachedInput: 0.60, output: 2.20),
        "glm-4.5-air": rate(input: 0.20, cachedInput: 0.20, output: 1.10),
        "zai/glm-4.5-air": rate(input: 0.20, cachedInput: 0.20, output: 1.10),
    ]

    private static func rate(
        input: Double,
        cachedInput: Double,
        cacheCreation: Double? = nil,
        output: Double
    ) -> PricingRate {
        PricingRate(
            inputPerMillion: input,
            cachedInputPerMillion: cachedInput,
            cacheCreationInputPerMillion: cacheCreation,
            outputPerMillion: output
        )
    }
}
