import Foundation

public actor SyncEngine {
    public static let shared = SyncEngine()

    private let registry: ProviderRegistry
    private let store: UsageStore
    private let watcher: FileWatcher
    private var autoSyncTask: Task<Void, Never>?
    private var updatesContinuation: AsyncStream<[ProviderSnapshot]>.Continuation?

    public let updates: AsyncStream<[ProviderSnapshot]>

    public init(
        registry: ProviderRegistry = .default(),
        store: UsageStore = .shared,
        watcher: FileWatcher = .shared
    ) {
        self.registry = registry
        self.store = store
        self.watcher = watcher
        var continuation: AsyncStream<[ProviderSnapshot]>.Continuation!
        self.updates = AsyncStream { cont in
            continuation = cont
        }
        self.updatesContinuation = continuation
    }

    public func refreshAll() async -> [ProviderSnapshot] {
        let snapshots = await registry.snapshotAll()
        await store.save(snapshots: snapshots)
        updatesContinuation?.yield(snapshots)
        return snapshots
    }

    public func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.watcher.events
            await self.watcher.start()
            for await _ in stream {
                _ = await self.refreshAll()
            }
        }
    }

    public func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        Task {
            await watcher.stop()
        }
    }
}
