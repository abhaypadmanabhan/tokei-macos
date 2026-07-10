import Foundation

public struct QuotaSample: Codable, Equatable, Sendable {
    public let providerID: ProviderID
    public let windowType: QuotaWindowType
    public let bucketKey: String
    public let usedPercent: Double
    public let used: Double
    public let limit: Double
    public let resetAt: Date?
    public let sampledAt: Date

    public init(
        providerID: ProviderID,
        windowType: QuotaWindowType,
        bucketKey: String,
        usedPercent: Double,
        used: Double,
        limit: Double,
        resetAt: Date? = nil,
        sampledAt: Date
    ) {
        self.providerID = providerID
        self.windowType = windowType
        self.bucketKey = bucketKey
        self.usedPercent = usedPercent
        self.used = used
        self.limit = limit
        self.resetAt = resetAt
        self.sampledAt = sampledAt
    }
}

extension QuotaSample {
    init?(window: QuotaWindow, sampledAt: Date) {
        guard let limit = window.limit, limit > 0 else { return nil }
        guard let used = window.used ?? window.remaining.map({ limit - $0 }) else { return nil }

        let usedPercent = min(100, max(0, used / limit * 100))
        self.init(
            providerID: window.providerID,
            windowType: window.type,
            bucketKey: window.bucketKey ?? "\(window.providerID.rawValue)_\(window.type.rawValue)",
            usedPercent: usedPercent,
            used: used,
            limit: limit,
            resetAt: window.resetAt,
            sampledAt: sampledAt
        )
    }

    func isSameSeries(as other: QuotaSample) -> Bool {
        providerID == other.providerID &&
            windowType == other.windowType &&
            bucketKey == other.bucketKey
    }

    func hasSameReading(as other: QuotaSample) -> Bool {
        isSameSeries(as: other) &&
            usedPercent == other.usedPercent &&
            used == other.used &&
            limit == other.limit &&
            resetAt == other.resetAt
    }
}
