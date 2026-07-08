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
    private var session: URLSession!
    private var client: CursorUsageClientImpl!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockCursorURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = CursorUsageClientImpl(urlSession: session)
    }

    override func tearDown() {
        MockCursorURLProtocol.mockResponse = nil
        MockCursorURLProtocol.lastRequest = nil
        session.invalidateAndCancel()
        super.tearDown()
    }

    func testCSVRequestUsesCookieAuthAndCorrectURL() async throws {
        MockCursorURLProtocol.mockResponse = (Data(CursorFixtures.usageEventsCSV.utf8), 200)

        let csv = try await client.fetchUsageEventsCSV(cookie: "WorkosCursorSessionToken=user_1%3A%3Ajwt")

        XCTAssertTrue(csv.contains("claude-opus-4-8"))
        XCTAssertEqual(
            MockCursorURLProtocol.lastRequest?.url?.absoluteString,
            "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens"
        )
        XCTAssertEqual(
            MockCursorURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"),
            "WorkosCursorSessionToken=user_1%3A%3Ajwt"
        )
        XCTAssertEqual(
            MockCursorURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer"),
            "https://www.cursor.com/settings"
        )
    }

    func testNon2xxThrowsHTTPStatus() async {
        MockCursorURLProtocol.mockResponse = (Data(), 403)
        do {
            _ = try await client.fetchUsageSummary(cookie: "c")
            XCTFail("expected throw")
        } catch let CursorUsageError.httpStatus(code) {
            XCTAssertEqual(code, 403)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private final class MockCursorURLProtocol: URLProtocol {
    static var mockResponse: (data: Data, statusCode: Int)?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let (data, statusCode) = Self.mockResponse else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockCursorURLProtocol", code: -1))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
