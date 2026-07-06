import Foundation

/// Static per-token pricing for OpenAI models seen in Codex CLI session logs.
///
/// Source: openai.com/api/pricing, captured 2026-07-06. This table is a snapshot,
/// not a live feed — OpenAI can reprice at any time, and Codex CLI regularly ships
/// new model slugs (e.g. `gpt-5.5`, `gpt-5.3-codex`) ahead of this table being
/// updated. Rows only exist for models this table's author could verify a price
/// for; any other slug is treated as unknown (see `estimateCost`).
///
/// Codex CLI usage is typically bundled into a ChatGPT subscription rather than
/// billed per token, so this is a token-cost *equivalent* for comparison, not a
/// literal charge.
///
/// Reasoning-output tokens are billed by OpenAI at the same rate as ordinary
/// output tokens (there is no separate published reasoning-token price), so this
/// table folds `reasoningTokens` into the output rate below.
///
/// `estimateCost` prices a whole token aggregate under a single model (see
/// `CodexProvider.costUsage(for:logs:)`, which passes the *most recently
/// configured* model for the entire lifetime/today/week/month totals). If a
/// user has switched models over their history, older tokens actually billed
/// under a different model still get priced at the current model's rate.
public enum CodexPricing {
    public struct Rate: Sendable {
        public let inputPerMillion: Double
        public let cachedInputPerMillion: Double
        public let outputPerMillion: Double
    }

    public static let rates: [String: Rate] = [
        "gpt-5": Rate(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
        "gpt-5-mini": Rate(inputPerMillion: 0.25, cachedInputPerMillion: 0.025, outputPerMillion: 2.00),
        "gpt-5-nano": Rate(inputPerMillion: 0.05, cachedInputPerMillion: 0.005, outputPerMillion: 0.40),
        "gpt-4.1": Rate(inputPerMillion: 2.00, cachedInputPerMillion: 0.50, outputPerMillion: 8.00),
        "gpt-4.1-mini": Rate(inputPerMillion: 0.40, cachedInputPerMillion: 0.10, outputPerMillion: 1.60),
        "gpt-4.1-nano": Rate(inputPerMillion: 0.10, cachedInputPerMillion: 0.025, outputPerMillion: 0.40),
        "gpt-4o": Rate(inputPerMillion: 2.50, cachedInputPerMillion: 1.25, outputPerMillion: 10.00),
        "gpt-4o-mini": Rate(inputPerMillion: 0.15, cachedInputPerMillion: 0.075, outputPerMillion: 0.60),
        "o3": Rate(inputPerMillion: 2.00, cachedInputPerMillion: 0.50, outputPerMillion: 8.00),
        "o3-mini": Rate(inputPerMillion: 1.10, cachedInputPerMillion: 0.55, outputPerMillion: 4.40),
        "o4-mini": Rate(inputPerMillion: 1.10, cachedInputPerMillion: 0.275, outputPerMillion: 4.40),
    ]

    /// Returns the estimated USD cost of `tokens` under `model`'s published rate, or
    /// `nil` if `model` has no row in `rates` — never fabricates a number for an
    /// unrecognized model.
    public static func estimateCost(tokens: TokenUsage, model: String) -> Double? {
        guard let rate = rates[model] else { return nil }
        let billedInput = Double(tokens.inputTokens ?? 0)
        let cachedInput = Double(tokens.cacheReadTokens ?? 0)
        let billedOutput = Double(tokens.outputTokens ?? 0) + Double(tokens.reasoningTokens ?? 0)

        let amount = billedInput * rate.inputPerMillion
            + cachedInput * rate.cachedInputPerMillion
            + billedOutput * rate.outputPerMillion
        return amount / 1_000_000
    }
}
