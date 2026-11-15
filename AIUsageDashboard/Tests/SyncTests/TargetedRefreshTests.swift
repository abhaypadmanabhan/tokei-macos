import XCTest
@testable import AIUsageDashboardCore

final class TargetedRefreshTests: XCTestCase {
    private func eventually(_ check: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if await check() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Missing refresh checkpoint", file: file, line: line)
    }

    func testClaudeFileEventDoesNotRefreshCodex() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let claudeLogs = home.appendingPathComponent(".claude/projects")
        let codexLogs = home.appendingPathComponent(".codex/sessions")
        for directory in [claudeLogs, codexLogs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let claude = CountingRefreshProvider(.claudeCode)
        let codex = CountingRefreshProvider(.codex)
        let output = home.appendingPathComponent("output")
        let watcher = FileWatcher(paths: [claudeLogs, codexLogs], debounceInterval: 0.05)
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: [claude, codex]),
            store: UsageStore(directory: output), quotaSeriesStore: QuotaSeriesStore(directory: output),
            agentSnapshotWriter: AgentSnapshotWriter(directory: output), watcher: watcher,
            evaluateThresholds: { _ in }
        )
        _ = await engine.refreshAll()
        await engine.startAutoSync()
        try await Task.sleep(nanoseconds: 200_000_000)
        try Data("fixture".utf8).write(to: claudeLogs.appendingPathComponent("session.jsonl"))
        for _ in 0..<500 {
            if await claude.calls > 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let claudeCalls = await claude.calls
        let codexCalls = await codex.calls
        await engine.stopAutoSync()
        await watcher.stop()
        XCTAssertGreaterThan(claudeCalls, 1, "the real FSEvent must reach sync")
        XCTAssertEqual(codexCalls, 1, "a Claude file event must leave Codex alone")
    }

    func testHiddenWritesRunAtMostOncePerFifteenSecondsAndOpeningCatchesUp() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let logs = home.appendingPathComponent(".claude/projects")
        let provider = CountingRefreshProvider(.claudeCode)
        let clock = RefreshClock()
        let watcher = FileWatcher(paths: [logs])
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: [provider]), store: UsageStore(directory: home),
            quotaSeriesStore: QuotaSeriesStore(directory: home),
            agentSnapshotWriter: AgentSnapshotWriter(directory: home), watcher: watcher,
            evaluateThresholds: { _ in }, sleep: { try await clock.sleep($0) },
            now: { clock.now() }, isVisible: { false }
        )
        await engine.visibilityChanged(false)
        await engine.handleFileEvent(.init(path: logs.appendingPathComponent("active.jsonl").path))
        for second in 1..<15 {
            clock.advance(to: Double(second))
            await engine.handleFileEvent(.init(path: logs.path))
        }
        let beforeDeadline = await provider.calls
        XCTAssertEqual(beforeDeadline, 1)
        await eventually { clock.hasDeadline(15) }
        clock.advance(to: 15)
        await eventually { await provider.calls == 2 }
        clock.advance(to: 16)
        await engine.handleFileEvent(.init(path: logs.path))
        let stillHidden = await provider.calls
        XCTAssertEqual(stillHidden, 2)
        await engine.visibilityChanged(true)
        let opened = await provider.calls
        XCTAssertEqual(opened, 3, "opening must flush dirty providers immediately")
        await engine.stopAutoSync()
        clock.advance(to: 100)
    }

    func testTargetedAndFullRefreshProduceTheSameFixtureSnapshots() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = CountingRefreshProvider(.claudeCode)
        let codex = CountingRefreshProvider(.codex)
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: [claude, codex]), store: UsageStore(directory: home),
            quotaSeriesStore: QuotaSeriesStore(directory: home),
            agentSnapshotWriter: AgentSnapshotWriter(directory: home),
            watcher: FileWatcher(paths: []), evaluateThresholds: { _ in }
        )
        _ = await engine.refreshAll()
        await claude.changeValue(42)
        let targeted = await engine.refresh(providers: [.claudeCode])
        let codexCalls = await codex.calls
        XCTAssertEqual(codexCalls, 1)
        let full = await engine.refreshAll()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(targeted), try encoder.encode(full))
        let saved = await UsageStore(directory: home).allSnapshots()
        XCTAssertEqual(Set(saved.map(\.providerID)), [.claudeCode, .codex], "partial refresh must preserve the saved siblings")
    }

    func testWatcherRetainsEveryProviderPathInOneBatchAndMapsSharedParents() async throws {
        let home = URL(fileURLWithPath: "/tmp/tokei-batch")
        let claude = home.appendingPathComponent(".claude/projects")
        let codex = home.appendingPathComponent(".codex/sessions")
        let watcher = FileWatcher(paths: [claude, codex])
        let stream = await watcher.events
        await watcher.handleEvents(paths: [claude.appendingPathComponent("one").path])
        await watcher.handleEvents(paths: [codex.appendingPathComponent("two").path])
        await watcher.flushPendingEvents()
        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        let event = try XCTUnwrap(next)
        XCTAssertEqual(event.paths.count, 2)
        let targeted = await watcher.affectedProviders(for: event)
        let shared = await watcher.affectedProviders(for: .init(path: home.path))
        let unknown = await watcher.affectedProviders(for: .init(path: home.path + "-other"))
        let dropped = await watcher.affectedProviders(for: .init(paths: [claude.path], requiresFullRescan: true))
        XCTAssertEqual(targeted, [.claudeCode, .codex])
        XCTAssertEqual(shared, [.claudeCode, .codex])
        XCTAssertNil(unknown)
        XCTAssertNil(dropped)
        await watcher.stop()
    }
}

private actor CountingRefreshProvider: UsageProvider {
    nonisolated let id: ProviderID
    nonisolated let displayName = "Fixture"
    nonisolated let capabilities: ProviderCapabilities = [.localLog]
    var calls = 0
    private var value = 1
    init(_ id: ProviderID) { self.id = id }
    func detectAvailability() async -> ProviderAvailability { .installed }
    func authenticate() async throws -> AuthStatus { .unknown }
    func changeValue(_ value: Int) { self.value = value }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        return ProviderSnapshot(providerID: id, displayName: displayName, authStatus: .unknown,
                                todayUsage: TokenUsage(inputTokens: value, confidence: .localParsed),
                                weekUsage: .unavailable)
    }
}

/// Both the clock and sleepers advance from the test; wall-clock sleeps never
/// stand in for fifteen seconds. Cancellation removes each abandoned deadline.
private final class RefreshClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: TimeInterval = 0
    private var waits: [UUID: (TimeInterval, CheckedContinuation<Void, Error>)] = [:]
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: instant) } }
    func hasDeadline(_ deadline: TimeInterval) -> Bool { lock.withLock { waits.values.contains { $0.0 == deadline } } }
    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else { waits[id] = (instant + interval, continuation) }
                }
            }
        }, onCancel: { self.cancel(id) })
    }
    private func cancel(_ id: UUID) {
        let continuation = lock.withLock { waits.removeValue(forKey: id)?.1 }
        continuation?.resume(throwing: CancellationError())
    }
    func advance(to value: TimeInterval) {
        let ready = lock.withLock {
            instant = value
            let ids = waits.keys.filter { waits[$0]!.0 <= instant }
            return ids.compactMap { waits.removeValue(forKey: $0)?.1 }
        }
        for continuation in ready { continuation.resume() }
    }
}
