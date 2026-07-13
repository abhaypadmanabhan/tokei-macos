import XCTest
@testable import AIUsageDashboardCore

final class GeminiUsageClientTests: XCTestCase {
    private var tempDirectory: URL!
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-07-12T12:00:00Z")!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        GeminiRoutingMockURLProtocol.reset()
    }

    override func tearDown() {
        GeminiRoutingMockURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Pure decoding

    func testDecodeQuotaWindowsFromRemainingFraction() throws {
        let data = Data(GeminiFixtures.retrieveUserQuotaRemainingFractionJSON.utf8)

        let windows = try GeminiUsageClientImpl.decodeQuotaWindows(data)

        XCTAssertEqual(windows.count, 2)
        let byBucket = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.bucketKey.map { ($0, window) }
        })

        let daily = try XCTUnwrap(byBucket["gemini-pro-daily"])
        XCTAssertEqual(daily.type, .daily)
        XCTAssertEqual(daily.used, 38)      // (1 - 0.62) * 100
        XCTAssertEqual(daily.limit, 100)
        XCTAssertEqual(daily.remaining, 62)
        XCTAssertEqual(daily.providerID, .gemini)
        XCTAssertEqual(daily.confidence, .providerReported)
        XCTAssertEqual(daily.source, "gemini-cli")
        XCTAssertEqual(daily.label, "Gemini 2.5 Pro")
        XCTAssertEqual(daily.resetAt, ISO8601DateFormatter().date(from: "2026-07-13T00:00:00Z"))

        let weekly = try XCTUnwrap(byBucket["gemini-pro-weekly"])
        XCTAssertEqual(weekly.type, .weekly)
        XCTAssertEqual(weekly.used, 10)     // (1 - 0.90) * 100
        XCTAssertEqual(weekly.remaining, 90)
    }

    func testDecodeQuotaWindowsFromUsedPercent() throws {
        let data = Data(GeminiFixtures.retrieveUserQuotaUsedPercentJSON.utf8)

        let windows = try GeminiUsageClientImpl.decodeQuotaWindows(data)

        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.type, .daily)
        XCTAssertEqual(window.used, 25)
        XCTAssertEqual(window.remaining, 75)
        XCTAssertEqual(window.resetAt, ISO8601DateFormatter().date(from: "2026-07-13T12:30:00Z"))
    }

    func testDecodeQuotaWindowsUnrecognizedThrows() {
        let data = Data(GeminiFixtures.retrieveUserQuotaUnrecognizedJSON.utf8)
        XCTAssertThrowsError(try GeminiUsageClientImpl.decodeQuotaWindows(data)) { error in
            XCTAssertEqual(error as? GeminiUsageError, .unrecognizedResponse)
        }
    }

    func testDecodeAccessToken() throws {
        let token = try GeminiUsageClientImpl.decodeAccessToken(Data(GeminiFixtures.tokenRefreshJSON.utf8))
        XCTAssertEqual(token, "ya29.refreshed-token")
    }

    func testDecodeLoadCodeAssistProject() {
        let project = GeminiUsageClientImpl.decodeLoadCodeAssistProject(Data(GeminiFixtures.loadCodeAssistJSON.utf8))
        XCTAssertEqual(project, "tokei-user-project")
    }

    // MARK: - Token expiry (injected clock, no real Date())

    func testExpiryDecisionWithInjectedClock() {
        let valid = GeminiOAuthCredentials(
            accessToken: "a", refreshToken: "r", tokenType: "Bearer",
            expiryDate: (fixedNow.timeIntervalSince1970 + 3600) * 1000
        )
        XCTAssertFalse(valid.isExpired(now: fixedNow))

        let expired = GeminiOAuthCredentials(
            accessToken: "a", refreshToken: "r", tokenType: "Bearer",
            expiryDate: (fixedNow.timeIntervalSince1970 - 3600) * 1000
        )
        XCTAssertTrue(expired.isExpired(now: fixedNow))

        let missing = GeminiOAuthCredentials(
            accessToken: "a", refreshToken: "r", tokenType: "Bearer", expiryDate: nil
        )
        XCTAssertTrue(missing.isExpired(now: fixedNow), "missing expiry must be treated as expired")

        // Within the skew window it should be considered expired (refresh early).
        let withinSkew = GeminiOAuthCredentials(
            accessToken: "a", refreshToken: "r", tokenType: "Bearer",
            expiryDate: (fixedNow.timeIntervalSince1970 + 30) * 1000
        )
        XCTAssertTrue(withinSkew.isExpired(now: fixedNow, skew: 60))
    }

    // MARK: - End-to-end flow

    func testValidTokenSkipsRefreshAndReturnsWindows() async throws {
        writeCredentials(expiryOffset: 3600) // still valid
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.loadCodeAssistURL,
                                             json: GeminiFixtures.loadCodeAssistJSON, status: 200)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.retrieveUserQuotaURL,
                                             json: GeminiFixtures.retrieveUserQuotaRemainingFractionJSON, status: 200)

        let client = makeClient(clientSecret: nil)
        let windows = try await client.fetchQuotaWindows()

        XCTAssertEqual(windows.count, 2)
        XCTAssertFalse(GeminiRoutingMockURLProtocol.hits.contains(GeminiUsageClientImpl.tokenEndpoint.absoluteString),
                       "a still-valid token must not hit the OAuth refresh endpoint")
    }

    func testExpiredTokenRefreshesThenRetries() async throws {
        writeCredentials(expiryOffset: -3600) // expired
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.tokenEndpoint,
                                             json: GeminiFixtures.tokenRefreshJSON, status: 200)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.loadCodeAssistURL,
                                             json: GeminiFixtures.loadCodeAssistJSON, status: 200)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.retrieveUserQuotaURL,
                                             json: GeminiFixtures.retrieveUserQuotaUsedPercentJSON, status: 200)

        let client = makeClient(clientSecret: "test-secret")
        let windows = try await client.fetchQuotaWindows()

        XCTAssertEqual(windows.count, 1)
        XCTAssertTrue(GeminiRoutingMockURLProtocol.hits.contains(GeminiUsageClientImpl.tokenEndpoint.absoluteString),
                      "an expired token must trigger a refresh call")
    }

    func testExpiredTokenWithoutSecretIsRefreshUnavailable() async {
        writeCredentials(expiryOffset: -3600)
        let client = makeClient(clientSecret: nil) // secret deliberately not bundled

        await assertThrows(GeminiUsageError.tokenRefreshUnavailable) {
            _ = try await client.fetchQuotaWindows()
        }
    }

    func testMissingCredentialsThrowsNotAuthenticated() async {
        let client = makeClient(clientSecret: nil) // no creds file written
        await assertThrows(GeminiUsageError.notAuthenticated) {
            _ = try await client.fetchQuotaWindows()
        }
    }

    func testNon200FromQuotaThrowsHTTPStatus() async {
        writeCredentials(expiryOffset: 3600)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.loadCodeAssistURL,
                                             json: GeminiFixtures.loadCodeAssistJSON, status: 200)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.retrieveUserQuotaURL,
                                             json: "{}", status: 500)

        let client = makeClient(clientSecret: nil)
        await assertThrows(GeminiUsageError.httpStatus(500)) {
            _ = try await client.fetchQuotaWindows()
        }
    }

    func test401MidFlightForcesRefreshAndRetries() async throws {
        writeCredentials(expiryOffset: 3600) // token looks valid, but server rejects it
        // First loadCodeAssist rejects (401); after forced refresh, the retry succeeds.
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.loadCodeAssistURL,
                                             json: "{}", status: 401)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.tokenEndpoint,
                                             json: GeminiFixtures.tokenRefreshJSON, status: 200)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.loadCodeAssistURL,
                                             json: GeminiFixtures.loadCodeAssistJSON, status: 200)
        GeminiRoutingMockURLProtocol.enqueue(url: GeminiUsageClientImpl.retrieveUserQuotaURL,
                                             json: GeminiFixtures.retrieveUserQuotaUsedPercentJSON, status: 200)

        let client = makeClient(clientSecret: "test-secret")
        let windows = try await client.fetchQuotaWindows()
        XCTAssertEqual(windows.count, 1)
    }

    // MARK: - Helpers

    private var credentialsURL: URL {
        tempDirectory.appendingPathComponent("oauth_creds.json")
    }

    private func writeCredentials(expiryOffset: TimeInterval) {
        let millis = (fixedNow.timeIntervalSince1970 + expiryOffset) * 1000
        let json = GeminiFixtures.credentialsJSON(expiryDateMillis: millis)
        try? Data(json.utf8).write(to: credentialsURL)
    }

    private func makeClient(clientSecret: String?) -> GeminiUsageClientImpl {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiRoutingMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return GeminiUsageClientImpl(
            urlSession: session,
            credentialsFileURL: credentialsURL,
            now: { self.fixedNow },
            clientID: "test-client-id",
            clientSecret: clientSecret
        )
    }

    private func assertThrows(
        _ expected: GeminiUsageError,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as GeminiUsageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

/// Routes mock responses per URL, popping a per-URL queue so the same endpoint can
/// return different responses across sequential calls (used for the 401→refresh→retry
/// path). Records every requested URL for assertions.
final class GeminiRoutingMockURLProtocol: URLProtocol {
    private static var queues: [String: [(data: Data, status: Int)]] = [:]
    private(set) static var hits: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queues = [:]
        hits = []
    }

    static func enqueue(url: URL, json: String, status: Int) {
        lock.lock(); defer { lock.unlock() }
        queues[url.absoluteString, default: []].append((Data(json.utf8), status))
    }

    private static func next(for url: String) -> (data: Data, status: Int)? {
        lock.lock(); defer { lock.unlock() }
        hits.append(url)
        guard var queue = queues[url], !queue.isEmpty else { return nil }
        let response = queue.count > 1 ? queue.removeFirst() : queue[0]
        queues[url] = queue
        return response
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        guard let (data, status) = Self.next(for: key) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "GeminiRoutingMock", code: -1))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
