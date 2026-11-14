import Foundation

/// Durable achievements only. Refresh timestamps and transient moments never reach disk.
public struct BurnState: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = currentVersion
    public var initialized = false
    public var longestStreak = 0
    public var badges: [String: Date] = [:]
    public var records: [String: Record] = [:]
    public var tierMonth: Date?
    public var tier: String?

    public init() {}

    public struct Record: Codable, Sendable, Equatable {
        public let value: Double
        public let unit: String?
        public let achievedAt: Date

        init(_ record: BurnRecord) {
            value = record.value
            unit = record.unit?.rawValue
            achievedAt = record.achievedAt
        }

        func burnRecord(kind: BurnRecordKind) -> BurnRecord {
            BurnRecord(kind: kind, value: value, unit: unit.flatMap(BurnUnit.init(rawValue:)), achievedAt: achievedAt)
        }
    }
}
