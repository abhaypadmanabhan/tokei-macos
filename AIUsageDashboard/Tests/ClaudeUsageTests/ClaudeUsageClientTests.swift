import XCTest
@testable import AIUsageDashboardCore

final class ClaudeUsageDecoderTests: XCTestCase {
    func testDecodesCommittedFixtureIntoSessionWeeklyAndScopedWindows() throws {
        let data = Data(ClaudeFixtures.oauthUsageResponse.utf8)

        let windows = try ClaudeUsageClientImpl.decodeQuotaWindows(data, providerID: .claudeCode)

        XCTAssertEqual(windows.count, 3)

        let session = try XCTUnwrap(windows.first { $0.type == .session })
        XCTAssertEqual(session.used, 8)
        XCTAssertEqual(session.limit, 100)
        XCTAssertEqual(session.remaining, 92)
        XCTAssertEqual(session.confidence, .providerReported)
        XCTAssertEqual(session.resetAt, isoDate("2026-07-09T01:00:00.475743+00:00"))

        let weekly = try XCTUnwrap(windows.first { $0.type == .weekly })
        XCTAssertEqual(weekly.used, 62)
        XCTAssertEqual(weekly.limit, 100)
        XCTAssertEqual(weekly.remaining, 38)
        XCTAssertEqual(weekly.resetAt, isoDate("2026-07-13T02:00:00.475765+00:00"))

        let scoped = try XCTUnwrap(windows.first { $0.type == .perModel })
        XCTAssertEqual(scoped.used, 49)
        XCTAssertEqual(scoped.limit, 100)
        XCTAssertEqual(scoped.remaining, 51)
        XCTAssertEqual(scoped.label, "Fable")
        XCTAssertEqual(scoped.bucketKey, "weekly_scoped:Fable")
        XCTAssertEqual(scoped.resetAt, isoDate("2026-07-13T02:00:00.476071+00:00"))

        XCTAssertFalse(windows.contains { $0.type == .credits })
    }

    private func isoDate(_ value: String) -> Date? {
        JSONLDateParsing.iso8601(value)
    }
}

final class DefaultClaudeUsageCredentialsReaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func credentialsPayload(accessToken token: String) -> String {
        "{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"}}"
    }

    func testFilePresentIsUsedWithoutSpawningSecurity() async throws {
        let fileURL = tempDirectory.appendingPathComponent(".credentials.json")
        try Data(credentialsPayload(accessToken: "file-token").utf8).write(to: fileURL)
        let spawner = RecordingKeychainReader(payload: credentialsPayload(accessToken: "keychain-token"))
        let reader = DefaultClaudeUsageCredentialsReader(credentialsURL: fileURL, keychainReader: spawner)

        let credentials = try await reader.readCredentials()

        XCTAssertEqual(credentials.accessToken, "file-token")
        XCTAssertEqual(spawner.callCount, 0)
    }

    func testExpiredFileCredentialFallsThroughToKeychain() async throws {
        let fileURL = tempDirectory.appendingPathComponent(".credentials.json")
        // A stale leftover file whose cred is already EXPIRED (expiresAt = epoch-ms in 2001).
        // It must NOT shadow the fresh Keychain token — otherwise the reader wedges in a
        // permanent expired state (the priority-inversion regression from the file-first order).
        let expiredFile = "{\"claudeAiOauth\":{\"accessToken\":\"stale-file\",\"expiresAt\":1000000000000}}"
        try Data(expiredFile.utf8).write(to: fileURL)
        let spawner = RecordingKeychainReader(payload: credentialsPayload(accessToken: "fresh-keychain"))
        let reader = DefaultClaudeUsageCredentialsReader(credentialsURL: fileURL, keychainReader: spawner)

        let credentials = try await reader.readCredentials()

        XCTAssertEqual(credentials.accessToken, "fresh-keychain")
        XCTAssertEqual(spawner.callCount, 1) // Keychain WAS consulted despite the file existing
    }

    func testFileAbsentParsesSpawnPayload() async throws {
        let fileURL = tempDirectory.appendingPathComponent("does-not-exist.json")
        let spawner = RecordingKeychainReader(payload: credentialsPayload(accessToken: "keychain-token"))
        let reader = DefaultClaudeUsageCredentialsReader(credentialsURL: fileURL, keychainReader: spawner)

        let credentials = try await reader.readCredentials()

        XCTAssertEqual(credentials.accessToken, "keychain-token")
        XCTAssertEqual(spawner.callCount, 1)
    }

    func testSpawnFailureReturnsNilWithNoThrowLoopAndNoRetry() async throws {
        let fileURL = tempDirectory.appendingPathComponent("does-not-exist.json")
        // nil payload simulates non-zero exit / spawn error / timeout.
        let spawner = RecordingKeychainReader(payload: nil)
        let reader = DefaultClaudeUsageCredentialsReader(credentialsURL: fileURL, keychainReader: spawner)

        do {
            _ = try await reader.readCredentials()
            XCTFail("Expected missingCredentials")
        } catch let error as ClaudeUsageError {
            guard case .missingCredentials = error else {
                return XCTFail("Expected missingCredentials, got \(error)")
            }
        }

        // Single failed read is final for the cycle — no re-prompt loop.
        XCTAssertEqual(spawner.callCount, 1)
    }

    func testEmptySpawnPayloadReturnsNil() async throws {
        let fileURL = tempDirectory.appendingPathComponent("does-not-exist.json")
        // A whitespace-only payload carries no token and no JSON — must fail, not surface a bad token.
        let spawner = RecordingKeychainReader(payload: "   ")
        let reader = DefaultClaudeUsageCredentialsReader(credentialsURL: fileURL, keychainReader: spawner)

        do {
            _ = try await reader.readCredentials()
            XCTFail("Expected missingCredentials for whitespace payload")
        } catch let error as ClaudeUsageError {
            guard case .missingCredentials = error else {
                return XCTFail("Expected missingCredentials, got \(error)")
            }
        }
        XCTAssertEqual(spawner.callCount, 1)
    }
}

private final class RecordingKeychainReader: KeychainPasswordSpawning, @unchecked Sendable {
    private let payload: String?
    private(set) var callCount = 0

    init(payload: String?) {
        self.payload = payload
    }

    func readPassword(service: String) -> String? {
        callCount += 1
        return payload
    }
}

final class ClaudeUsageClientImplTests: XCTestCase {
    private var tempDirectory: URL!
    private var session: URLSession!
    private var now: DateBox!
    private var sleeper: RecordingSleeper!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockClaudeURLProtocol.self]
        session = URLSession(configuration: configuration)
        now = DateBox(JSONLDateParsing.iso8601("2026-07-08T12:00:00Z")!)
        sleeper = RecordingSleeper()
    }

    override func tearDown() {
        MockClaudeURLProtocol.responses = []
        MockClaudeURLProtocol.requests = []
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testRequestUsesBearerAuthAndAnthropicBetaHeader() async throws {
        MockClaudeURLProtocol.responses = [
            .init(data: Data(ClaudeFixtures.oauthUsageResponse.utf8), statusCode: 200)
        ]
        let client = makeClient(accessToken: "mock-access-token")

        let windows = try await client.fetchQuotaWindows()

        XCTAssertEqual(windows.count, 3)
        let request = try XCTUnwrap(MockClaudeURLProtocol.requests.last)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }

    func testRepeated429PersistsCooldownAndServesStaleCacheWithoutThrowing() async throws {
        MockClaudeURLProtocol.responses = [
            .init(data: Data(ClaudeFixtures.oauthUsageResponse.utf8), statusCode: 200)
        ]
        let client = makeClient(accessToken: "mock-access-token")

        _ = try await client.fetchQuotaWindows()

        now.value = now.value.addingTimeInterval((10 * 60) + 1)
        MockClaudeURLProtocol.responses = [
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "120"]),
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "120"]),
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "120"])
        ]

        let staleWindows = try await client.fetchQuotaWindows()

        XCTAssertEqual(MockClaudeURLProtocol.requests.count, 4)
        let recordedSleeps = await sleeper.intervals()
        XCTAssertEqual(recordedSleeps, [30, 30])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cooldownURL.path))
        XCTAssertEqual(staleWindows.count, 3)
        XCTAssertTrue(staleWindows.allSatisfy { $0.confidence == .estimated })
        XCTAssertTrue(staleWindows.allSatisfy { $0.source.contains("(stale)") })

        MockClaudeURLProtocol.responses = []
        let cooldownWindows = try await client.fetchQuotaWindows()

        XCTAssertEqual(MockClaudeURLProtocol.requests.count, 4)
        XCTAssertEqual(cooldownWindows.count, 3)
        XCTAssertTrue(cooldownWindows.allSatisfy { $0.confidence == .estimated })
    }

    func testCachedWindowsWhoseResetHasPassedAreDropped() async throws {
        MockClaudeURLProtocol.responses = [
            .init(data: Data(ClaudeFixtures.oauthUsageResponse.utf8), statusCode: 200)
        ]
        let client = makeClient(accessToken: "mock-access-token")
        _ = try await client.fetchQuotaWindows()

        now.value = JSONLDateParsing.iso8601("2026-07-09T02:00:00Z")!
        MockClaudeURLProtocol.responses = [
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "300"]),
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "300"]),
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "300"])
        ]

        let windows = try await client.fetchQuotaWindows()

        XCTAssertNil(windows.first { $0.type == .session })
        XCTAssertEqual(windows.filter { $0.type == .weekly || $0.type == .perModel }.count, 2)
    }

    private var cacheURL: URL {
        tempDirectory.appendingPathComponent("claude-usage-cache.json")
    }

    private var cooldownURL: URL {
        tempDirectory.appendingPathComponent("claude-usage-cooldown.json")
    }

    private func makeClient(accessToken: String) -> ClaudeUsageClientImpl {
        let nowBox = now!
        let recordingSleeper = sleeper!
        return ClaudeUsageClientImpl(
            urlSession: session,
            credentialsReader: MockClaudeCredentialsReader(credentials: ClaudeUsageCredentials(
                accessToken: accessToken,
                expiresAt: JSONLDateParsing.iso8601("2026-07-20T23:00:00Z")
            )),
            cacheURL: cacheURL,
            cooldownURL: cooldownURL,
            now: { nowBox.value },
            sleep: { interval in await recordingSleeper.sleep(interval) }
        )
    }
}

final class ClaudeCodeProviderQuotaTests: XCTestCase {
    private var tempDirectory: URL!
    private var claudeDirectory: URL!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        claudeDirectory = tempDirectory.appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: claudeDirectory.appendingPathComponent("projects", isDirectory: true),
            withIntermediateDirectories: true
        )

        userDefaults = UserDefaults(suiteName: "com.AIUsageDashboard.ClaudeCodeProviderQuotaTests")!
        userDefaults.removeObject(forKey: "claudeNetworkUsageEnabled")
    }

    override func tearDown() {
        userDefaults.removeObject(forKey: "claudeNetworkUsageEnabled")
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testToggleOffKeepsCurrentUnavailableQuotaWindowsAndDoesNotCallClient() async throws {
        let client = MockClaudeUsageClient(behavior: .success(try liveWindows()))
        let provider = makeProvider(client: client)

        XCTAssertEqual(provider.capabilities, [.localLog, .tokenUsage])
        let snapshot = try await provider.fetchSnapshot()

        let calls = await client.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(snapshot.quotaWindows.map(\.type), [.session, .weekly])
        XCTAssertTrue(snapshot.quotaWindows.allSatisfy { $0.confidence == .unavailable })
        XCTAssertTrue(snapshot.quotaWindows.allSatisfy { $0.used == nil && $0.limit == nil && $0.remaining == nil })
    }

    func testToggleOnPublishesClientSessionWeeklyAndScopedWindows() async throws {
        userDefaults.set(true, forKey: "claudeNetworkUsageEnabled")
        let client = MockClaudeUsageClient(behavior: .success(try liveWindows()))
        let provider = makeProvider(client: client)

        XCTAssertEqual(provider.capabilities, [.localLog, .tokenUsage, .quota, .providerEndpoint])
        let snapshot = try await provider.fetchSnapshot()

        let calls = await client.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first { $0.type == .session }?.used, 8)
        XCTAssertEqual(snapshot.quotaWindows.first { $0.type == .weekly }?.used, 62)
        XCTAssertEqual(snapshot.quotaWindows.first { $0.type == .perModel }?.label, "Fable")
    }

    func testToggleOnClientThrowFallsBackToUnavailableQuotaWindows() async throws {
        userDefaults.set(true, forKey: "claudeNetworkUsageEnabled")
        let client = MockClaudeUsageClient(behavior: .failure)
        let snapshot = try await makeProvider(client: client).fetchSnapshot()

        let calls = await client.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(snapshot.quotaWindows.map(\.type), [.session, .weekly])
        XCTAssertTrue(snapshot.quotaWindows.allSatisfy { $0.confidence == .unavailable })
        XCTAssertTrue(snapshot.warnings.contains { warning in
            warning.level == .warning && warning.message.contains("Falling back")
        })
    }

    private func makeProvider(client: ClaudeUsageClient) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            parser: ClaudeJSONLParser(),
            claudeDirectoryURL: claudeDirectory,
            usageClient: client,
            userDefaults: userDefaults
        )
    }

    private func liveWindows() throws -> [QuotaWindow] {
        try ClaudeUsageClientImpl.decodeQuotaWindows(
            Data(ClaudeFixtures.oauthUsageResponse.utf8),
            providerID: .claudeCode
        )
    }
}

private struct MockClaudeCredentialsReader: ClaudeUsageCredentialsReading {
    let credentials: ClaudeUsageCredentials

    func readCredentials() async throws -> ClaudeUsageCredentials {
        credentials
    }
}

private actor RecordingSleeper {
    private var recorded: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) async {
        recorded.append(interval)
    }

    func intervals() -> [TimeInterval] {
        recorded
    }
}

private final class DateBox: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

private final class MockClaudeURLProtocol: URLProtocol {
    struct Response {
        let data: Data
        let statusCode: Int
        let headers: [String: String]

        init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
        }
    }

    static var responses: [Response] = []
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockClaudeURLProtocol", code: -1))
            return
        }
        let response = Self.responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor MockClaudeUsageClient: ClaudeUsageClient {
    enum Behavior: Sendable {
        case success([QuotaWindow])
        case failure
    }

    private let behavior: Behavior
    private var calls = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        calls += 1
        switch behavior {
        case .success(let windows):
            return windows
        case .failure:
            throw ClaudeUsageError.unexpectedResponse
        }
    }

    func callCount() -> Int {
        calls
    }
}
