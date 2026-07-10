import XCTest
@testable import AIUsageDashboardCore

final class ClineProviderTests: XCTestCase {
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

    private func clineDirectory() -> URL {
        tempDirectory.appendingPathComponent(".cline", isDirectory: true)
    }

    func testDetectAvailabilityUsesClineDirectoryPresenceOnly() async throws {
        let cline = clineDirectory()
        let provider = ClineProvider(clineDirectory: cline)

        var availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .notInstalled)

        try FileManager.default.createDirectory(at: cline, withIntermediateDirectories: true)
        availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
    }

    func testAuthenticateReturnsUnknown() async throws {
        let cline = clineDirectory()
        try FileManager.default.createDirectory(at: cline, withIntermediateDirectories: true)
        let provider = ClineProvider(clineDirectory: cline)
        let authStatus = try await provider.authenticate()
        XCTAssertEqual(authStatus, .unknown)
    }

    func testFetchSnapshotUsesClineSessionLogsAndCost() async throws {
        let cline = clineDirectory()
        let sessionID = "1783325327533_provider"
        let sessionDir = cline
            .appendingPathComponent("data/sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try ClineFixtures.twoAssistantMessages(sessionID: sessionID).write(
            to: sessionDir.appendingPathComponent("\(sessionID).messages.json"),
            atomically: true,
            encoding: .utf8
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 7,
            day: 6,
            hour: 12
        ))!
        let parser = ClineMessagesParser(calendar: calendar, now: { now })
        let provider = ClineProvider(parser: parser, clineDirectory: cline)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .cline)
        XCTAssertEqual(snapshot.authStatus, .unknown)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 525)
        XCTAssertEqual(snapshot.weekUsage.totalTokens, 525)
        XCTAssertEqual(snapshot.monthUsage?.totalTokens, 525)
        XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, 525)
        XCTAssertEqual(snapshot.dailyTotals?.values.reduce(0, +), 525)
        XCTAssertEqual(snapshot.hourlyTotals?.values.reduce(0, +), 525)
        XCTAssertEqual(snapshot.costUsage?.amount ?? -1, 0.03, accuracy: 0.0001)
        XCTAssertEqual(snapshot.costUsage?.currency, "USD")
        XCTAssertEqual(snapshot.costUsage?.confidence, .localParsed)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }
}
