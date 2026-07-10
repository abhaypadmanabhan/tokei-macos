import XCTest
@testable import AIUsageDashboardCore

final class CodexProviderTests: XCTestCase {
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

    private func codexDirectory() -> URL {
        tempDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    func testDetectAvailabilityAndAuthUseCodexDirectoryPresenceOnly() async throws {
        let codex = codexDirectory()
        let provider = CodexProvider(codexDirectory: codex)

        var availability = await provider.detectAvailability()
        var authStatus = try await provider.authenticate()
        XCTAssertEqual(availability, .notInstalled)
        XCTAssertEqual(authStatus, .unauthenticated)

        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        availability = await provider.detectAvailability()
        authStatus = try await provider.authenticate()
        XCTAssertEqual(availability, .installed)
        XCTAssertEqual(authStatus, .unauthenticated)

        let auth = codex.appendingPathComponent("auth.json")
        try "{}".write(to: auth, atomically: true, encoding: .utf8)
        authStatus = try await provider.authenticate()
        XCTAssertEqual(authStatus, .authenticated)
    }

    func testFetchSnapshotUsesCodexSessionLogsAndQuotaWindows() async throws {
        let codex = codexDirectory()
        let sessionDir = codex
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("07", isDirectory: true)
            .appendingPathComponent("06", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try "{}".write(to: codex.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        try CodexFixtures.twoTokenCountEvents().write(
            to: sessionDir.appendingPathComponent("rollout-2026-07-06T10-00-00-test.jsonl"),
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
        let parser = CodexJSONLParser(calendar: calendar, now: { now })
        let provider = CodexProvider(parser: parser, codexDirectory: codex)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .codex)
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 200)
        XCTAssertEqual(snapshot.weekUsage.totalTokens, 200)
        XCTAssertEqual(snapshot.monthUsage?.totalTokens, 200)
        XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, 200)
        XCTAssertEqual(snapshot.dailyTotals?.values.reduce(0, +), 200)
        XCTAssertEqual(snapshot.hourlyTotals?.values.reduce(0, +), 200)
        XCTAssertEqual(snapshot.hourlyTotals?[calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 7,
            day: 6,
            hour: 10
        ))!], 130)
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }
}
