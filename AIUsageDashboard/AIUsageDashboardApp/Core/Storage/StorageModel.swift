import Foundation

/// Placeholder for the SwiftData persistence model layer.
/// Concrete entities will be added in Phase 1.
public enum StorageModel {
    case snapshot(ProviderSnapshot)
    case tokenUsage(providerID: ProviderID, range: UsageRange, usage: TokenUsage)
}
