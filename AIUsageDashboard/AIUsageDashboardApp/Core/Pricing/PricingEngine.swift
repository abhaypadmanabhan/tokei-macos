import Foundation

public struct PricingEngine: Sendable {
    public let table: PricingTable

    public init(table: PricingTable = PricingSeed.defaultTable) {
        self.table = table
    }

    /// Returns API-equivalent USD for `tokens`, or nil when no public rate resolves.
    public func cost(model: String, tokens: TokenUsage) -> Double? {
        guard let rate = table.resolveRate(for: model) else { return nil }

        let input = Double(tokens.inputTokens ?? 0) * rate.inputPerMillion
        let cacheCreation = Double(tokens.cacheCreationTokens ?? 0) * rate.cacheCreationInputPerMillion
        let cacheRead = Double(tokens.cacheReadTokens ?? 0) * rate.cachedInputPerMillion
        let output = (Double(tokens.outputTokens ?? 0) + Double(tokens.reasoningTokens ?? 0)) * rate.outputPerMillion

        return (input + cacheCreation + cacheRead + output) / 1_000_000
    }
}
