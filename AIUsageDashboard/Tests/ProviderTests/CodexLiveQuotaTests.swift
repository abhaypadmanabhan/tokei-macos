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

    private func writeLog(at date: Date, used: Int = 80, individualLimit: Int? = nil) throws {
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: date)
        let spendLimit = individualLimit.map {
            ",\"spend_control\":{\"individual_limit\":{\"used_percent\":\($0)}}"
        } ?? ""
        let row = """
        {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count",
        "info":{"total_token_usage":{"input_tokens":10,"total_tokens":10},
        "last_token_usage":{"input_tokens":10,"total_tokens":10}},
        "rate_limits":{"primary":{"used_percent":\(used),"window_minutes":300,"resets_at":1900000000}\(spendLimit)}}}
        """.replacingOccurrences(of: "\n", with: "")
        try Data(row.utf8).write(to: sessions.appendingPathComponent("session.jsonl"), options: .atomic)
    }

    private func provider(
        probe: LiveQuotaProbe, clock: LiveQuotaClock, responseDelay: TimeInterval = 0
    ) -> CodexProvider {
        let binary = directory!
        let client = CodexRateLimitClient(
            resolveBinary: { binary }, run: { _, _ in
                clock.advance(responseDelay)
                return try await probe.run()
            }, now: { clock.read() }
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
        XCTAssertNil(defaults.object(forKey: CodexProvider.liveQuotaEnabledKey),
                     "Provider must not register app defaults")
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
        let session = newer.accounts?.first?.quotaWindows.first { $0.type == .session }
        XCTAssertEqual(session?.used, 60)
        XCTAssertFalse(session?.source.contains("app-server") ?? true)
    }

    func testIdentityMismatchNeverAttributesAndExplicitOffDoesNotProbe() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        try writeLog(at: clock.read())
        let probe = LiveQuotaProbe()
        await probe.set(live("different-account"))
        let provider = provider(probe: probe, clock: clock)
        let mismatch = try await provider.fetchSnapshot()
        XCTAssertEqual(mismatch.accounts?.first?.quotaWindows.first?.used, 80)
        defaults.set(false, forKey: CodexProvider.liveQuotaEnabledKey)
        clock.advance(301)
        _ = try await provider.fetchSnapshot()
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testRefreshReusesReadingAt299SecondsAndProbesAt300() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        let probe = LiveQuotaProbe()
        await probe.set(live())
        let provider = provider(probe: probe, clock: clock)
        _ = try await provider.fetchSnapshot()
        clock.advance(299)
        _ = try await provider.fetchSnapshot()
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        clock.advance(1)
        _ = try await provider.fetchSnapshot()
        let refreshedCalls = await probe.calls
        XCTAssertEqual(refreshedCalls, 2)
    }

    func testSlowProbeStillReusesReadingFor300SecondsAfterObservation() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        let probe = LiveQuotaProbe()
        await probe.set(live())
        let provider = provider(probe: probe, clock: clock, responseDelay: 5)
        _ = try await provider.fetchSnapshot()
        clock.advance(299)
        _ = try await provider.fetchSnapshot()
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        clock.advance(1)
        _ = try await provider.fetchSnapshot()
        let refreshedCalls = await probe.calls
        XCTAssertEqual(refreshedCalls, 2)
    }

    func testDefaultProviderHasNoCLIClient() throws {
        // Inspect configuration without ever giving the old default a chance to spawn.
        let provider = CodexProvider(userDefaults: defaults)
        let client = try XCTUnwrap(Mirror(reflecting: provider).children.first { $0.label == "liveQuotaClient" })
        let configuration = Mirror(reflecting: client.value)
        XCTAssertEqual(configuration.displayStyle, .optional)
        XCTAssertTrue(configuration.children.isEmpty, "Core must be offline until a client is injected")
    }

    func testLiveWeeklyKeepsTighterLogIndividualLimit() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        try writeLog(at: clock.read().addingTimeInterval(-60), used: 10, individualLimit: 90)
        let probe = LiveQuotaProbe()
        await probe.set(Data("""
        {"accountId":"fixture-account","rateLimits":{"limitId":"codex",
        "primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1900000000},
        "credits":{"balance":"50"}}}
        """.utf8))
        let provider = provider(probe: probe, clock: clock)
        defaults.set(false, forKey: CodexProvider.liveQuotaEnabledKey)
        let logOnly = try await provider.fetchSnapshot()
        XCTAssertEqual(logOnly.accounts?.first?.quotaWindows.first {
            $0.bucketKey == "spend_control_individual_limit"
        }?.used, 90)
        defaults.set(true, forKey: CodexProvider.liveQuotaEnabledKey)
        let snapshot = try await provider.fetchSnapshot()
        let account = try XCTUnwrap(snapshot.accounts?.first)
        XCTAssertEqual(account.quotaWindows.first { $0.type == .weekly }?.used, 20)
        XCTAssertEqual(account.quotaWindows.first { $0.bucketKey == "credits" }?.remaining, 50)
        XCTAssertEqual(account.quotaWindows.first { $0.bucketKey == "spend_control_individual_limit" }?.used, 90)
        let decision = AccountQuotaDecision.evaluate(account, providerID: .codex, now: clock.read())
        XCTAssertEqual(decision.headroomPercent, 10)
    }

    func testFailedProbeIsAlsoLimitedToFiveMinutes() async throws {
        let clock = LiveQuotaClock(Date(timeIntervalSince1970: 1800000000))
        let probe = LiveQuotaProbe()
        let provider = provider(probe: probe, clock: clock)
        _ = try await provider.fetchSnapshot()
        clock.advance(299)
        _ = try await provider.fetchSnapshot()
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        clock.advance(1)
        _ = try await provider.fetchSnapshot()
        let retriedCalls = await probe.calls
        XCTAssertEqual(retriedCalls, 2)
    }

}

private struct LiveQuotaDiscovery: AccountDiscovering {
    let providerID: ProviderID = .codex
    let accounts: [ProviderAccount]
    func discover(context: DiscoveryContext) throws -> [ProviderAccount] { accounts }
}
