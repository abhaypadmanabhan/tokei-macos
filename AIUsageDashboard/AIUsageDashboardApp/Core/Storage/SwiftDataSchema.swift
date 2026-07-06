import Foundation

/// SwiftData schema placeholders.
/// The final schema will contain entities such as ProviderSnapshotEntity,
/// QuotaWindowEntity, TokenUsageEntity, and CostUsageEntity.
public enum SwiftDataSchema {
    public static let schemaVersion: UInt64 = 1
    public static let modelName = "AIUsageDashboardModel"
}
