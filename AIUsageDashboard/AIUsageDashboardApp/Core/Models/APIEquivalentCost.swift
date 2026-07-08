import Foundation

public struct APIEquivalentCost: Sendable, Equatable {
    public let amountUSD: Double?
    public let confidence: MetricConfidence
    public let hasUnpricedTokens: Bool

    public init(
        amountUSD: Double? = nil,
        confidence: MetricConfidence,
        hasUnpricedTokens: Bool
    ) {
        self.amountUSD = amountUSD
        self.confidence = confidence
        self.hasUnpricedTokens = hasUnpricedTokens
    }
}
