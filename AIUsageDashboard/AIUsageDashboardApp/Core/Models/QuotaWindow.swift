import Foundation

public struct QuotaWindow: Sendable, Identifiable {
    public var id: String { "\(providerID.rawValue)_\(type.rawValue)" }
    public let providerID: ProviderID
    public let type: QuotaWindowType
    public let used: Double?
    public let limit: Double?
    public let remaining: Double?
    public let resetAt: Date?
    public let confidence: MetricConfidence
    public let source: String

    public init(
        providerID: ProviderID,
        type: QuotaWindowType,
        used: Double? = nil,
        limit: Double? = nil,
        remaining: Double? = nil,
        resetAt: Date? = nil,
        confidence: MetricConfidence,
        source: String
    ) {
        self.providerID = providerID
        self.type = type
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.confidence = confidence
        self.source = source
    }
}

