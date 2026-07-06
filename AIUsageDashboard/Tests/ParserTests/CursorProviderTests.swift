import XCTest
@testable import AIUsageDashboardCore

final class CursorProviderTests: XCTestCase {
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

    func testDetectAvailabilityUsesStateDatabasePresenceOnly() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        let provider = CursorProvider(stateDatabaseURL: stateDB)

        var availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .notInstalled)

        try Data().write(to: stateDB)
        availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
    }

    func testFetchSnapshotStaysUnavailableWithPostMVPWarning() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try Data().write(to: stateDB)
        let provider = CursorProvider(stateDatabaseURL: stateDB)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertEqual(snapshot.authStatus, .unknown)
        XCTAssertEqual(snapshot.todayUsage.confidence, .unavailable)
        XCTAssertNil(snapshot.costUsage)
        XCTAssertEqual(snapshot.warnings.count, 1)
        XCTAssertEqual(snapshot.warnings.first?.message, "Cursor metrics require dashboard auth (post-MVP)")
        XCTAssertEqual(snapshot.warnings.first?.level, .info)
    }
}
