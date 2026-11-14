import XCTest
import os
@testable import AIUsageDashboardCore

@MainActor
final class BurnViewModelTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private let f = BurnFixtures()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = directory.appendingPathComponent("preferences").path
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        MaxxerPlanCostStore(defaults: defaults).setMonthlyUSD(31, for: "codex")
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func setup(snapshot: ProviderSnapshot, probe: BurnProbe,
                       offMain: OSAllocatedUnfairLock<Bool> = .init(initialState: false))
        -> (DashboardViewModel, SyncEngine, BurnStateStore, UsageStore, FileWatcher) {
        let output = directory.appendingPathComponent("output")
        let input = directory.appendingPathComponent("input")
        let store = UsageStore(directory: output)
        let burnStore = BurnStateStore(directory: output)
        let f = f
        let quota = QuotaSeriesStore(now: { f.now }, directory: output)
        let watcher = FileWatcher(paths: [input])
        let sync = SyncEngine(registry: ProviderRegistry(providers: [BurnProvider(snapshot: snapshot)]),
                              store: store, quotaSeriesStore: quota, agentSnapshotWriter: AgentSnapshotWriter(directory: output),
                              watcher: watcher, evaluateThresholds: { _ in })
        let model = DashboardViewModel(syncEngine: sync, store: store, calendar: f.calendar, now: { f.now },
                                       burnStateStore: burnStore, quotaSeriesStore: quota, burnDefaults: defaults,
                                       burnPricing: { offMain.withLock { $0 = !Thread.isMainThread }; return f.pricing },
                                       notifyBurn: { snapshot, _ in await probe.add(snapshot) })
        return (model, sync, burnStore, store, watcher)
    }

    func testRefreshSetsBurnAndPersistsOffMainAndNotifiesFromLive() async {
        let probe = BurnProbe()
        let offMain = OSAllocatedUnfairLock(initialState: false)
        let (model, _, burnStore, _, _) = setup(snapshot: f.snapshot(days: [0: 2_000_000]), probe: probe, offMain: offMain)
        await model.refresh()
        XCTAssertEqual(model.burn.today.valueUSD, 2)
        XCTAssertEqual(model.burn.today.goal?.target, 1)
        XCTAssertEqual(model.burn.today.progress, 2)
        XCTAssertTrue(offMain.withLock { $0 })
        let state = await burnStore.load()
        XCTAssertTrue(state.initialized)
        let delivered = await probe.snapshots
        XCTAssertEqual(delivered, [model.burn])
    }

    func testSavedComputesWithoutMomentsNudgesOrChangingDurableStateThenLiveUpdates() async throws {
        let probe = BurnProbe()
        let (model, _, burnStore, usageStore, _) = setup(snapshot: f.snapshot(days: [0: 3_000_000]), probe: probe)
        let durable = f.evaluate([f.snapshot(days: [0: 2_000_000])]).state
        try await burnStore.save(durable)
        await usageStore.save(snapshot: f.snapshot(days: [0: 1_000_000]))
        await model.loadSavedSnapshots()
        XCTAssertTrue(model.showingSavedSnapshots)
        XCTAssertEqual(model.burn.today.valueUSD, 1)
        XCTAssertTrue(model.burn.moments.isEmpty)
        let delivered = await probe.snapshots
        XCTAssertTrue(delivered.isEmpty)
        let unchanged = await burnStore.load()
        XCTAssertEqual(unchanged, durable)
        await model.refresh()
        XCTAssertFalse(model.showingSavedSnapshots)
        XCTAssertEqual(model.burn.today.valueUSD, 3)
        XCTAssertTrue(model.burn.moments.contains(.record(.bestDay)))
        let live = await probe.snapshots
        XCTAssertEqual(live.count, 1)
    }

    func testHiddenProviderMatchesOverviewAndNoSavedTodayInvented() async {
        let probe = BurnProbe()
        let (model, _, _, usageStore, _) = setup(snapshot: f.snapshot(days: [0: 2_000_000]), probe: probe)
        defaults.set(true, forKey: "provider_hidden_codex")
        await model.refresh()
        XCTAssertEqual(model.burn.today.tokens, 0)
        XCTAssertNil(model.burn.today.goal)
        XCTAssertTrue(model.burn.leaderboard.isEmpty)
        XCTAssertEqual(model.menuBarTodayTotal, 0)
        let earlier = BurnFixtures(day: 1)
        await usageStore.save(snapshot: earlier.snapshot(days: [0: 2_000_000]))
        let (savedModel, _, _, _, _) = setup(snapshot: f.snapshot(days: [:]), probe: probe)
        defaults.removeObject(forKey: "provider_hidden_codex")
        await savedModel.loadSavedSnapshots()
        XCTAssertEqual(savedModel.burn.today.tokens, 0)
        XCTAssertNil(savedModel.burn.today.valueUSD)
        XCTAssertTrue(savedModel.burn.moments.isEmpty)
    }

    func testSupersededEvaluationCannotSeedStateOrNotifyOldData() async {
        let probe = BurnProbe()
        let (model, _, _, _, _) = setup(snapshot: f.snapshot(days: [0: 3_000_000]), probe: probe)
        let gate = BurnEvaluationGate()
        model.burnTask = Task { await gate.wait() }
        model.snapshots = [f.snapshot(days: [0: 1_000_000])]
        let old = Task { await model.recomputeBurn(saved: false) }
        for _ in 0..<200 {
            if model.burnGeneration >= 1 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.burnGeneration, 1)
        model.snapshots = [f.snapshot(days: [0: 3_000_000])]
        let latest = Task { await model.recomputeBurn(saved: false) }
        for _ in 0..<200 {
            if model.burnGeneration >= 2 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.burnGeneration, 2)
        await gate.release()
        await old.value
        await latest.value
        XCTAssertEqual(model.burn.today.valueUSD, 3)
        XCTAssertTrue(model.burn.moments.isEmpty, "the latest live data seeds, not the superseded evaluation")
        let notifications = await probe.snapshots
        XCTAssertEqual(notifications.map { $0.today.valueUSD }, [3])
    }

    func testAutoSyncUpdateAlsoSetsBurn() async throws {
        let probe = BurnProbe()
        let (model, sync, _, _, watcher) = setup(snapshot: f.snapshot(days: [0: 4_000_000]), probe: probe)
        let input = directory.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        model.beginAutoSync()
        _ = await sync.refreshAll()
        for _ in 0..<200 {
            if model.burn.today.valueUSD == 4 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.burn.today.valueUSD, 4)
        await sync.stopAutoSync()
        await watcher.stop()
    }
}

private struct BurnProvider: UsageProvider {
    let snapshot: ProviderSnapshot
    var id: ProviderID { snapshot.providerID }
    var displayName: String { snapshot.displayName }
    let capabilities: ProviderCapabilities = [.localLog, .tokenUsage]
    func detectAvailability() async -> ProviderAvailability { .installed }
    func authenticate() async throws -> AuthStatus { .authenticated }
    func fetchSnapshot() async throws -> ProviderSnapshot { snapshot }
}

private actor BurnProbe {
    private(set) var snapshots: [BurnSnapshot] = []
    func add(_ snapshot: BurnSnapshot) { snapshots.append(snapshot) }
}

private actor BurnEvaluationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
