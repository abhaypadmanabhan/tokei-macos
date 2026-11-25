import XCTest
@testable import AIUsageDashboardCore

/// Cursor Super and SuperGrok spend one pool: it must count once in totals, route,
/// burn and the agent snapshot, whichever providers report it.
final class SharedQuotaPoolTests: XCTestCase {
    // Real clock: the agent snapshot judges freshness against the wall clock.
    private let now = Date()

    private func pool(_ provider: ProviderID, used: Double, observedAt: Date? = nil) -> QuotaWindow {
        QuotaWindow(providerID: provider, type: .weekly, used: used, limit: 100, remaining: 100 - used,
                    resetAt: now.addingTimeInterval(3 * 86_400), confidence: .providerReported, source: "fixture",
                    label: SharedQuotaPool.superGrokLabel, bucketKey: SharedQuotaPool.superGrokBucketKey,
                    observedAt: observedAt ?? now, windowDuration: 7 * 86_400)
    }

    private func plain(_ provider: ProviderID, used: Double) -> QuotaWindow {
        QuotaWindow(providerID: provider, type: .fiveHour, used: used, limit: 100, remaining: 100 - used,
                    resetAt: now.addingTimeInterval(3600), confidence: .providerReported, source: "fixture",
                    observedAt: now, windowDuration: 5 * 3600)
    }

    private func snapshot(_ provider: ProviderID, _ windows: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerID: provider, displayName: provider.rawValue, authStatus: .authenticated,
                         quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable)
    }

    private var bothReportThePool: [ProviderSnapshot] {
        [snapshot(.claudeCode, [plain(.claudeCode, used: 50)]),
         snapshot(.cursor, [pool(.cursor, used: 7)]),
         snapshot(.grok, [pool(.grok, used: 7)])]
    }

    func testPoolReportedByCursorAndGrokIsKeptOnceUnderGrok() {
        let result = SharedQuotaPool.deduplicated(bothReportThePool)
        let poolHolders = result.filter { $0.quotaWindows.contains { $0.bucketKey == "supergrok_pool" } }
        XCTAssertEqual(poolHolders.map(\.providerID), [.grok])
        let cursor = try? XCTUnwrap(result.first { $0.providerID == .cursor })
        XCTAssertEqual(cursor?.quotaWindows.count, 0)
        XCTAssertTrue(cursor?.warnings.contains { $0.message.contains("shared with Grok") } ?? false)
        XCTAssertEqual(result.map(\.providerID), [.claudeCode, .cursor, .grok])
    }

    func testAggregateAndRouteCountThePoolOnce() throws {
        let deduplicated = SharedQuotaPool.deduplicated(bothReportThePool)
        // Mean of per-provider peaks: (50 + 7) / 2, not (50 + 7 + 7) / 3.
        let aggregate = try XCTUnwrap(UtilizationEngine.aggregate(from: deduplicated))
        XCTAssertEqual(aggregate.usedPercent, 28.5, accuracy: 0.001)
        XCTAssertEqual(aggregate.coveredProviders, [.claudeCode, .grok])

        let route = RoutePlan.make(snapshots: deduplicated, now: now)
        XCTAssertEqual(route.rows.filter { $0.windowLabel == SharedQuotaPool.superGrokLabel }.count, 1)
        XCTAssertFalse(route.rows.contains { $0.providerID == .cursor })

        let expiring = ExpiringHeadroomFinder.find(in: deduplicated, now: now)
        XCTAssertLessThanOrEqual(expiring.filter { $0.providerID == .cursor || $0.providerID == .grok }.count, 1)
    }

    func testCursorKeepsThePoolWhenGrokHasNoReading() {
        let snapshots = [snapshot(.cursor, [pool(.cursor, used: 7)]), snapshot(.grok, [])]
        let result = SharedQuotaPool.deduplicated(snapshots)
        XCTAssertEqual(result.first { $0.providerID == .cursor }?.quotaWindows.count, 1)
        XCTAssertTrue(result.allSatisfy { $0.warnings.isEmpty })
    }

    func testWithoutTheOwnerTheFreshestReadingWins() {
        let older = snapshot(.cursor, [pool(.cursor, used: 6, observedAt: now.addingTimeInterval(-600))])
        let newer = snapshot(.codex, [pool(.codex, used: 7, observedAt: now)])
        let result = SharedQuotaPool.deduplicated([older, newer])
        XCTAssertEqual(result.filter { !$0.quotaWindows.isEmpty }.map(\.providerID), [.codex])
    }

    func testIsIdempotentAndLeavesOtherWindowsAlone() {
        let once = SharedQuotaPool.deduplicated(bothReportThePool)
        let twice = SharedQuotaPool.deduplicated(once)
        XCTAssertEqual(twice.map { $0.quotaWindows.map(\.id) }, once.map { $0.quotaWindows.map(\.id) })
        XCTAssertEqual(twice.map { $0.warnings.count }, once.map { $0.warnings.count })
        XCTAssertEqual(twice.first { $0.providerID == .claudeCode }?.quotaWindows.map(\.used), [50])
    }

    /// The wiring: a real sync writes an agent snapshot whose aggregate counts the pool once.
    func testSyncEngineWritesTheAgentSnapshotWithThePoolOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = bothReportThePool
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: fixtures.map(FixedSnapshotProvider.init)),
            store: UsageStore(directory: directory), quotaSeriesStore: QuotaSeriesStore(directory: directory),
            agentSnapshotWriter: AgentSnapshotWriter(directory: directory),
            watcher: FileWatcher(paths: [directory]), evaluateThresholds: { _ in }, sleep: { _ in }
        )
        let snapshots = await engine.refreshAll()
        XCTAssertEqual(snapshots.flatMap(\.quotaWindows).filter { $0.bucketKey == "supergrok_pool" }.count, 1)

        let data = try Data(contentsOf: directory.appendingPathComponent("agent-snapshot.json"))
        let agent = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)
        XCTAssertEqual(agent.providers.flatMap(\.windows).filter { $0.bucketKey == "supergrok_pool" }.count, 1)
        XCTAssertEqual(try XCTUnwrap(agent.aggregateUtilizationPercent), 28.5, accuracy: 0.001)
    }
}

private actor FixedSnapshotProvider: UsageProvider {
    nonisolated let id: ProviderID
    nonisolated let displayName: String
    nonisolated let capabilities: ProviderCapabilities = [.quota]
    private let snapshot: ProviderSnapshot

    init(_ snapshot: ProviderSnapshot) {
        self.snapshot = snapshot
        self.id = snapshot.providerID
        self.displayName = snapshot.displayName
    }

    func detectAvailability() async -> ProviderAvailability { .installed }
    func authenticate() async throws -> AuthStatus { .authenticated }
    func fetchSnapshot() async throws -> ProviderSnapshot { snapshot }
}
