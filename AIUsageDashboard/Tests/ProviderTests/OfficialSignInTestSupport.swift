import XCTest
@testable import AIUsageDashboardCore

// Shared fixtures and fakes for the official, opt-in sign-ins: GitHub billing (Copilot) and
// OpenCode Go. Fixture-only: no real tokens, no real Keychain, no live network (every request
// goes through `OfficialStubProtocol`).

let officialFakeGitHubToken = "gho_test_not_a_real_token" // secscan:allow
let officialFakeGoKey = "oc_go_test_not_a_real_key" // secscan:allow

// MARK: - Fixtures (shapes from the official docs, 2026-11-24)

enum OfficialFixtures {
    /// https://opencode.ai/docs/console/go/ usage example.
    static let goUsage = Data("""
    {
      "usage": {
        "rolling": { "status": "ok", "percent": 30, "resetsAt": "2026-11-21T15:00:00.000Z" },
        "weekly": { "status": "rate-limited", "percent": 100, "resetsAt": "2026-11-23T00:00:00.000Z" },
        "monthly": { "status": "ok", "percent": 50, "resetsAt": "2026-12-01T00:00:00.000Z" }
      }
    }
    """.utf8)

    static let goEntitlement = Data("""
    { "type": "error", "error": { "type": "EntitlementError", "message": "OpenCode Go subscription required." } }
    """.utf8)

    static let githubUser = Data(#"{ "login": "octo-test", "id": 1 }"#.utf8)

    /// GitHub `premium_request/usage` schema (docs.github.com/en/rest/billing/usage).
    static let premiumRequests = Data("""
    {
      "timePeriod": { "year": 2026, "month": 11 },
      "user": "octo-test",
      "usageItems": [
        { "product": "Copilot", "sku": "Copilot Premium Request", "model": "Model A", "unitType": "requests",
          "pricePerUnit": 0.04, "grossQuantity": 250, "grossAmount": 10.0, "discountQuantity": 250,
          "discountAmount": 10.0, "netQuantity": 0, "netAmount": 0.0 },
        { "product": "Copilot", "sku": "Copilot Premium Request", "model": "Model B", "unitType": "requests",
          "pricePerUnit": 0.04, "grossQuantity": 62, "grossAmount": 2.48, "discountQuantity": 50,
          "discountAmount": 2.0, "netQuantity": 12, "netAmount": 0.48 }
      ]
    }
    """.utf8)

    static let emptyUsage = Data(
        #"{ "timePeriod": { "year": 2026, "month": 11 }, "user": "octo-test", "usageItems": [] }"#.utf8
    )
}

// MARK: - Stubs

final class OfficialStubProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
        var headers: [String: String] = [:]
    }

    /// Keyed by URL path; a path with no stub fails the request.
    static var stubs: [String: Stub] = [:]
    static var requests: [URLRequest] = []

    static func reset() {
        stubs = [:]
        requests = []
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let url = request.url, let stub = Self.stubs[url.path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

actor InMemorySecretStore: SecretStore {
    private var values: [String: String]
    init(_ values: [String: String] = [:]) { self.values = values }
    func secret(for account: String) -> String? { values[account] }
    func hasSecret(for account: String) -> Bool { values[account] != nil }
    func setSecret(_ secret: String, for account: String) { values[account] = secret }
    func removeSecret(for account: String) { values[account] = nil }
}

actor CountingGoClient: OpencodeGoUsageFetching {
    private(set) var calls = 0
    private(set) var lastKey: String?
    let result: Result<[OpencodeGoMeter], OfficialUsageError>
    init(_ result: Result<[OpencodeGoMeter], OfficialUsageError>) { self.result = result }
    func fetchMeters(apiKey: String) async throws -> [OpencodeGoMeter] {
        calls += 1
        lastKey = apiKey
        return try result.get()
    }
}

actor CountingBillingClient: CopilotBillingFetching {
    private(set) var calls = 0
    private(set) var lastToken: String?
    let result: Result<CopilotBillingUsage, OfficialUsageError>
    init(_ result: Result<CopilotBillingUsage, OfficialUsageError>) { self.result = result }
    func fetchUsage(token: String) async throws -> CopilotBillingUsage {
        calls += 1
        lastToken = token
        return try result.get()
    }
}

func officialStubSession() -> URLSession {
    UsageHTTPSession.make(protocolClasses: [OfficialStubProtocol.self])
}

func officialCooldownURL() -> URL {
    // Own directory: the cooldown writer makes its parent 0700, which the shared temp dir refuses.
    FileManager.default.temporaryDirectory
        .appendingPathComponent("official-signin-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("cooldown.json")
}

func officialIsolatedDefaults(_ values: [String: Any] = [:]) throws -> (UserDefaults, String) {
    let suite = "official.signin.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    for (key, value) in values { defaults.set(value, forKey: key) }
    return (defaults, suite)
}

let officialFixedNow = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!

// MARK: - Helpers

func assertOfficialError(
    _ expected: OfficialUsageError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? OfficialUsageError, expected, file: file, line: line)
    }
}
