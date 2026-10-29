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
        let creation = max(0, tokens.cacheCreationTokens ?? 0)
        let oneHour = min(creation, max(0, tokens.cacheCreation1hTokens ?? 0))
        let cacheCreation = Double(creation - oneHour) * rate.cacheCreationInputPerMillion
            + Double(oneHour) * rate.cacheCreation1hInputPerMillion
        let cacheRead = Double(tokens.cacheReadTokens ?? 0) * rate.cachedInputPerMillion
        let output = (Double(tokens.outputTokens ?? 0) + Double(tokens.reasoningTokens ?? 0)) * rate.outputPerMillion

        return (input + cacheCreation + cacheRead + output) / 1_000_000
    }
}

extension UsageAggregation {
    static func mergeModels(_ maps: [[Date: [String: TokenUsage]]]) -> [Date: [String: TokenUsage]] {
        maps.reduce(into: [:]) { result, days in
            for (day, models) in days {
                result[day] = sumModels([result[day] ?? [:], models])
            }
        }
    }

    static func sumModels(_ maps: [[String: TokenUsage]]) -> [String: TokenUsage] {
        maps.reduce(into: [:]) { result, models in
            result.merge(models) { $0.merging($1) }
        }
    }
}
