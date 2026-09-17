import Foundation

public actor SyncEngine {
    public static let shared = SyncEngine()

    private let registry: ProviderRegistry
    private let store: UsageStore
    private let quotaSeriesStore: QuotaSeriesStore
    private let agentSnapshotWriter: AgentSnapshotWriter
    private let watcher: FileWatcher
    private var autoSyncTask: Task<Void, Never>?
    private var updatesContinuation: AsyncStream<[ProviderSnapshot]>.Continuation?

    public let updates: AsyncStream<[ProviderSnapshot]>

    public init(
        registry: ProviderRegistry = .default(),
        store: UsageStore = .shared,
        quotaSeriesStore: QuotaSeriesStore = .shared,
        agentSnapshotWriter: AgentSnapshotWriter = .shared,
        watcher: FileWatcher = .shared
    ) {
        self.registry = registry
        self.store = store
        self.quotaSeriesStore = quotaSeriesStore
        self.agentSnapshotWriter = agentSnapshotWriter
        self.watcher = watcher
        var continuation: AsyncStream<[ProviderSnapshot]>.Continuation!
        self.updates = AsyncStream { cont in
            continuation = cont
        }
        self.updatesContinuation = continuation
    }

    /// D9: forward a timezone change to every provider that caches calendar-bucketed
    /// data, so the next refresh rebuilds day buckets from original timestamps.
    public func updateCalendar(_ calendar: Calendar) async {
        for provider in registry.providers {
            if let aware = provider as? CalendarAwareProvider {
                await aware.updateCalendar(calendar)
            }
        }
    }

    public func refreshAll() async -> [ProviderSnapshot] {
        let snapshots = await registry.snapshotAll()
        await store.save(snapshots: snapshots)
        await quotaSeriesStore.append(from: snapshots)
        await NotificationEngine.shared.evaluateThresholds(for: snapshots)
        updatesContinuation?.yield(snapshots)
        // Last: nothing in-process reads this back (only the external `tokei` CLI/MCP
        // helper does), so it shouldn't gate notification delivery or the UI-facing yield.
        await agentSnapshotWriter.write(from: snapshots)
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
