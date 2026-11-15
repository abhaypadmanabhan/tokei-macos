import Foundation
import AppKit

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
    private var pendingFullRefresh = false
    private var pendingRefreshProviders: Set<ProviderID> = []
    private let now: @Sendable () -> Date
    private let isVisible: @Sendable () async -> Bool
    private var visible = true
    private var visibilityTask: Task<Void, Never>?
    private var fileRefreshTask: Task<Void, Never>?
    private var pendingFileProviders: Set<ProviderID> = []
    private var pendingFileRescan = false
    private var lastFileRefresh: [ProviderID: Date] = [:]
    private var lastFullFileRefresh: Date?
    private var lastRefreshAt: [ProviderID: Date] = [:]
    private var autoSyncTask: Task<Void, Never>?
    private var updatesContinuation: AsyncStream<[ProviderSnapshot]>.Continuation?
    /// The last refresh's snapshots and the view model's latest burn state, so the agent
    /// snapshot carries streak and today's burn on every write (the burn is evaluated after
    /// the refresh, by the view model).
    private var lastSnapshots: [ProviderSnapshot]?
    private var lastBurn: BurnSnapshot?

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
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        now: @escaping @Sendable () -> Date = { Date() },
        isVisible: @escaping @Sendable () async -> Bool = {
            await MainActor.run { NSApplication.shared.occlusionState.contains(.visible) }
        }
    ) {
        self.registry = registry
        self.store = store
        self.quotaSeriesStore = quotaSeriesStore
        self.agentSnapshotWriter = agentSnapshotWriter
        self.watcher = watcher
        self.sleep = sleep
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.evaluateThresholds = evaluateThresholds
        self.now = now
        self.isVisible = isVisible
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
        await refresh(providers: nil)
    }

    public func refreshFromUser() async -> [ProviderSnapshot] {
        await refreshAll()
    }

    func refresh(providers: Set<ProviderID>?) async -> [ProviderSnapshot] {
        if let providers { pendingRefreshProviders.formUnion(providers) }
        else { pendingFullRefresh = true }
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task {
            var snapshots: [ProviderSnapshot]
            repeat {
                let providers = self.pendingFullRefresh ? nil : self.pendingRefreshProviders
                self.pendingFullRefresh = false
                self.pendingRefreshProviders.removeAll()
                snapshots = await self.performRefresh(providers: providers)
            } while self.pendingFullRefresh || !self.pendingRefreshProviders.isEmpty
            // Clear before publishing completion so a later caller starts a new run.
            self.refreshTask = nil
            return snapshots
        }
        refreshTask = task
        return await task.value
    }

    private func performRefresh(providers: Set<ProviderID>?) async -> [ProviderSnapshot] {
        await watcher.refreshWatchPaths()
        let refreshed = await registry.snapshots(for: providers)
        let refreshedAt = now()
        for snapshot in refreshed { lastRefreshAt[snapshot.providerID] = refreshedAt }
        var snapshots = refreshed
        if providers != nil {
            let previous: [ProviderSnapshot]
            if let lastSnapshots { previous = lastSnapshots }
            else { previous = await store.allSnapshots() }
            let changed = Set(refreshed.map(\.providerID))
            snapshots += previous.filter { !changed.contains($0.providerID) }
        }
        snapshots.sort { $0.providerID.rawValue < $1.providerID.rawValue }
        await store.save(snapshots: snapshots)
        await quotaSeriesStore.append(from: snapshots)
        await evaluateThresholds(snapshots)
        updatesContinuation?.yield(snapshots)
        // Last: nothing in-process reads this back (only the external `tokei` CLI/MCP
        // helper does), so it shouldn't gate notification delivery or the UI-facing yield.
        lastSnapshots = snapshots
        await agentSnapshotWriter.write(from: snapshots, burn: lastBurn)
        return snapshots
    }

    /// Hands the view model's freshly evaluated live burn state to the agent snapshot.
    /// Saved (preview) evaluations are never published.
    public func publishBurn(_ burn: BurnSnapshot) async {
        lastBurn = burn
        guard let lastSnapshots else { return }
        await agentSnapshotWriter.write(from: lastSnapshots, burn: burn)
    }

    public func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self, watcher] in
            let stream = await watcher.events
            guard !Task.isCancelled else { return }
            await watcher.start()
            if let self { await self.visibilityChanged(await self.isVisible()) }
            for await event in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.handleFileEvent(event)
            }
        }
        visibilityTask = Task { [weak self, isVisible] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeOcclusionStateNotification) {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.visibilityChanged(await isVisible())
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

    func handleFileEvent(_ event: FileWatcher.Event) async {
        if let providers = await watcher.affectedProviders(for: event) {
            pendingFileProviders.formUnion(providers)
        } else { pendingFileRescan = true }
        await drainFileEvents()
    }

    func visibilityChanged(_ isVisible: Bool) async {
        let becameVisible = isVisible && !visible
        visible = isVisible
        if visible {
            // A continuous writer may still be inside the watcher's ten-second batch.
            await watcher.flushPendingEvents()
            await drainFileEvents()
            if becameVisible {
                let date = now()
                let stale = Set(registry.providers.map(\.id).filter {
                    date.timeIntervalSince(lastRefreshAt[$0] ?? .distantPast) > 15
                })
                if !stale.isEmpty { _ = await refresh(providers: stale) }
            }
        }
    }

    private func drainFileEvents() async {
        fileRefreshTask?.cancel()
        fileRefreshTask = nil
        let date = now()
        if pendingFileRescan {
            let last = max(lastFullFileRefresh ?? .distantPast, lastFileRefresh.values.max() ?? .distantPast)
            let delay = visible ? 0 : max(0, 15 - date.timeIntervalSince(last))
            if delay > 0 { scheduleFileRefresh(after: delay); return }
            pendingFileRescan = false
            pendingFileProviders.removeAll()
            lastFullFileRefresh = date
            for provider in registry.providers { lastFileRefresh[provider.id] = date }
            _ = await refreshAll()
        } else {
            let ready = pendingFileProviders.filter {
                visible || date.timeIntervalSince(lastFileRefresh[$0] ?? .distantPast) >= 15
            }
            pendingFileProviders.subtract(ready)
            for provider in ready { lastFileRefresh[provider] = date }
            if !ready.isEmpty { _ = await refresh(providers: ready) }
        }
        if !pendingFileProviders.isEmpty {
            let next = pendingFileProviders.map {
                max(0, 15 - now().timeIntervalSince(lastFileRefresh[$0] ?? .distantPast))
            }.min() ?? 15
            scheduleFileRefresh(after: next)
        }
    }

    private func scheduleFileRefresh(after interval: TimeInterval) {
        fileRefreshTask?.cancel()
        fileRefreshTask = Task { [weak self, sleep] in
            do { try await sleep(interval) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.scheduledFileRefresh()
        }
    }

    private func scheduledFileRefresh() async {
        fileRefreshTask = nil
        await drainFileEvents()
    }

    public func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        visibilityTask?.cancel()
        visibilityTask = nil
        fileRefreshTask?.cancel()
        fileRefreshTask = nil
        pendingFileProviders.removeAll()
        pendingFileRescan = false
        Task {
            await watcher.stop()
        }
    }
}
