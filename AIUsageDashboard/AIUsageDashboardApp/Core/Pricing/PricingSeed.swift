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
/// Captured 2026-07-08. Anthropic rows use first-party Claude API pricing; cache
/// creation uses the 5-minute cache-write column and cache reads use the cache-hit
/// column. OpenAI/Codex rows mirror `CodexPricing` captured 2026-07-06. Cursor,
/// Kimi, Cline, and GLM rows are curated overrides so local model slugs can resolve
/// without a network refresh on first run.
public enum PricingSeed {
    public static let capturedAt = "2026-07-08"

    public static let defaultTable = PricingTable(rates: [
        // Anthropic Claude.
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

        // OpenAI / Codex. Keep these in sync with Core/Providers/CodexPricing.swift.
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
    ])

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
