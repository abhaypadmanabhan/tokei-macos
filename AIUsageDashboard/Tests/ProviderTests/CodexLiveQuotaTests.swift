import XCTest
@testable import AIUsageDashboardCore

private actor LiveQuotaProbe {
    var calls = 0
    var data: Data?
    func set(_ data: Data?) { self.data = data }
    func run() throws -> Data {
        calls += 1
        guard let data else { throw CocoaError(.fileReadUnknown) }
        return data
    }
}

private final class LiveQuotaClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date += seconds; lock.unlock() }
}

final class CodexLiveQuotaTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "wp2.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func live(_ account: String = "fixture-account", used: Int = 30) -> Data {
        Data("""
        {"accountId":"\(account)","rateLimits":{"limitId":"codex",
        "primary":{"usedPercent":\(used),"windowDurationMins":300,"resetsAt":1900000000},
        "secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1900000000}}}
        """.utf8)
    }

    private func writeLog(at date: Date, used: Int = 80) throws {
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: date)
        let row = """
        {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count",
        "info":{"total_token_usage":{"input_tokens":10,"total_tokens":10},
        "last_token_usage":{"input_tokens":10,"total_tokens":10}},
        "rate_limits":{"primary":{"used_percent":\(used),"window_minutes":300,"resets_at":1900000000}}}}
        """.replacingOccurrences(of: "\n", with: "")
        try Data(row.utf8).write(to: sessions.appendingPathComponent("session.jsonl"), options: .atomic)
    }

    private func provider(probe: LiveQuotaProbe, clock: LiveQuotaClock) -> CodexProvider {
        let binary = directory!
        let client = CodexRateLimitClient(
            resolveBinary: { binary }, run: { _, _ in try await probe.run() }, now: { clock.read() }
        )
        let account = ProviderAccountNormalizer.normalize(providerID: .codex, candidates: [.init(
            root: directory, label: "fixture", quotaIdentity: "fixture-account", selector: nil
        )])
        return CodexProvider(
            codexDirectory: directory, environment: [:], discoverer: LiveQuotaDiscovery(accounts: account),
            now: { clock.read() }, liveQuotaClient: client, userDefaults: defaults
        )
    }

    func testDefaultOnLiveWinsFailureKeepsBarsAndNewerLogWins() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        try writeLog(at: clock.read().addingTimeInterval(-4200))
        let probe = LiveQuotaProbe()
        await probe.set(live())
        let provider = provider(probe: probe, clock: clock)
        XCTAssertTrue(defaults.bool(forKey: "codexLiveQuotaEnabled"))
        let first = try await provider.fetchSnapshot()
        XCTAssertEqual(first.accounts?.first?.quotaWindows.first?.used, 30)
        XCTAssertEqual(first.accounts?.first?.quotaStatus, .eligible)
        XCTAssertEqual(first.quotaWindows.first?.source, "Codex app-server account/rateLimits/read")
        let publicSnapshot = AgentSnapshotWriter.buildSnapshot(from: [first], generatedAt: clock.read())
        XCTAssertEqual(publicSnapshot.providers.first?.accounts?.first?.quota?.status, "eligible")
        await probe.set(nil)
        clock.advance(301)
        let failed = try await provider.fetchSnapshot()
        XCTAssertEqual(failed.accounts?.first?.quotaWindows.first?.used, 30)
        XCTAssertEqual(failed.accounts?.first?.quotaWindows.first?.observedAt, first.quotaWindows.first?.observedAt)
        try writeLog(at: clock.read(), used: 60)
        clock.advance(301)
        let newer = try await provider.fetchSnapshot()
        XCTAssertEqual(newer.accounts?.first?.quotaWindows.first?.used, 60)
        XCTAssertFalse(newer.accounts?.first?.quotaWindows.first?.source.contains("app-server") ?? true)
    }

    func testIdentityMismatchNeverAttributesAndExplicitOffDoesNotProbe() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        try writeLog(at: clock.read())
        let probe = LiveQuotaProbe()
        await probe.set(live("different-account"))
        let provider = provider(probe: probe, clock: clock)
        let mismatch = try await provider.fetchSnapshot()
        XCTAssertEqual(mismatch.accounts?.first?.quotaWindows.first?.used, 80)
        defaults.set(false, forKey: "codexLiveQuotaEnabled")
        clock.advance(301)
        _ = try await provider.fetchSnapshot()
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testSubsequentRefreshObtainsFreshObservation() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        let probe = LiveQuotaProbe()
        await probe.set(live())
        let provider = provider(probe: probe, clock: clock)
        _ = try await provider.fetchSnapshot()
        clock.advance(299)
        _ = try await provider.fetchSnapshot()
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
        clock.advance(1)
        _ = try await provider.fetchSnapshot()
        let refreshedCalls = await probe.calls
        XCTAssertEqual(refreshedCalls, 3)
    }
}

private struct LiveQuotaDiscovery: AccountDiscovering {
    let providerID: ProviderID = .codex
    let accounts: [ProviderAccount]
    func discover(context: DiscoveryContext) throws -> [ProviderAccount] { accounts }
}
