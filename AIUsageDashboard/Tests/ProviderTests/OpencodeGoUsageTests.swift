import XCTest
@testable import AIUsageDashboardCore

// MARK: - OpenCode Go

final class OpencodeGoUsageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OfficialStubProtocol.reset()
    }

    func testParsesDocumentedResponseIntoPercentWindows() throws {
        let meters = try OpencodeGoUsageParser.meters(from: OfficialFixtures.goUsage)
        XCTAssertEqual(meters.map(\.kind), [.rolling, .weekly, .monthly])
        XCTAssertEqual(meters.map(\.percent), [30, 100, 50])
        XCTAssertEqual(meters.map(\.isRateLimited), [false, true, false])

        let windows = OpencodeGoUsageParser.quotaWindows(from: meters, observedAt: officialFixedNow)
        XCTAssertEqual(windows.map(\.type), [.fiveHour, .weekly, .monthly])
        XCTAssertEqual(windows.map(\.used), [30, 100, 50])
        XCTAssertEqual(windows.map(\.limit), [100, 100, 100])
        XCTAssertEqual(windows.map(\.remaining), [70, 0, 50])
        XCTAssertEqual(windows[0].resetAt, ISO8601DateFormatter().date(from: "2026-11-21T15:00:00Z"))
        XCTAssertEqual(windows[0].windowDuration, 5 * 60 * 60)
        XCTAssertNil(windows[2].windowDuration, "the docs give no monthly length; do not invent one")
        XCTAssertTrue(windows.allSatisfy { $0.confidence == .providerReported && $0.observedAt == officialFixedNow })
        XCTAssertEqual(windows.compactMap { UtilizationEngine.usedPercent(from: $0) }, [30, 100, 50])
    }

    func testMalformedBodyIsUnexpected() {
        XCTAssertThrowsError(try OpencodeGoUsageParser.meters(from: Data("{}".utf8))) {
            XCTAssertEqual($0 as? OfficialUsageError, .unexpectedResponse)
        }
    }

    func testClientSendsBearerToOfficialEndpoint() async throws {
        OfficialStubProtocol.stubs["/inference/go/v1/usage"] = .init(status: 200, body: OfficialFixtures.goUsage)
        let client = OpencodeGoUsageClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        let meters = try await client.fetchMeters(apiKey: officialFakeGoKey)
        XCTAssertEqual(meters.count, 3)
        let request = try XCTUnwrap(OfficialStubProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/inference/go/v1/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(officialFakeGoKey)")
    }

    func testUnauthorizedIs401() async {
        OfficialStubProtocol.stubs["/inference/go/v1/usage"] = .init(status: 401, body: Data())
        let client = OpencodeGoUsageClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        await assertOfficialError(.unauthorized) { _ = try await client.fetchMeters(apiKey: officialFakeGoKey) }
    }

    func testForbiddenIs403() async {
        OfficialStubProtocol.stubs["/inference/go/v1/usage"] = .init(status: 403, body: OfficialFixtures.goEntitlement)
        let client = OpencodeGoUsageClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        await assertOfficialError(.forbidden) {
            _ = try await client.fetchMeters(apiKey: officialFakeGoKey)
        }
    }

    func testForbiddenDoesNotExposeAnEchoedKey() async {
        let fakeShortKey = UUID().uuidString.prefix(12)
        let body = Data(#"{"error":{"message":"Key \#(fakeShortKey) has no plan"}}"#.utf8)
        OfficialStubProtocol.stubs["/inference/go/v1/usage"] = .init(status: 403, body: body)
        let client = OpencodeGoUsageClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        do {
            _ = try await client.fetchMeters(apiKey: String(fakeShortKey))
            XCTFail("Expected a 403 error")
        } catch {
            let warning = OpencodeProvider.goWarning(for: error).message
            XCTAssertFalse(warning.contains(fakeShortKey))
            XCTAssertTrue(warning.contains("no active Go subscription"))
        }
    }

    func testRateLimitRecordsCooldownAndThenSkipsTheNetwork() async {
        OfficialStubProtocol.stubs["/inference/go/v1/usage"] = .init(
            status: 429, body: Data(), headers: ["Retry-After": "600"]
        )
        let cooldown = officialCooldownURL()
        let client = OpencodeGoUsageClient(urlSession: officialStubSession(), cooldownURL: cooldown, sleep: { _ in })
        await assertOfficialError(.rateLimited(retryAfter: 600)) {
            _ = try await client.fetchMeters(apiKey: officialFakeGoKey)
        }
        XCTAssertEqual(OfficialStubProtocol.requests.count, 1, "a Retry-After over the ceiling gives up at once")
        await assertOfficialError(.cooldownActive) { _ = try await client.fetchMeters(apiKey: officialFakeGoKey) }
        XCTAssertEqual(OfficialStubProtocol.requests.count, 1, "cooldown means no second request")
    }

    // MARK: Provider

    func testProviderMakesNoRequestWhenSwitchIsOff() async throws {
        let (defaults, suite) = try officialIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = CountingGoClient(.success([]))
        let store = InMemorySecretStore([OfficialSignIn.opencodeGo.keychainAccount: officialFakeGoKey])
        let provider = makeProvider(client: client, store: store, defaults: defaults)
        let snapshot = try await provider.fetchSnapshot()
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertFalse(snapshot.warnings.contains { $0.message.hasPrefix("OpenCode Go:") })
    }

    func testProviderWithSwitchOnButNoKeySaysSoAndMakesNoRequest() async throws {
        let (defaults, suite) = try officialIsolatedDefaults([OfficialSignIn.opencodeGo.liveEnabledKey: true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = CountingGoClient(.success([]))
        let provider = makeProvider(client: client, store: InMemorySecretStore(), defaults: defaults)
        let snapshot = try await provider.fetchSnapshot()
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.message.contains("no API key is saved") })
    }

    func testProviderPublishesGoWindowsWithSavedKey() async throws {
        let (defaults, suite) = try officialIsolatedDefaults([OfficialSignIn.opencodeGo.liveEnabledKey: true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let meters = try OpencodeGoUsageParser.meters(from: OfficialFixtures.goUsage)
        let client = CountingGoClient(.success(meters))
        let provider = makeProvider(
            client: client,
            store: InMemorySecretStore([OfficialSignIn.opencodeGo.keychainAccount: officialFakeGoKey]),
            defaults: defaults
        )
        let snapshot = try await provider.fetchSnapshot()
        let key = await client.lastKey
        XCTAssertEqual(key, officialFakeGoKey)
        XCTAssertEqual(snapshot.quotaWindows.map(\.used), [30, 100, 50])
        XCTAssertTrue(snapshot.warnings.contains { $0.message.contains("Go weekly limit is used up") })
        XCTAssertFalse(snapshot.warnings.contains { $0.message.contains(officialFakeGoKey) })
    }

    func testProviderWords401And403() {
        let unauthorized = OpencodeProvider.goWarning(for: OfficialUsageError.unauthorized)
        XCTAssertTrue(unauthorized.message.contains("rejected (401)"))
        let forbidden = OpencodeProvider.goWarning(for: OfficialUsageError.forbidden)
        XCTAssertEqual(forbidden.message, "OpenCode Go: this key has no active Go subscription (403).")
    }

    private func makeProvider(
        client: CountingGoClient, store: InMemorySecretStore, defaults: UserDefaults
    ) -> OpencodeProvider {
        OpencodeProvider(
            opencodeDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("no-opencode-\(UUID().uuidString)"),
            goUsageClient: client,
            secretStore: store,
            userDefaults: defaults,
            now: { officialFixedNow }
        )
    }
}
