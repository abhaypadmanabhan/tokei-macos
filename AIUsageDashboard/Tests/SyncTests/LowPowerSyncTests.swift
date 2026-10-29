import XCTest
@testable import AIUsageDashboardCore

final class LowPowerSyncTests: XCTestCase {
    private var directory: URL!
    private var input: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        input = directory.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func engine(power: PowerState, sleeper: SyncTestSleeper, watcher: FileWatcher) -> SyncEngine {
        let output = directory.appendingPathComponent("output")
        return SyncEngine(
            registry: ProviderRegistry(providers: []), store: UsageStore(directory: output),
            quotaSeriesStore: QuotaSeriesStore(directory: output),
            agentSnapshotWriter: AgentSnapshotWriter(directory: output), watcher: watcher,
            evaluateThresholds: { _ in }, sleep: { try await sleeper.sleep($0) },
            isLowPowerModeEnabled: power.read
        )
    }

    private func eventually(_ check: () async -> Bool) async {
        for _ in 0..<200 {
            if await check() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing sync checkpoint")
    }

    func testLowPowerSleeps1800ThenRechecksPowerAfterTick() async {
        let power = PowerState(true)
        let sleeper = SyncTestSleeper()
        let watcher = FileWatcher(paths: [input])
        let engine = engine(power: power, sleeper: sleeper, watcher: watcher)
        await engine.startAutoSync()
        await eventually { await sleeper.intervals.count == 1 }
        let first = await sleeper.intervals
        XCTAssertEqual(first, [1800])
        power.set(false)
        await sleeper.tick()
        await eventually { await sleeper.intervals.count == 2 }
        let intervals = await sleeper.intervals
        XCTAssertEqual(intervals, [1800, 300])
        await engine.stopAutoSync()
        await sleeper.tick()
        await watcher.stop()
    }

    func testFileEventsRefreshWhileLowPowerTimerIsWaiting() async throws {
        let sleeper = SyncTestSleeper()
        let watcher = FileWatcher(paths: [input], debounceInterval: 0.05)
        let engine = engine(power: PowerState(true), sleeper: sleeper, watcher: watcher)
        let refreshed = expectation(description: "file event refreshed")
        let stream = await engine.updates
        let consumer = Task {
            for await _ in stream { refreshed.fulfill(); break }
        }
        await engine.startAutoSync()
        await eventually { await sleeper.intervals.count == 1 }
        try await Task.sleep(nanoseconds: 200_000_000)
        try Data("changed".utf8).write(to: input.appendingPathComponent("event.txt"))
        await fulfillment(of: [refreshed], timeout: 5)
        consumer.cancel()
        let intervals = await sleeper.intervals
        XCTAssertEqual(intervals, [1800])
        await engine.stopAutoSync()
        await sleeper.tick()
        await watcher.stop()
    }
}

private final class PowerState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(_ value: Bool) { self.value = value }
    func read() -> Bool { lock.withLock { value } }
    func set(_ value: Bool) { lock.withLock { self.value = value } }
}

private actor SyncTestSleeper {
    var intervals: [TimeInterval] = []
    private var continuation: CheckedContinuation<Void, Error>?
    func sleep(_ interval: TimeInterval) async throws {
        intervals.append(interval)
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func tick() { continuation?.resume(); continuation = nil }
}
