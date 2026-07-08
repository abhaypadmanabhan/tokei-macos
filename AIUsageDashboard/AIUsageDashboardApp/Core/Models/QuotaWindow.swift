import Foundation

public struct QuotaWindow: Sendable, Identifiable {
    public var id: String { bucketKey ?? "\(providerID.rawValue)_\(type.rawValue)" }
    public let providerID: ProviderID
    public let type: QuotaWindowType
    public let used: Double?
    public let limit: Double?
    public let remaining: Double?
    public let resetAt: Date?
    public let confidence: MetricConfidence
    public let source: String
    public let label: String?
    public let bucketKey: String?

    public init(
        providerID: ProviderID,
        type: QuotaWindowType,
        used: Double? = nil,
        limit: Double? = nil,
        remaining: Double? = nil,
        resetAt: Date? = nil,
        confidence: MetricConfidence,
        source: String,
        label: String? = nil,
        bucketKey: String? = nil
    ) {
        self.providerID = providerID
        self.type = type
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.confidence = confidence
        self.source = source
        self.label = label
        self.bucketKey = bucketKey
    }
}
