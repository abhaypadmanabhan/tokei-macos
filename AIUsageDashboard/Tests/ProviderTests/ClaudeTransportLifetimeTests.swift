import XCTest
@testable import AIUsageDashboardCore

final class ClaudeTransportLifetimeTests: XCTestCase {
    func testRepeatedClaudeClientCreationReusesOneEphemeralSession() throws {
        var sessions: [URLSession] = []
        defer {
            if Set(sessions.map(ObjectIdentifier.init)).count > 1 {
                sessions.forEach { $0.invalidateAndCancel() }
            }
        }
        for _ in 0..<50 {
            let client = ClaudeUsageClientImpl()
            // No fetch occurs. Inspect the immutable transport without exposing a production test hook.
            let transports = Mirror(reflecting: client).children.compactMap { $0.value as? URLSession }
            let session = try XCTUnwrap(transports.first)
            sessions.append(session)
        }
        XCTAssertEqual(Set(sessions.map(ObjectIdentifier.init)).count, 1)
        XCTAssertTrue(sessions.allSatisfy { $0.configuration.urlCache == nil })
    }
}
