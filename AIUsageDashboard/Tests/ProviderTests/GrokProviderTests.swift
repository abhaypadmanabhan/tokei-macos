import XCTest
@testable import AIUsageDashboardCore

/// SuperGrok pool via the Grok CLI's billing call. Fixtures are the shapes from
/// xai-org/grok-build `extensions/billing.rs` tests; every key and id here is fake.
final class GrokProviderTests: XCTestCase {
    private var home: URL!
    private var defaults: UserDefaults!
    private let suite = "com.AIUsageDashboard.GrokProviderTests"
    private let now = Date(timeIntervalSince1970: 1_780_000_000) // 2026-05-28

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        GrokStubProtocol.reset()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: home)
        GrokStubProtocol.reset()
        super.tearDown()
    }

    // MARK: - Billing decode

    static let creditsBody = """
    {"config":{"creditUsagePercent":7.25,
      "currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-06-01T00:00:00Z","end":"2026-06-08T00:00:00Z"},
      "onDemandCap":{"val":5000},"onDemandUsed":{"val":300},"isUnifiedBillingUser":true,
      "productUsage":[{"product":"PRODUCT_GROK_BUILD","usagePercent":61.2}]},
     "subscription_tier":"SuperGrok"}
    """

    func testCreditsShapeBecomesOneWeeklySharedPoolWindow() throws {
        let summary = try XCTUnwrap(GrokBillingSummary.decode(Data(Self.creditsBody.utf8)))
        XCTAssertEqual(summary.usedPercent, 7.25)
        XCTAssertEqual(summary.subscriptionTier, "SuperGrok")
        XCTAssertEqual(summary.isUnifiedPool, true)

        let windows = summary.quotaWindows(observedAt: now)
        XCTAssertEqual(windows.count, 1)
        let pool = try XCTUnwrap(windows.first)
        XCTAssertEqual(pool.providerID, .grok)
        XCTAssertEqual(pool.type, .weekly)
        XCTAssertEqual(pool.used, 7.25)
        XCTAssertEqual(pool.remaining, 92.75)
        XCTAssertEqual(pool.limit, 100)
        XCTAssertEqual(pool.bucketKey, "supergrok_pool")
        XCTAssertEqual(pool.label, "SuperGrok pool")
        XCTAssertEqual(pool.resetAt, ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
        XCTAssertEqual(pool.windowDuration, 7 * 24 * 3600)
        XCTAssertEqual(pool.observedAt, now)
        XCTAssertEqual(pool.confidence, .providerReported)
    }

    func testLegacyCentsShapeFallsBackToUsedOverLimit() throws {
        let body = """
        {"config":{"monthlyLimit":{"val":2000},"used":{"val":500},
          "billingPeriodStart":"2025-04-01T00:00:00Z","billingPeriodEnd":"2025-05-01T00:00:00Z"}}
        """
        let summary = try XCTUnwrap(GrokBillingSummary.decode(Data(body.utf8)))
        XCTAssertEqual(summary.usedPercent, 25)
        XCTAssertEqual(summary.periodType, .monthly)
        XCTAssertEqual(summary.periodEnd, ISO8601DateFormatter().date(from: "2025-05-01T00:00:00Z"))
        XCTAssertEqual(summary.quotaWindows(observedAt: now).first?.label, "Grok Build credits")
        XCTAssertNotEqual(summary.quotaWindows(observedAt: now).first?.bucketKey, SharedQuotaPool.superGrokBucketKey)
    }

    func testNonUnifiedCreditsDoNotReplaceCursorSuperUsage() throws {
        let body = #"{"config":{"creditUsagePercent":25,"isUnifiedBillingUser":false}}"#
        let summary = try XCTUnwrap(GrokBillingSummary.decode(Data(body.utf8)))
        let grokWindows = summary.quotaWindows(observedAt: now)
        let cursor = CursorUsageSummary(usedPercent: 7, resetAt: nil, membershipType: "super")
        let cursorWindows = cursor.quotaWindows(observedAt: now)
        let snapshots = [(ProviderID.grok, grokWindows), (.cursor, cursorWindows)].map { provider, windows in
            ProviderSnapshot(providerID: provider, displayName: provider.rawValue, authStatus: .authenticated,
                             quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable)
        }
        XCTAssertEqual(cursorWindows.first?.bucketKey, SharedQuotaPool.superGrokBucketKey)
        XCTAssertEqual(SharedQuotaPool.deduplicated(snapshots).flatMap(\.quotaWindows).compactMap(\.used), [25, 7])
    }

    func testCreditsShapeWithOmittedZeroPercentReadsAsZero() throws {
        // proto3 JSON drops zero scalars, so an unused pool arrives without the percent.
        let body = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"},"isUnifiedBillingUser":true}}"#
        XCTAssertEqual(GrokBillingSummary.decode(Data(body.utf8))?.usedPercent, 0)
    }

    func testNullOrUnusableConfigYieldsNoWindow() {
        XCTAssertNil(GrokBillingSummary.decode(Data(#"{"config":null}"#.utf8)))
        XCTAssertNil(GrokBillingSummary.decode(Data("not json".utf8)))
        let empty = GrokBillingSummary.decode(Data(#"{"config":{"onDemandCap":{"val":5}}}"#.utf8))
        XCTAssertNil(empty?.usedPercent)
        XCTAssertEqual(empty?.quotaWindows(observedAt: now).count, 0)
    }

    func testPercentIsClampedToGauge() {
        let body = #"{"config":{"creditUsagePercent":140}}"#
        XCTAssertEqual(GrokBillingSummary.decode(Data(body.utf8))?.usedPercent, 100)
    }

    // MARK: - Login selection

    func testLoginPrefersTheCLIDefaultScopeAndSkipsUnusableEntries() throws {
        let store = """
        {"https://accounts.x.ai/sign-in":{"key":"legacy-key","user_id":"u-legacy","auth_mode":"web_login"},
         "xai::api_key":{"key":"api-key","user_id":"u-api","auth_mode":"api_key"},
         "https://other.example::x":{"key":"other-key","auth_mode":"oidc"},
         "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"fake-key","user_id":"u-fake",
           "auth_mode":"oidc","expires_at":"2026-06-20T10:11:12.123456789Z"}}
        """
        let login = try XCTUnwrap(GrokLogin.select(fromAuthStore: Data(store.utf8)))
        XCTAssertEqual(login.key, "fake-key")
        XCTAssertEqual(login.userID, "u-fake")
        let whole = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-20T10:11:12Z"))
        let expected = whole.timeIntervalSince1970 + 0.123
        XCTAssertEqual(try XCTUnwrap(login.expiresAt).timeIntervalSince1970, expected, accuracy: 0.001)
        XCTAssertFalse("\(login)".contains("fake-key"))
    }

    func testLoginIgnoresWebLoginAndAPIKeyOnly() {
        let store = """
        {"https://accounts.x.ai/sign-in":{"key":"k","user_id":"u","auth_mode":"web_login"},
         "xai::api_key":{"key":"k2","user_id":"u2","auth_mode":"api_key"}}
        """
        XCTAssertNil(GrokLogin.select(fromAuthStore: Data(store.utf8)))
        XCTAssertNil(GrokLogin.select(fromAuthStore: Data("[]".utf8)))
    }

    // MARK: - Client

    func testClientSendsTheCLIHeadersToTheBillingURL() async throws {
        try writeAuth(expiresAt: "2026-06-20T00:00:00Z")
        try Data(#"{"version":"1.0.92"}"#.utf8).write(to: home.appendingPathComponent("version.json"))
        GrokStubProtocol.response = (Data(Self.creditsBody.utf8), 200)

        let body = try await makeClient().fetchBilling()

        XCTAssertNotNil(GrokBillingSummary.decode(body))
        let request = try XCTUnwrap(GrokStubProtocol.requests.first)
        XCTAssertEqual(request.url, URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-userid"), "u-fake")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-version"), "1.0.92")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testExpiredLoginIsReportedWithoutAnyRequest() async throws {
        try writeAuth(expiresAt: "2026-05-01T00:00:00Z")
        do {
            _ = try await makeClient().fetchBilling()
            XCTFail("expected loginExpired")
        } catch let error as GrokBillingError {
            XCTAssertEqual(error, .loginExpired)
        }
        XCTAssertTrue(GrokStubProtocol.requests.isEmpty)
    }

    func testForeignIssuerLoginNeverSendsARequest() async throws {
        let entry = #"""
        {"key":"fixture-key","user_id":"fixture-user","auth_mode":"oidc","oidc_issuer":"https://login.example.invalid"}
        """#
        let stores = ["https://login.example.invalid::example", GrokLogin.preferredScope]
        for scope in stores {
            try Data("{\"\(scope)\":\(entry)}".utf8).write(to: home.appendingPathComponent("auth.json"))
            GrokStubProtocol.response = (Data(Self.creditsBody.utf8), 200)
            do {
                _ = try await makeClient().fetchBilling()
                XCTFail("expected notSignedIn")
            } catch let error as GrokBillingError {
                XCTAssertEqual(error, .notSignedIn)
            }
        }
        XCTAssertTrue(GrokStubProtocol.requests.isEmpty)
    }

    func testRateLimitRecordsCooldownAndTheNextCallStaysOffline() async throws {
        try writeAuth(expiresAt: "2026-06-20T00:00:00Z")
        GrokStubProtocol.response = (Data(), 429)
        let client = makeClient()
        do { _ = try await client.fetchBilling(); XCTFail("expected rate limit") } catch {}
        let sent = GrokStubProtocol.requests.count
        do {
            _ = try await client.fetchBilling()
            XCTFail("expected cooldown")
        } catch let error as GrokBillingError {
            XCTAssertEqual(error, .cooldownActive)
        }
        XCTAssertEqual(GrokStubProtocol.requests.count, sent)
    }

    // MARK: - Provider

    func testProviderIsOffUntilTheToggleIsOn() async throws {
        try writeAuth(expiresAt: "2026-06-20T00:00:00Z")
        let snapshot = try await makeProvider(client: FixedGrokClient(result: .success(Data(Self.creditsBody.utf8))))
            .fetchSnapshot()
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.warnings.first?.level, .info)
    }

    func testProviderPublishesThePoolAndPlan() async throws {
        try writeAuth(expiresAt: "2026-06-20T00:00:00Z")
        defaults.set(true, forKey: GrokProvider.networkUsageEnabledKey)
        let snapshot = try await makeProvider(client: FixedGrokClient(result: .success(Data(Self.creditsBody.utf8))))
            .fetchSnapshot()
        XCTAssertEqual(snapshot.providerID, .grok)
        XCTAssertEqual(snapshot.quotaWindows.map(\.used), [7.25])
        XCTAssertEqual(snapshot.quotaWindows.map(\.bucketKey), ["supergrok_pool"])
        XCTAssertEqual(snapshot.warnings.map(\.message), ["Plan: SuperGrok"])
    }

    func testProviderWithoutLoginFileIsSignedOut() async throws {
        defaults.set(true, forKey: GrokProvider.networkUsageEnabledKey)
        let provider = makeProvider(client: FixedGrokClient(result: .failure(GrokBillingError.notSignedIn)))
        let availability = await provider.detectAvailability()
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(availability, .notInstalled)
        XCTAssertEqual(snapshot.authStatus, .unauthenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testProviderTurnsFailuresIntoWarningsNotWindows() async throws {
        try writeAuth(expiresAt: "2026-06-20T00:00:00Z")
        defaults.set(true, forKey: GrokProvider.networkUsageEnabledKey)
        let expired = try await makeProvider(client: FixedGrokClient(result: .failure(GrokBillingError.loginExpired)))
            .fetchSnapshot()
        XCTAssertEqual(expired.authStatus, .unauthenticated)
        XCTAssertTrue(expired.warnings.contains { $0.message.contains("expired") })

        let rejectedClient = FixedGrokClient(result: .failure(GrokBillingError.httpStatus(401)))
        let rejected = try await makeProvider(client: rejectedClient).fetchSnapshot()
        XCTAssertTrue(rejected.quotaWindows.isEmpty)
        XCTAssertTrue(rejected.warnings.contains { $0.message.contains("HTTP 401") })
    }

    // MARK: - Helpers

    private func writeAuth(expiresAt: String) throws {
        let store = """
        {"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":
          {"key":"fake-key","user_id":"u-fake","auth_mode":"oidc","expires_at":"\(expiresAt)"}}
        """
        try Data(store.utf8).write(to: home.appendingPathComponent("auth.json"))
    }

    private func makeClient() -> GrokBillingClientImpl {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokStubProtocol.self]
        let fixedNow = now
        return GrokBillingClientImpl(
            grokHome: home, urlSession: URLSession(configuration: configuration),
            cooldownURL: home.appendingPathComponent("cooldown.json"), now: { fixedNow }, sleep: { _ in }
        )
    }

    private func makeProvider(client: any GrokBillingClient) -> GrokProvider {
        let fixedNow = now
        return GrokProvider(grokHome: home, client: client, now: { fixedNow }, userDefaults: defaults)
    }
}

private struct FixedGrokClient: GrokBillingClient {
    let result: Result<Data, GrokBillingError>
    func fetchBilling() async throws -> Data { try result.get() }
}

private final class GrokStubProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (Data, Int)?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        response = nil
        requests = []
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let (data, status) = Self.response, let url = request.url,
              let http = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
