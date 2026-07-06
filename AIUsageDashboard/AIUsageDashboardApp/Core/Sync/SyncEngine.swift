import Foundation

public actor SyncEngine {
    public static let shared = SyncEngine()

    private let registry: ProviderRegistry
    private let store: UsageStore

    public init(registry: ProviderRegistry = .default(), store: UsageStore = .shared) {
        self.registry = registry
        self.store = store
    }

    public func refreshAll() async -> [ProviderSnapshot] {
        let snapshots = await registry.snapshotAll()
        await store.save(snapshots: snapshots)
        return snapshots
    }
}
