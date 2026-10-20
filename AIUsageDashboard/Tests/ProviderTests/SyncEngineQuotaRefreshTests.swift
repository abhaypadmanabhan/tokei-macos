import XCTest
@testable import AIUsageDashboardCore

private actor QuotaRefreshSleeper {
    var intervals: [TimeInterval] = []
    private var continuation: CheckedContinuation<Void, Error>?
    func sleep(_ interval: TimeInterval) async throws {
        intervals.append(interval)
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func tick() { continuation?.resume(); continuation = nil }
}

private actor QuotaRefreshProvider: UsageProvider {
    nonisolated let id: ProviderID = .codex
    nonisolated let displayName = "fixture"
    nonisolated let capabilities: ProviderCapabilities = [.quota]
    var calls = 0
    private var held = false
    private var continuation: CheckedContinuation<Void, Never>?
    func detectAvailability() async -> ProviderAvailability { .installed }
    func authenticate() async throws -> AuthStatus { .authenticated }
    func hold() { held = true }
    func release() { held = false; continuation?.resume(); continuation = nil }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        if held { await withCheckedContinuation { continuation = $0 } }
        return ProviderSnapshot(providerID: id, displayName: displayName, authStatus: .authenticated,
                                todayUsage: .unavailable, weekUsage: .unavailable)
    }
}

final class SyncEngineQuotaRefreshTests: XCTestCase {
    private func engine(directory: URL, provider: QuotaRefreshProvider, sleeper: QuotaRefreshSleeper) -> SyncEngine {
        SyncEngine(registry: ProviderRegistry(providers: [provider]),
                   store: UsageStore(directory: directory), quotaSeriesStore: QuotaSeriesStore(directory: directory),
                   agentSnapshotWriter: AgentSnapshotWriter(directory: directory),
                   watcher: FileWatcher(paths: [directory]), evaluateThresholds: { _ in },
                   sleep: { try await sleeper.sleep($0) })
    }

    private func eventually(_ check: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if await check() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for async checkpoint", file: file, line: line)
    }

    func testFiveMinuteClockRefreshesAndStopCancelsNextTick() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = QuotaRefreshProvider()
        let sleeper = QuotaRefreshSleeper()
        let engine = engine(directory: directory, provider: provider, sleeper: sleeper)
        await engine.startAutoSync()
        await engine.startAutoSync()
        await eventually { await sleeper.intervals.count == 1 }
        let intervals = await sleeper.intervals
        XCTAssertEqual(intervals, [300])
        await sleeper.tick()
        await eventually { await sleeper.intervals.count == 2 }
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
        await engine.stopAutoSync()
        await sleeper.tick()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let stoppedCalls = await provider.calls
        XCTAssertEqual(stoppedCalls, 1)
    }

    func testTimerAndConcurrentRefreshJoinOneInFlightOperation() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = QuotaRefreshProvider()
        let sleeper = QuotaRefreshSleeper()
        let engine = engine(directory: directory, provider: provider, sleeper: sleeper)
        await provider.hold()
        let first = Task { await engine.refreshAll() }
        await eventually { await provider.calls == 1 }
        await engine.startAutoSync()
        await eventually { await sleeper.intervals.count == 1 }
        await sleeper.tick()
        let second = Task { await engine.refreshAll() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let concurrentCalls = await provider.calls
        XCTAssertEqual(concurrentCalls, 1)
        await provider.release()
        _ = await first.value
        _ = await second.value
        await eventually { await sleeper.intervals.count == 2 }
        await engine.stopAutoSync()
        await sleeper.tick()
    }
}
