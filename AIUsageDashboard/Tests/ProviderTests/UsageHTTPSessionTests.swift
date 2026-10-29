import XCTest
@testable import AIUsageDashboardCore

final class UsageHTTPSessionTests: XCTestCase {
    func testSessionHasNoDiskCacheOrCookieStore() {
        let session = UsageHTTPSession.make()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(UsageHTTPSession.userAgent.hasPrefix("Tokei/"))
    }

    func testRedirectDelegateRejectsCrossHostAndDowngradeWithNoSecondRequest() async throws {
        for destination in ["https://second.test/end", "http://first.test/end"] {
            let session = UsageHTTPSession.make(protocolClasses: [RedirectUsageProtocol.self])
            defer { session.invalidateAndCancel() }
            RedirectUsageProtocol.destination = URL(string: destination)!
            RedirectUsageProtocol.hits = []
            var request = URLRequest(url: URL(string: "https://first.test/start")!)
            request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
            _ = try await session.data(for: request)
            XCTAssertEqual(RedirectUsageProtocol.hits, ["first.test"])
        }
    }

    func testSameHostHTTPSRedirectIsFollowed() async throws {
        let session = UsageHTTPSession.make(protocolClasses: [RedirectUsageProtocol.self])
        defer { session.invalidateAndCancel() }
        RedirectUsageProtocol.destination = URL(string: "https://first.test/end")!
        RedirectUsageProtocol.hits = []
        _ = try await session.data(from: URL(string: "https://first.test/start")!)
        XCTAssertEqual(RedirectUsageProtocol.hits, ["first.test", "first.test"])
    }
}

private final class RedirectUsageProtocol: URLProtocol {
    static var destination = URL(string: "https://second.test/end")!
    static var hits: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.hits.append(url.host ?? "")
        if url.path == "/start" {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": Self.destination.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: Self.destination), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
