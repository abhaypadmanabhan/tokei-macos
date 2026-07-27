import XCTest
@testable import AIUsageDashboardCore

/// Handoff P2: a live reading must carry a structured `observedAt`, and its `source`
/// must keep naming where the reading came from rather than how old it is.
final class AntigravityQuotaObservationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        MockURLProtocol.mockResponse = nil
        MockURLProtocol.mockError = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testLiveFetchStampsObservedAtWithTheFetchTime() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        MockURLProtocol.mockResponse = (AntigravityFixtures.quotaSummaryJSON.data(using: .utf8)!, 200)
        MockURLProtocol.mockError = nil

        let testNow = isoDate("2026-07-06T12:00:00Z")!
        let client = AntigravityQuotaClientImpl(
            urlSession: session,
            discoverer: MockDiscoverer(endpoint: AntigravityQuotaEndpoint(csrfToken: "csrf", listenPorts: [1234])),
            now: { testNow },
            cacheDirectory: tempDirectory,
            cacheFileName: "test-quota-cache.json"
        )

        let windows = try await client.fetchQuotaWindows()

        XCTAssertEqual(windows.count, 4)
        for window in windows {
            XCTAssertEqual(window.observedAt, testNow)
            XCTAssertEqual(window.confidence, .providerReported)
            XCTAssertEqual(window.source, "antigravity-local-rpc")
        }
    }

    private func isoDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
