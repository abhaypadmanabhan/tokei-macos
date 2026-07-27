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
    /// When this reading was actually taken — `nil` when the provider doesn't report one.
    ///
    /// The structured answer to "how old is this number". Before this existed, the only
    /// staleness signal was a `" (stale)"` suffix appended to `source` by hand in each
    /// client, which no consumer could reason about, plus a `.estimated` confidence that
    /// conflates "old server number" with "fresh local estimate". Distinct from `resetAt`
    /// (when the budget refills) and from `AgentSnapshot.generatedAt` (when the app last
    /// wrote the file — a snapshot can be seconds old and still contain hour-old readings).
    public let observedAt: Date?

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
        bucketKey: String? = nil,
        observedAt: Date? = nil
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
        self.observedAt = observedAt
    }

    /// A copy stamped with when the reading was taken. Used by clients that learn the
    /// observation time separately from decoding (a live fetch stamps "now"; a cache
    /// serve stamps the cache's own `fetchedAt`).
    public func withObservedAt(_ date: Date) -> QuotaWindow {
        QuotaWindow(
            providerID: providerID,
            type: type,
            used: used,
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
            confidence: confidence,
            source: source,
            label: label,
            bucketKey: bucketKey,
            observedAt: date
        )
    }
}
