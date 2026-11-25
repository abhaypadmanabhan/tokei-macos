import XCTest
@testable import AIUsageDashboardCore

// MARK: - GitHub billing (Copilot)

final class CopilotBillingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OfficialStubProtocol.reset()
    }

    private let userPath = "/user"
    private let premiumPath = "/users/octo-test/settings/billing/premium_request/usage"
    private let creditPath = "/users/octo-test/settings/billing/ai_credit/usage"

    func testParsesPremiumRequestReport() throws {
        let parsed = try CopilotBillingParser.meter(kind: .premiumRequests, from: OfficialFixtures.premiumRequests)
        XCTAssertEqual(parsed.year, 2026)
        XCTAssertEqual(parsed.month, 11)
        XCTAssertEqual(parsed.meter.itemCount, 2)
        XCTAssertEqual(parsed.meter.grossQuantity, 312)
        XCTAssertEqual(parsed.meter.discountQuantity, 300)
        XCTAssertEqual(parsed.meter.netQuantity, 12)
        XCTAssertEqual(parsed.meter.netAmount, 0.48, accuracy: 0.0001)
    }

    func testWindowsReportCountsWithoutInventingAPercent() throws {
        let meter = try CopilotBillingParser.meter(kind: .premiumRequests, from: OfficialFixtures.premiumRequests).meter
        let usage = CopilotBillingUsage(year: 2026, month: 11, meters: [meter])
        let windows = CopilotBillingParser.quotaWindows(from: usage, observedAt: officialFixedNow)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(window.type, .credits)
        XCTAssertEqual(window.used, 312)
        XCTAssertNil(window.limit)
        XCTAssertNil(UtilizationEngine.usedPercent(from: window))
        XCTAssertTrue(window.isInformationalCredits, "a count is never a ceiling for alerts or routing")
        XCTAssertNil(Utilization(window: window, providerID: .copilot))
        XCTAssertEqual(window.resetAt, ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z"))
        let cost = try XCTUnwrap(CopilotBillingParser.billedCost(from: usage))
        XCTAssertEqual(cost.amount ?? -1, 0.48, accuracy: 0.0001)
        XCTAssertEqual(cost.confidence, .providerReported)
    }

    func testClientResolvesLoginAndUsesOfficialHeaders() async throws {
        OfficialStubProtocol.stubs[userPath] = .init(status: 200, body: OfficialFixtures.githubUser)
        OfficialStubProtocol.stubs[premiumPath] = .init(status: 200, body: OfficialFixtures.premiumRequests)
        OfficialStubProtocol.stubs[creditPath] = .init(status: 404, body: Data())
        let client = CopilotBillingClient(
            urlSession: officialStubSession(), cooldownURL: officialCooldownURL(), now: { officialFixedNow }
        )
        let usage = try await client.fetchUsage(token: officialFakeGitHubToken)

        XCTAssertEqual(usage.meters.map(\.kind), [.premiumRequests], "a 404 meter is simply absent")
        XCTAssertEqual(OfficialStubProtocol.requests.compactMap(\.url?.path), [userPath, premiumPath, creditPath])
        for request in OfficialStubProtocol.requests {
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(officialFakeGitHubToken)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2026-03-10")
        }
    }

    func testInvalidTokenIs401() async {
        OfficialStubProtocol.stubs[userPath] = .init(status: 401, body: Data())
        let client = CopilotBillingClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        await assertOfficialError(.unauthorized) { _ = try await client.fetchUsage(token: officialFakeGitHubToken) }
    }

    func testOrgSeatOrMissingPermissionIs403() async {
        OfficialStubProtocol.stubs[userPath] = .init(status: 200, body: OfficialFixtures.githubUser)
        let refusal = Data(#"{"message":"Resource not accessible"}"#.utf8)
        OfficialStubProtocol.stubs[premiumPath] = .init(status: 403, body: refusal)
        let client = CopilotBillingClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        await assertOfficialError(.forbidden(message: nil)) {
            _ = try await client.fetchUsage(token: officialFakeGitHubToken)
        }
    }

    func testGitHubRateLimit403IsARateLimitNotAPermissionError() async {
        OfficialStubProtocol.stubs[userPath] = .init(
            status: 403, body: Data(),
            headers: [
                "x-ratelimit-remaining": "0",
                "x-ratelimit-reset": String(Int(officialFixedNow.timeIntervalSince1970) + 900)
            ]
        )
        let client = CopilotBillingClient(
            urlSession: officialStubSession(),
            cooldownURL: officialCooldownURL(),
            now: { officialFixedNow },
            sleep: { _ in }
        )
        await assertOfficialError(.rateLimited(retryAfter: 900)) {
            _ = try await client.fetchUsage(token: officialFakeGitHubToken)
        }
    }

    func testEmptyReportsReadAsNoPersonalUsage() async throws {
        OfficialStubProtocol.stubs[userPath] = .init(status: 200, body: OfficialFixtures.githubUser)
        OfficialStubProtocol.stubs[premiumPath] = .init(status: 200, body: OfficialFixtures.emptyUsage)
        OfficialStubProtocol.stubs[creditPath] = .init(status: 200, body: OfficialFixtures.emptyUsage)
        let client = CopilotBillingClient(urlSession: officialStubSession(), cooldownURL: officialCooldownURL())
        let usage = try await client.fetchUsage(token: officialFakeGitHubToken)
        XCTAssertTrue(usage.isEmpty)
        XCTAssertTrue(CopilotBillingParser.quotaWindows(from: usage, observedAt: officialFixedNow).isEmpty)
        XCTAssertNil(CopilotBillingParser.billedCost(from: usage))
    }

    func testLoginMustBeAValidHandle() {
        XCTAssertThrowsError(try CopilotBillingParser.login(from: Data(#"{"login":"../../orgs/x"}"#.utf8)))
        XCTAssertEqual(try? CopilotBillingParser.login(from: OfficialFixtures.githubUser), "octo-test")
    }

    // MARK: Provider

    func testProviderMakesNoRequestWhenSwitchIsOff() async throws {
        let (defaults, suite) = try officialIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = CountingBillingClient(.failure(.unexpectedResponse))
        let store = InMemorySecretStore([OfficialSignIn.githubBilling.keychainAccount: officialFakeGitHubToken])
        let provider = makeProvider(client: client, store: store, defaults: defaults)
        let snapshot = try await provider.fetchSnapshot()
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testProviderWithSwitchOnButNoTokenSaysSo() async throws {
        let (defaults, suite) = try officialIsolatedDefaults([OfficialSignIn.githubBilling.liveEnabledKey: true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = CountingBillingClient(.failure(.unexpectedResponse))
        let provider = makeProvider(client: client, store: InMemorySecretStore(), defaults: defaults)
        let snapshot = try await provider.fetchSnapshot()
        let calls = await client.calls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(snapshot.warnings.contains { $0.message.contains("no GitHub token is saved") })
    }

    func testProviderPublishesBillingWithSavedToken() async throws {
        let (defaults, suite) = try officialIsolatedDefaults([OfficialSignIn.githubBilling.liveEnabledKey: true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let meter = try CopilotBillingParser.meter(kind: .premiumRequests, from: OfficialFixtures.premiumRequests).meter
        let client = CountingBillingClient(.success(CopilotBillingUsage(year: 2026, month: 11, meters: [meter])))
        let provider = makeProvider(
            client: client,
            store: InMemorySecretStore([OfficialSignIn.githubBilling.keychainAccount: officialFakeGitHubToken]),
            defaults: defaults
        )
        let snapshot = try await provider.fetchSnapshot()
        let token = await client.lastToken
        XCTAssertEqual(token, officialFakeGitHubToken)
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.quotaWindows.map(\.used), [312])
        XCTAssertEqual(snapshot.costUsage?.amount ?? -1, 0.48, accuracy: 0.0001)
        XCTAssertEqual(snapshot.costUsage?.confidence, .providerReported)
        XCTAssertFalse(snapshot.warnings.contains { $0.message.contains(officialFakeGitHubToken) })
    }

    func testProviderWarnsAboutOrgSeatsWhenPersonalBillingIsEmpty() async throws {
        let (defaults, suite) = try officialIsolatedDefaults([OfficialSignIn.githubBilling.liveEnabledKey: true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let empty = try CopilotBillingParser.meter(kind: .premiumRequests, from: OfficialFixtures.emptyUsage).meter
        let client = CountingBillingClient(.success(CopilotBillingUsage(year: 2026, month: 11, meters: [empty])))
        let provider = makeProvider(
            client: client,
            store: InMemorySecretStore([OfficialSignIn.githubBilling.keychainAccount: officialFakeGitHubToken]),
            defaults: defaults
        )
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.message.contains("organization or enterprise") })
    }

    func testProviderWords401And403() {
        XCTAssertTrue(CopilotProvider.billingWarning(for: OfficialUsageError.unauthorized).message.contains("(401)"))
        let forbidden = CopilotProvider.billingWarning(for: OfficialUsageError.forbidden(message: nil)).message
        XCTAssertTrue(forbidden.contains("Plan: Read"))
        XCTAssertTrue(forbidden.contains("organization or enterprise"))
    }

    private func makeProvider(
        client: CountingBillingClient, store: InMemorySecretStore, defaults: UserDefaults
    ) -> CopilotProvider {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("no-copilot-\(UUID().uuidString)")
        return CopilotProvider(
            installationMarkers: [],
            extensionDirectories: [],
            sessionParser: CopilotSessionParser(sessionStateDirectory: root),
            now: { officialFixedNow },
            billingClient: client,
            secretStore: store,
            userDefaults: defaults
        )
    }
}

// MARK: - Settings metadata

final class OfficialSignInMetadataTests: XCTestCase {
    func testSignInsAreOffByDefaultAndUseDistinctKeychainAccounts() {
        XCTAssertEqual(OfficialSignIn.githubBilling.keychainAccount, "github.billing.token")
        XCTAssertEqual(OfficialSignIn.opencodeGo.keychainAccount, "opencode.go.apiKey")
        XCTAssertEqual(ProviderMetadata.liveQuotaEnabledKey(for: .copilot), OfficialSignIn.githubBilling.liveEnabledKey)
        XCTAssertEqual(ProviderMetadata.liveQuotaEnabledKey(for: .opencode), OfficialSignIn.opencodeGo.liveEnabledKey)
        for signIn in OfficialSignIn.allCases {
            XCTAssertNil(ProviderMetadata.networkDefaultsOn[signIn.liveEnabledKey], "opt-in: never on by default")
            XCTAssertEqual(OfficialSignIn(providerID: signIn.providerID), signIn)
        }
    }

    func testCopilotHasNoPendingGaugeButOpencodeGoDoes() {
        XCTAssertFalse(ProviderMetadata.showsPendingQuota(for: .copilot))
        XCTAssertTrue(ProviderMetadata.showsPendingQuota(for: .opencode))
    }
}
