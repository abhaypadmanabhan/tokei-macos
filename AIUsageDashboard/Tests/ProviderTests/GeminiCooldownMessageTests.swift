import XCTest
@testable import AIUsageDashboardCore

final class GeminiCooldownMessageTests: XCTestCase {
    func testPersistedCooldownExplainsRateLimitAndRetryTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let credentials = directory.appendingPathComponent("fixture-auth.json")
        let json = GeminiFixtures.credentialsJSON(expiryDateMillis: 1_700_003_600_000)
        try Data(json.utf8).write(to: credentials)
        let cooldown = directory.appendingPathComponent("cooldown.json")
        try CooldownStore(cooldownURL: cooldown, now: { now }).persist(duration: 300)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiRoutingMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = GeminiUsageClientImpl(urlSession: session, credentialsFileURL: credentials,
                                            now: { now }, cooldownURL: cooldown)
        // Unset means on; never touch the process-wide argument domain other tests read.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: directory.appendingPathComponent("defaults").path))
        let provider = GeminiProvider(credentialsFileURL: credentials, quotaClient: client, userDefaults: defaults)
        let snapshot = try await provider.fetchSnapshot()
        let message = try XCTUnwrap(snapshot.warnings.first?.message)
        XCTAssertTrue(message.contains("rate-limited"))
        XCTAssertTrue(message.contains("retries at"))
        XCTAssertNotNil(message.range(of: "[0-9]{1,2}[:.][0-9]{2}", options: .regularExpression))
        XCTAssertFalse(message.contains("endpoint error"))
    }
}
