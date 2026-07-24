import XCTest
@testable import AIUsageDashboardCore

final class CopilotProviderTests: XCTestCase {
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

    func testMissingInstallMarkersReportNotInstalledAndUnavailableUsage() async throws {
        let provider = CopilotProvider(
            installationMarkers: [tempDirectory.appendingPathComponent("missing")],
            extensionDirectories: [tempDirectory.appendingPathComponent("extensions")]
        )

        let availability = await provider.detectAvailability()
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(availability, .notInstalled)
        XCTAssertEqual(snapshot.providerID, .copilot)
        XCTAssertEqual(snapshot.authStatus, .unauthenticated)
        XCTAssertEqual(snapshot.todayUsage.confidence, .unavailable)
        XCTAssertNil(snapshot.todayUsage.totalTokens)
        XCTAssertEqual(snapshot.weekUsage.confidence, .unavailable)
        XCTAssertNil(snapshot.weekUsage.totalTokens)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains {
            $0.level == .info && $0.message.localizedCaseInsensitiveContains("not installed")
        })
    }

    func testExistingConfigurationMarkerReportsInstalled() async throws {
        let marker = tempDirectory.appendingPathComponent(".copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        let provider = CopilotProvider(
            installationMarkers: [marker],
            extensionDirectories: []
        )

        let availability = await provider.detectAvailability()
        let authStatus = try await provider.authenticate()

        XCTAssertEqual(availability, .installed)
        XCTAssertEqual(authStatus, .unknown)
    }

    func testVersionedVSCodeExtensionReportsInstalled() async throws {
        let extensions = tempDirectory.appendingPathComponent("extensions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: extensions.appendingPathComponent("github.copilot-chat-0.39.0", isDirectory: true),
            withIntermediateDirectories: true
        )
        let provider = CopilotProvider(
            installationMarkers: [],
            extensionDirectories: [extensions]
        )

        let availability = await provider.detectAvailability()

        XCTAssertEqual(availability, .installed)
    }

    func testInstalledSnapshotRemainsHonestlyUnavailable() async throws {
        let marker = tempDirectory.appendingPathComponent(".copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        let provider = CopilotProvider(
            installationMarkers: [marker],
            extensionDirectories: []
        )

        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.authStatus, .unknown)
        XCTAssertEqual(snapshot.todayUsage.confidence, .unavailable)
        XCTAssertEqual(snapshot.weekUsage.confidence, .unavailable)
        XCTAssertTrue(snapshot.warnings.contains {
            $0.level == .info && $0.message.localizedCaseInsensitiveContains("usage")
        })
    }

    func testDefaultRegistryIncludesCopilotProvider() async {
        let registry = ProviderRegistry.default()
        let ids = await registry.providers.map(\.id)

        XCTAssertTrue(ids.contains(.copilot))
    }
}
