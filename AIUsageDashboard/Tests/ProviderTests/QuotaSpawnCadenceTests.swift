import XCTest
@testable import AIUsageDashboardCore

final class QuotaSpawnCadenceTests: XCTestCase {
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
    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        calls += 1
        throw ClaudeUsageError.missingCredentials
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
