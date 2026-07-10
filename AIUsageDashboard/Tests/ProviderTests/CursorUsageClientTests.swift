import XCTest
@testable import AIUsageDashboardCore

final class CursorSessionTests: XCTestCase {
    func testUserIDStripsProviderPrefixForNativeSubject() {
        let jwt = CursorFixtures.jwt(sub: "auth0|user_01ABCdef")
        XCTAssertEqual(CursorSession.userID(fromJWT: jwt), "user_01ABCdef")
    }

    func testUserIDKeepsWorkOSOAuthSubjectVerbatim() {
        let jwt = CursorFixtures.jwt(sub: "google-oauth2|105551234567890")
        XCTAssertEqual(CursorSession.userID(fromJWT: jwt), "google-oauth2|105551234567890")
    }

    func testUserIDRejectsUnrecognizedSubject() {
        XCTAssertNil(CursorSession.userID(fromJWT: CursorFixtures.jwt(sub: "1234567890")))
        XCTAssertNil(CursorSession.userID(fromJWT: "not-a-jwt"))
        XCTAssertNil(CursorSession.userID(fromJWT: ""))
    }

    func testCookieEncodesSeparatorAndCarriesToken() {
        let jwt = CursorFixtures.jwt(sub: "auth0|user_01ABCdef")
        let cookie = CursorSession.cookie(jwt: jwt)
        XCTAssertEqual(cookie, "WorkosCursorSessionToken=user_01ABCdef%3A%3A\(jwt)")
    }

    func testCookieNilWhenSubjectUnresolvable() {
        XCTAssertNil(CursorSession.cookie(jwt: CursorFixtures.jwt(sub: "1234567890")))
    }
}

final class CursorUsageCSVTests: XCTestCase {
    func testParsesEventsWithHeaderNameLookupAndCacheWriteArithmetic() {
        let events = CursorUsageCSV.parseEvents(CursorFixtures.usageEventsCSV)

        // Four rows, but the all-zero "Errored, No Charge" row is dropped.
        XCTAssertEqual(events.count, 3)

        let first = events[0]
        XCTAssertEqual(first.model, "claude-opus-4-8")
        XCTAssertEqual(first.inputTokens, 1000)          // Input (w/o Cache Write)
        XCTAssertEqual(first.cacheWriteTokens, 200)      // 1200 − 1000
        XCTAssertEqual(first.cacheReadTokens, 500)
        XCTAssertEqual(first.outputTokens, 300)
        XCTAssertEqual(first.totalTokens, 2000)
        XCTAssertEqual(first.cost, 0.05, accuracy: 0.0001)
    }

    func testParsesQuotedCostWithEmbeddedComma() {
        let events = CursorUsageCSV.parseEvents(CursorFixtures.usageEventsCSV)
        let sonnet = events.first { $0.model == "claude-sonnet-5" }
        XCTAssertEqual(sonnet?.cost ?? 0, 1234.56, accuracy: 0.01)
    }

    func testMissingRequiredColumnsYieldsNoEvents() {
        XCTAssertTrue(CursorUsageCSV.parseEvents(CursorFixtures.usageEventsCSVMissingColumns).isEmpty)
        XCTAssertTrue(CursorUsageCSV.parseEvents("").isEmpty)
    }

    func testParsesFractionalISOAndBareDay() {
        XCTAssertNotNil(CursorUsageCSV.parseDate("2026-07-08T09:00:00.000Z"))
        XCTAssertNotNil(CursorUsageCSV.parseDate("2026-07-08T09:00:00Z"))
        XCTAssertNotNil(CursorUsageCSV.parseDate("2026-07-08"))
        XCTAssertNil(CursorUsageCSV.parseDate("nonsense"))
    }

    func testSplitFieldsHonoursQuotesAndEscapes() {
        let fields = CursorUsageCSV.splitFields(#"a,"b,c","d""e",f"#)
        XCTAssertEqual(fields, ["a", "b,c", "d\"e", "f"])
    }
}

final class CursorUsageSummaryTests: XCTestCase {
    func testDecodesTotalPercentAndReset() {
        let summary = CursorUsageSummary.decode(Data(CursorFixtures.usageSummary.utf8))
        XCTAssertEqual(summary?.usedPercent, 42.5)
        XCTAssertEqual(summary?.membershipType, "pro")
        XCTAssertNotNil(summary?.resetAt)
    }

    func testFallsBackToCentsRatioWhenNoPercent() {
        let summary = CursorUsageSummary.decode(Data(CursorFixtures.usageSummaryCentsOnly.utf8))
        XCTAssertEqual(summary?.usedPercent ?? 0, 25, accuracy: 0.0001) // 3000 / 12000
    }

    func testNilPercentWhenPlanEmpty() {
        let summary = CursorUsageSummary.decode(Data(CursorFixtures.usageSummaryEmpty.utf8))
        XCTAssertNil(summary?.usedPercent)
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(CursorUsageSummary.decode(Data("not json".utf8)))
    }
}

final class CursorUsageClientImplTests: XCTestCase {
    private var tempDirectory: URL!
    private var session: URLSession!
    private var now: CursorDateBox!
    private var sleeper: CursorRecordingSleeper!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockCursorURLProtocol.self]
        session = URLSession(configuration: configuration)
        now = CursorDateBox(JSONLDateParsing.iso8601("2026-07-08T12:00:00Z")!)
        sleeper = CursorRecordingSleeper()
    }

    override func tearDown() {
        MockCursorURLProtocol.responses = []
        MockCursorURLProtocol.requests = []
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testCSVRequestUsesCookieAuthAndCorrectURL() async throws {
        MockCursorURLProtocol.responses = [
            .init(data: Data(CursorFixtures.usageEventsCSV.utf8), statusCode: 200)
        ]
        let client = makeClient()

        let csv = try await client.fetchUsageEventsCSV(cookie: "WorkosCursorSessionToken=user_1%3A%3Ajwt")

        XCTAssertTrue(csv.contains("claude-opus-4-8"))
        let request = try XCTUnwrap(MockCursorURLProtocol.requests.last)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cookie"),
            "WorkosCursorSessionToken=user_1%3A%3Ajwt"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Referer"),
            "https://www.cursor.com/settings"
        )
    }

    func testNon2xxThrowsHTTPStatusWithoutEnteringCooldown() async throws {
        MockCursorURLProtocol.responses = [
            .init(data: Data(), statusCode: 403)
        ]
        let client = makeClient()

        do {
            _ = try await client.fetchUsageSummary(cookie: "c")
            XCTFail("expected throw")
        } catch let CursorUsageError.httpStatus(code) {
            XCTAssertEqual(code, 403)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: cooldownURL.path))
        XCTAssertEqual(MockCursorURLProtocol.requests.count, 1)

        MockCursorURLProtocol.responses = [
            .init(data: Data(CursorFixtures.usageSummary.utf8), statusCode: 200)
        ]
        let data = try await client.fetchUsageSummary(cookie: "c")
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(MockCursorURLProtocol.requests.count, 2)
    }

    func testRepeated429PersistsCooldownThenFastFailsUntilElapsed() async throws {
        MockCursorURLProtocol.responses = [
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "120"]),
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "120"]),
            .init(data: Data(), statusCode: 429, headers: ["Retry-After": "120"])
        ]
        let client = makeClient()

        do {
            _ = try await client.fetchUsageSummary(cookie: "c")
            XCTFail("expected rateLimited")
        } catch let CursorUsageError.rateLimited(retryAfter) {
            XCTAssertEqual(retryAfter, 120)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(MockCursorURLProtocol.requests.count, 3)
        let recordedSleeps = await sleeper.intervals()
        XCTAssertEqual(recordedSleeps, [30, 30])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cooldownURL.path))

        MockCursorURLProtocol.responses = [
            .init(data: Data(CursorFixtures.usageSummary.utf8), statusCode: 200)
        ]
        do {
            _ = try await client.fetchUsageSummary(cookie: "c")
            XCTFail("expected cooldownActive")
        } catch CursorUsageError.cooldownActive {
            // Expected — no network while cooling down.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(MockCursorURLProtocol.requests.count, 3)

        now.value = now.value.addingTimeInterval(121)
        MockCursorURLProtocol.responses = [
            .init(data: Data(CursorFixtures.usageSummary.utf8), statusCode: 200)
        ]
        let data = try await client.fetchUsageSummary(cookie: "c")
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(MockCursorURLProtocol.requests.count, 4)
    }

    private var cooldownURL: URL {
        tempDirectory.appendingPathComponent("cursor-usage-cooldown.json")
    }

    private func makeClient() -> CursorUsageClientImpl {
        let nowBox = now!
        let sleeper = sleeper!
        return CursorUsageClientImpl(
            urlSession: session,
            cooldownURL: cooldownURL,
            now: { nowBox.value },
            sleep: { interval in await sleeper.sleep(interval) }
        )
    }
}

private actor CursorRecordingSleeper {
    private var recorded: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) async {
        recorded.append(interval)
    }

    func intervals() -> [TimeInterval] {
        recorded
    }
}

private final class CursorDateBox: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

private final class MockCursorURLProtocol: URLProtocol {
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
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockCursorURLProtocol", code: -1))
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
