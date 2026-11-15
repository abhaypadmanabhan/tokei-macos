import XCTest
@testable import AIUsageDashboardCore

final class QuotaSpawnCadenceTests: XCTestCase {
    @MainActor
    func testManualRefreshRetriesClaudeImmediatelyAfterSignInIsFixed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "tokei.manual.cadence." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claudeNetworkUsageEnabled")
        let client = MissingClaudeQuota()
        let provider = ClaudeCodeProvider(
            accounts: [ClaudeAccount(configDirectory: root.appendingPathComponent(".claude"), home: root)],
            usageClientFactory: { _ in client }, userDefaults: defaults
        )
        let store = UsageStore(directory: root)
        let series = QuotaSeriesStore(directory: root)
        let engine = SyncEngine(registry: ProviderRegistry(providers: [provider]), store: store,
                                quotaSeriesStore: series, agentSnapshotWriter: AgentSnapshotWriter(directory: root),
                                watcher: FileWatcher(paths: []), evaluateThresholds: { _ in })
        let model = DashboardViewModel(syncEngine: engine, store: store,
                                       burnStateStore: BurnStateStore(directory: root), quotaSeriesStore: series,
                                       burnDefaults: defaults, notifyBurn: { _, _ in })
        await model.refresh()
        await client.recover()
        _ = await engine.refreshAll()
        let automatic = await client.calls
        XCTAssertEqual(automatic, 1, "automatic refresh must retain the failed-probe cadence")
        await model.refresh()
        let manual = await client.calls
        XCTAssertEqual(manual, 2, "manual Refresh must retry immediately after sign-in is fixed")
        XCTAssertEqual(model.snapshots.first?.authStatus, .authenticated)
    }

    func testAntigravityLiveReadingWithoutResetTimeCanStayLiveBetweenAttempts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(_ reset: Date?) -> QuotaWindow {
            QuotaWindow(providerID: .antigravity, type: .weekly, used: 10, limit: 100,
                        remaining: 90, resetAt: reset, confidence: .providerReported, source: "fixture")
        }
        XCTAssertTrue(AntigravityQuotaClientImpl.liveWindowsAreCurrent([window(nil)], at: now),
                      "an absent reset time must not downgrade a still-live reading")
        XCTAssertTrue(AntigravityQuotaClientImpl.liveWindowsAreCurrent([window(now.addingTimeInterval(1))], at: now))
        XCTAssertFalse(AntigravityQuotaClientImpl.liveWindowsAreCurrent([window(now)], at: now))
    }

    func testClaudeMissingCredentialsDoNotProbeAgainBeforeTenMinutes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "tokei.cadence." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "claudeNetworkUsageEnabled")
        let clock = CadenceClock()
        let client = MissingClaudeQuota()
        let provider = ClaudeCodeProvider(
            accounts: [ClaudeAccount(configDirectory: root.appendingPathComponent(".claude"), home: root)],
            usageClientFactory: { _ in client }, userDefaults: defaults, now: { clock.now() }
        )
        _ = try await provider.fetchSnapshot()
        clock.advance(by: 15)
        _ = try await provider.fetchSnapshot()
        clock.advance(by: 584)
        _ = try await provider.fetchSnapshot()
        let early = await client.calls
        XCTAssertEqual(early, 1, "a missing credential must not cause repeated subprocess probes")
        clock.advance(by: 1)
        _ = try await provider.fetchSnapshot()
        let due = await client.calls
        XCTAssertEqual(due, 2)
    }

    func testAntigravityFailedDiscoveryRunsAtMostEveryFiveMinutes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = CadenceClock()
        let discoverer = CountingQuotaDiscovery()
        let client = AntigravityQuotaClientImpl(discoverer: discoverer, now: { clock.now() }, cacheDirectory: root)
        _ = try? await client.fetchQuotaWindows()
        clock.advance(by: 15)
        _ = try? await client.fetchQuotaWindows()
        clock.advance(by: 284)
        _ = try? await client.fetchQuotaWindows()
        let early = await discoverer.calls
        XCTAssertEqual(early, 1, "file refreshes must not repeatedly spawn ps and lsof")
        clock.advance(by: 1)
        _ = try? await client.fetchQuotaWindows()
        let due = await discoverer.calls
        XCTAssertEqual(due, 2)
    }
}

private actor MissingClaudeQuota: ClaudeUsageClient {
    var calls = 0
    private var missing = true
    func recover() { missing = false }
    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        calls += 1
        if missing { throw ClaudeUsageError.missingCredentials }
        return [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 10, limit: 100,
                            remaining: 90, resetAt: Date(timeIntervalSince1970: 1_900_000_000),
                            confidence: .providerReported, source: "fixture")]
    }
}

private actor CountingQuotaDiscovery: AntigravityQuotaEndpointDiscovering {
    var calls = 0
    func discoverEndpoint() async -> AntigravityQuotaEndpoint? {
        calls += 1
        return nil
    }
}

private final class CadenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(by seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}
