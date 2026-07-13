import XCTest
@testable import AIUsageDashboardCore

final class GeminiProviderTests: XCTestCase {
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

    func testAbsentCredentialsProducesCleanEmptyState() async throws {
        // No creds file written → provider must not crash and must not touch the network.
        let provider = GeminiProvider(
            credentialsFileURL: credentialsURL,
            quotaClient: StubQuotaClient(result: .failure(GeminiUsageError.notAuthenticated))
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertEqual(snapshot.authStatus, .unauthenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .info })
    }

    func testLiveQuotaSurfacedWhenClientReturnsWindows() async throws {
        writeCredentials()
        let window = QuotaWindow(
            providerID: .gemini, type: .daily, used: 40, limit: 100, remaining: 60,
            resetAt: Date(), confidence: .providerReported, source: "gemini-cli", bucketKey: "gemini-daily"
        )
        let provider = GeminiProvider(
            credentialsFileURL: credentialsURL,
            quotaClient: StubQuotaClient(result: .success([window]))
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.type, .daily)
        XCTAssertEqual(snapshot.quotaWindows.first?.confidence, .providerReported)
    }

    func testEmptyWindowsAddsInfoWarning() async throws {
        writeCredentials()
        let provider = GeminiProvider(
            credentialsFileURL: credentialsURL,
            quotaClient: StubQuotaClient(result: .success([]))
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .info })
    }

    func testEndpointErrorDegradesToWarning() async throws {
        writeCredentials()
        let provider = GeminiProvider(
            credentialsFileURL: credentialsURL,
            quotaClient: StubQuotaClient(result: .failure(GeminiUsageError.httpStatus(503)))
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .warning })
    }

    func testRefreshUnavailableProducesActionableInfoWarning() async throws {
        writeCredentials()
        let provider = GeminiProvider(
            credentialsFileURL: credentialsURL,
            quotaClient: StubQuotaClient(result: .failure(GeminiUsageError.tokenRefreshUnavailable))
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.level == .info && $0.message.localizedCaseInsensitiveContains("gemini") })
    }

    func testRegistryIncludesGemini() async {
        let registry = ProviderRegistry.default()
        let providers = await registry.providers
        XCTAssertTrue(providers.contains { $0.id == .gemini })
    }

    // MARK: - Helpers

    private var credentialsURL: URL {
        tempDirectory.appendingPathComponent("oauth_creds.json")
    }

    private func writeCredentials() {
        let json = GeminiFixtures.credentialsJSON(expiryDateMillis: Date().timeIntervalSince1970 * 1000 + 3_600_000)
        try? Data(json.utf8).write(to: credentialsURL)
    }
}

/// Minimal `QuotaProvider` stub for provider-level tests.
private struct StubQuotaClient: QuotaProvider {
    let result: Result<[QuotaWindow], GeminiUsageError>

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        try result.get()
    }
}
