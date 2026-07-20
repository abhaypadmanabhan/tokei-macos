import Foundation

public struct MaxxerProviderValue: Sendable, Equatable {
    public let providerID: String
    public let apiEquivalentUSD: Double?
    public let planMonthlyUSD: Double?
    public let valueMultiple: Double?
    public let confidence: MetricConfidence
    public let hasUnpricedTokens: Bool
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
