import Combine
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
                       offMain: OSAllocatedUnfairLock<Bool> = .init(initialState: false),
                       clock: OSAllocatedUnfairLock<Date>? = nil, notificationGate: BurnEvaluationGate? = nil)
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
        let model = DashboardViewModel(syncEngine: sync, store: store, calendar: f.calendar, now: { clock?.withLock { $0 } ?? f.now },
                                       burnStateStore: burnStore, quotaSeriesStore: quota, burnDefaults: defaults,
                                       burnPricing: { offMain.withLock { $0 = !Thread.isMainThread }; return f.pricing },
                                       notifyBurn: { snapshot, _ in
                                           if let notificationGate { await notificationGate.wait() }
                                           await probe.add(snapshot)
                                       })
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
        let notified = await delivered(probe, count: 1)
        XCTAssertEqual(notified, [model.burn])
    }

    func testSavedComputesWithoutMomentsNudgesOrChangingDurableStateThenLiveUpdates() async throws {
        let probe = BurnProbe()
        let (model, _, burnStore, usageStore, _) = setup(snapshot: f.snapshot(days: [0: 3_000_000]), probe: probe)
        let durable = f.evaluate([f.snapshot(days: [-1: 2_000_000])]).state
        try await burnStore.save(durable)
        await usageStore.save(snapshot: f.snapshot(days: [0: 1_000_000]))
        await model.loadSavedSnapshots()
        XCTAssertTrue(model.showingSavedSnapshots)
        XCTAssertEqual(model.burn.today.valueUSD, 1)
        XCTAssertTrue(model.burn.moments.isEmpty)
        let savedNotifications = await probe.snapshots
        XCTAssertTrue(savedNotifications.isEmpty)
        let unchanged = await burnStore.load()
        XCTAssertEqual(unchanged, durable)
        await model.refresh()
        XCTAssertFalse(model.showingSavedSnapshots)
        XCTAssertEqual(model.burn.today.valueUSD, 3)
        XCTAssertTrue(model.burn.moments.contains(.record(.bestDay)))
        let live = await delivered(probe, count: 1)
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
        _ = await delivered(probe, count: 1)
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
        let notifications = await delivered(probe, count: 1)
        XCTAssertEqual(notifications.map { $0.today.valueUSD }, [3])
    }

    func testHiddenProviderQuotaSamplesCannotAffectBurnWindowsOrBadges() async {
        let probe = BurnProbe()
        let clock = OSAllocatedUnfairLock(initialState: f.now.addingTimeInterval(3_600))
        let (model, _, _, _, _) = setup(snapshot: f.snapshot(days: [0: 2_000_000]), probe: probe, clock: clock)
        let window = QuotaWindow(providerID: .codex, type: .fiveHour, used: 95, limit: 100,
                                 resetAt: f.now.addingTimeInterval(600), confidence: .providerReported, source: "fixture")
        await model.burnQuotaSeriesStore.append(from: [f.snapshot(days: [:], windows: [window])])
        let samples = await model.burnQuotaSeriesStore.allSamples()
        XCTAssertEqual(samples.count, 1)
        defaults.set(true, forKey: "provider_hidden_codex")
        await model.refresh()
        XCTAssertTrue(model.burn.recentWindows.isEmpty)
        XCTAssertNil(model.burn.leftOnTablePercent)
        XCTAssertFalse(model.burn.badges.first { $0.badge == .ranItDry }!.isUnlocked)
        _ = await delivered(probe, count: 1)
    }

    func testNotificationPermissionCannotHoldRefreshSpinner() async {
        let probe = BurnProbe()
        let gate = BurnEvaluationGate()
        let (model, _, _, _, _) = setup(snapshot: f.snapshot(days: [0: 2_000_000]), probe: probe, notificationGate: gate)
        let refresh = Task { await model.refresh() }
        for _ in 0..<200 {
            if await gate.waiting { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let waiting = await gate.waiting
        XCTAssertTrue(waiting, "the notification callback has reached its held permission prompt")
        for _ in 0..<200 {
            if !model.isLoading { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(model.isLoading, "refresh must finish while the notification prompt is still held")
        await gate.release()
        await refresh.value
        _ = await delivered(probe, count: 1)
    }

    func testOnlyGeneratedAtChangeDoesNotPublishBurnAgain() async {
        let probe = BurnProbe()
        let clock = OSAllocatedUnfairLock(initialState: f.now)
        let (model, _, _, _, _) = setup(snapshot: f.snapshot(days: [0: 2_000_000]), probe: probe, clock: clock)
        var changes = 0
        let subscription = model.$burn.sink { _ in changes += 1 }
        defer { subscription.cancel() }
        await model.refresh()
        let generatedAt = model.burn.generatedAt
        clock.withLock { $0 = f.now.addingTimeInterval(60) }
        await model.refresh()
        XCTAssertEqual(model.burn.generatedAt, generatedAt)
        XCTAssertEqual(changes, 2, "one initial value plus the first refresh, no duplicate publication")
        _ = await delivered(probe, count: 2)
    }

    private func delivered(_ probe: BurnProbe, count: Int) async -> [BurnSnapshot] {
        for _ in 0..<200 {
            let values = await probe.snapshots
            if values.count >= count { return values }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing burn notification callback")
        return await probe.snapshots
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
        _ = await delivered(probe, count: 1)
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
    private(set) var waiting = false
    func wait() async {
        waiting = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
