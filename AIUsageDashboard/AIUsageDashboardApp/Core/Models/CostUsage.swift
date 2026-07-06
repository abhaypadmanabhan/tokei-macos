import Foundation

public struct CostUsage: Sendable {
    public let amount: Double?
    public let currency: String?
    public let confidence: MetricConfidence

    public init(amount: Double? = nil, currency: String? = nil, confidence: MetricConfidence) {
        self.amount = amount
        self.currency = currency
        self.confidence = confidence
    }
}
