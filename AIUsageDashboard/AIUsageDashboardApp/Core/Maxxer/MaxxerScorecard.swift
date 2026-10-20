import Foundation

public struct MaxxerProviderValue: Sendable, Equatable {
    public let providerID: String
    public let apiEquivalentUSD: Double?
    public let planMonthlyUSD: Double?
    public let valueMultiple: Double?
    public let confidence: MetricConfidence
    public let hasUnpricedTokens: Bool
    /// Month-to-date value split by the model that served the tokens, largest first.
    /// Empty when the provider's logs do not name models.
    public let models: [MaxxerModelValue]
}

/// One model's share of a provider's month-to-date API-equivalent value.
public struct MaxxerModelValue: Sendable, Equatable {
    /// Raw model slug as written in the logs (e.g. `claude-opus-5-5`, `gpt-6.1-sol`).
    public let model: String
    public let totalTokens: Int
    /// API-equivalent USD at this model's public rate; `nil` when no rate resolves
    /// (the tokens are counted but never priced with a guessed rate).
    public let apiEquivalentUSD: Double?
}

public enum MaxxerTier: String, CaseIterable, Sendable {
    case idle
    case warming
    case breakEven
    case maxxing
    case goblinMode
}

public struct MaxxerScorecard: Sendable, Equatable {
    public let providers: [MaxxerProviderValue]
    public let totalAPIEquivalentUSD: Double?
    public let totalPlanUSD: Double?
    public let totalValueMultiple: Double?
    public let tier: MaxxerTier?
}
