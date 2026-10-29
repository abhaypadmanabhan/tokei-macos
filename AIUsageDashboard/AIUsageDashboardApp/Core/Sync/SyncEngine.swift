import Foundation

public actor SyncEngine {
    public static let shared = SyncEngine()

    private let registry: ProviderRegistry
    private let store: UsageStore
    private let quotaSeriesStore: QuotaSeriesStore
    private let agentSnapshotWriter: AgentSnapshotWriter
    private let watcher: FileWatcher
    private let evaluateThresholds: @Sendable ([ProviderSnapshot]) async -> Void
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let isLowPowerModeEnabled: @Sendable () -> Bool
    private var periodicSyncTask: Task<Void, Never>?
    private var refreshTask: Task<[ProviderSnapshot], Never>?
    private var refreshDirty = false
    private var autoSyncTask: Task<Void, Never>?
    private var updatesContinuation: AsyncStream<[ProviderSnapshot]>.Continuation?

    public let updates: AsyncStream<[ProviderSnapshot]>

    public init(
        registry: ProviderRegistry = .default(),
        store: UsageStore = .shared,
        quotaSeriesStore: QuotaSeriesStore = .shared,
        agentSnapshotWriter: AgentSnapshotWriter = .shared,
        watcher: FileWatcher = .shared,
        evaluateThresholds: @escaping @Sendable ([ProviderSnapshot]) async -> Void = {
            await NotificationEngine.shared.evaluateThresholds(for: $0)
        },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.registry = registry
        self.store = store
        self.quotaSeriesStore = quotaSeriesStore
        self.agentSnapshotWriter = agentSnapshotWriter
        self.watcher = watcher
        self.sleep = sleep
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.evaluateThresholds = evaluateThresholds
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
        if let refreshTask {
            refreshDirty = true
            return await refreshTask.value
        }
        let task = Task {
            var snapshots: [ProviderSnapshot]
            repeat {
                self.refreshDirty = false
                snapshots = await self.performRefresh()
            } while self.refreshDirty
            // Clear before publishing completion so a later caller starts a new run.
            self.refreshTask = nil
            return snapshots
        }
        refreshTask = task
        return await task.value
    }

    private func performRefresh() async -> [ProviderSnapshot] {
        let snapshots = await registry.snapshotAll()
        await store.save(snapshots: snapshots)
        await quotaSeriesStore.append(from: snapshots)
        await evaluateThresholds(snapshots)
        updatesContinuation?.yield(snapshots)
        // Last: nothing in-process reads this back (only the external `tokei` CLI/MCP
        // helper does), so it shouldn't gate notification delivery or the UI-facing yield.
        await agentSnapshotWriter.write(from: snapshots)
        return snapshots
    }

    public func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self, watcher] in
            let stream = await watcher.events
            guard !Task.isCancelled else { return }
            await watcher.start()
            for await _ in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                _ = await self.refreshAll()
            }
        }
        periodicSyncTask = Task { [weak self, sleep, isLowPowerModeEnabled] in
            while !Task.isCancelled {
                do { try await sleep(isLowPowerModeEnabled() ? 1800 : 300) } catch { break }
                guard !Task.isCancelled else { break }
                guard let self else { break }
                _ = await self.refreshAll()
            }
        }
    }

    public func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        Task {
            await watcher.stop()
        }
    }
}
