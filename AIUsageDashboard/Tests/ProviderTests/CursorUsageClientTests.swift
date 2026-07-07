import XCTest
@testable import AIUsageDashboardCore

final class CursorUsageClientTests: XCTestCase {
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
        session.invalidateAndCancel()
        super.tearDown()
    }

    func testSuccessfulResponseProducesProviderReportedQuotaWindows() async throws {
        MockCursorURLProtocol.mockResponse = (
            data: CursorFixtures.cursorUsageSuccess.data(using: .utf8)!,
            statusCode: 200
        )

        let response = try await client.fetchUsage(bearerToken: "test-token")

        XCTAssertEqual(response.quotaWindows.count, 1)
        let window = response.quotaWindows[0]
        XCTAssertEqual(window.providerID, .cursor)
        XCTAssertEqual(window.type, .monthly)
        // 150 of 500 requests → 30% used (convention: used is a percent, limit == 100).
        XCTAssertEqual(window.used, 30)
        XCTAssertEqual(window.limit, 100)
        XCTAssertEqual(window.remaining, 70)
        XCTAssertEqual(window.confidence, .providerReported)
        XCTAssertEqual(window.source, "api2.cursor.sh/auth/usage (gpt-4)")
        // Honest request-count info is always surfaced.
        XCTAssertTrue(response.warnings.contains {
            $0.level == .info && $0.message.contains("150 requests this billing month")
        })
    }

    func testMalformedResponseReturnsWarningWithoutThrowing() async throws {
        MockCursorURLProtocol.mockResponse = (
            data: CursorFixtures.cursorUsageMalformed.data(using: .utf8)!,
            statusCode: 200
        )

        let response = try await client.fetchUsage(bearerToken: "test-token")

        XCTAssertTrue(response.quotaWindows.isEmpty)
        XCTAssertEqual(response.warnings.count, 1)
        XCTAssertEqual(response.warnings.first?.level, .warning)
    }
}

private final class MockCursorURLProtocol: URLProtocol {
    static var mockResponse: (data: Data, statusCode: Int)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
