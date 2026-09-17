import XCTest
@testable import AIUsageDashboardCore

private final class CodexProviderTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func read() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Date) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private struct CalendarEpochFixture {
    let provider: CodexProvider
    let session: URL
    let clock: CodexProviderTestClock
    let formatter: ISO8601DateFormatter
    let losAngeles: Calendar
    let tokyo: Calendar
    let accountA: String
    let accountB: String
    let switched: ProviderSnapshot
}

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

    private func writeIdentity(_ identity: String, to codex: URL) throws {
        try Data(#"{"tokens":{"account_id":"\#(identity)"}}"#.utf8).write(
            to: codex.appendingPathComponent("auth.json"),
            options: .atomic
        )
    }

    private func codexEvent(
        totalTokens: Int,
        lastTokens: Int,
        timestamp: String,
        usedPercent: Int = 20
    ) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{" +
            "\"type\":\"token_count\",\"info\":{\"total_token_usage\":{" +
            "\"input_tokens\":\(totalTokens),\"total_tokens\":\(totalTokens)}," +
            "\"last_token_usage\":{\"input_tokens\":\(lastTokens)," +
            "\"total_tokens\":\(lastTokens)}},\"rate_limits\":{" +
            "\"primary\":{\"used_percent\":\(usedPercent),\"limit_window_seconds\":604800," +
            "\"resets_at\":1789698141}}}}"
    }

    @discardableResult
    private func writeSession(
        _ name: String,
        to codex: URL,
        events: [String]
    ) throws -> URL {
        let sessions = codex.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent(name)
        try Data(events.joined(separator: "\n").utf8).write(to: file, options: .atomic)
        return file
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeCalendarEpochFixture() async throws -> CalendarEpochFixture {
        let codex = codexDirectory()
        let sessions = codex.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try writeIdentity("acct-a", to: codex)
        let session = sessions.appendingPathComponent("session.jsonl")
        try Data(codexEvent(
            totalTokens: 10,
            lastTokens: 10,
            timestamp: "2026-09-17T02:14:00Z"
        ).utf8).write(to: session, options: .atomic)

        let formatter = ISO8601DateFormatter()
        let clock = CodexProviderTestClock(
            try XCTUnwrap(formatter.date(from: "2026-09-17T02:16:40Z"))
        )
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let parser = CodexJSONLParser(calendar: losAngeles, now: { clock.read() })
        let provider = CodexProvider(
            parser: parser,
            codexDirectory: codex,
            environment: [:],
            now: { clock.read() }
        )
        let first = try await provider.fetchSnapshot()
        let accountA = try XCTUnwrap(first.accounts?.first?.accountID)
        try writeIdentity("acct-b", to: codex)
        let switched = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(
            switched.accounts?.first { $0.accountID != accountA }?.accountID
        )
        return CalendarEpochFixture(
            provider: provider,
            session: session,
            clock: clock,
            formatter: formatter,
            losAngeles: losAngeles,
            tokyo: tokyo,
            accountA: accountA,
            accountB: accountB,
            switched: switched
        )
    }

    private func account(
        _ id: String,
        in snapshot: ProviderSnapshot
    ) throws -> ProviderAccountUsage {
        try XCTUnwrap(snapshot.accounts?.first { $0.accountID == id })
    }

    private func assertConservation(
        _ snapshot: ProviderSnapshot,
        today: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let accountToday = (snapshot.accounts ?? []).reduce(0) {
            $0 + ($1.todayUsage.totalTokens ?? 0)
        }
        let accountDaily = (snapshot.accounts ?? []).reduce(0) {
            $0 + ($1.dailyTotals?.values.reduce(0, +) ?? 0)
        }
        XCTAssertEqual(snapshot.todayUsage.totalTokens, today, file: file, line: line)
        XCTAssertEqual(accountToday, today, file: file, line: line)
        XCTAssertEqual(
            accountDaily,
            snapshot.dailyTotals?.values.reduce(0, +),
            file: file,
            line: line
        )
    }

    private func appendTokyoRollover(to fixture: CalendarEpochFixture) throws {
        fixture.clock.set(try XCTUnwrap(
            fixture.formatter.date(from: "2026-09-17T15:16:40Z")
        ))
        try writeSession(
            "session-b.jsonl",
            to: fixture.session.deletingLastPathComponent().deletingLastPathComponent(),
            events: [codexEvent(
                totalTokens: 5,
                lastTokens: 5,
                timestamp: "2026-09-17T15:15:00Z"
            )]
        )
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
        // A3: pin the provider clock so parsed rate-limit observations are freshness-testable.
        let now = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 7,
            day: 6,
            hour: 11,
            minute: 15
        ))!
        let parser = CodexJSONLParser(calendar: calendar, now: { now })
        let provider = CodexProvider(parser: parser, codexDirectory: codex, now: { now })
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
        // R09-04: the expired session sibling makes the provider headline ineligible,
        // while the historical account row still exposes both parsed windows.
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertEqual(snapshot.accounts?.first?.quotaWindows.count, 2)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }
}

extension CodexProviderTests {
    func testR09C_01_identityEpochOwnershipSurvivesCalendarChangesAndTokyoRollover() async throws {
        let fixture = try await makeCalendarEpochFixture()
        assertConservation(fixture.switched, today: 10)
        XCTAssertEqual(try account(fixture.accountA, in: fixture.switched).todayUsage.totalTokens, 10)
        XCTAssertEqual(try account(fixture.accountB, in: fixture.switched).todayUsage.totalTokens, 0)

        await fixture.provider.updateCalendar(fixture.tokyo)
        let inTokyo = try await fixture.provider.fetchSnapshot()
        let tokyoFirstDay = fixture.tokyo.startOfDay(
            for: try XCTUnwrap(fixture.formatter.date(from: "2026-09-17T02:14:00Z"))
        )
        assertConservation(inTokyo, today: 10)
        XCTAssertEqual(try account(fixture.accountA, in: inTokyo).todayUsage.totalTokens, 10)
        XCTAssertEqual(try account(fixture.accountB, in: inTokyo).todayUsage.totalTokens, 0)
        XCTAssertEqual(try account(fixture.accountA, in: inTokyo).dailyTotals?[tokyoFirstDay], 10)
        XCTAssertEqual(try account(fixture.accountB, in: inTokyo).dailyTotals?[tokyoFirstDay] ?? 0, 0)

        await fixture.provider.updateCalendar(fixture.losAngeles)
        let backInLosAngeles = try await fixture.provider.fetchSnapshot()
        assertConservation(backInLosAngeles, today: 10)
        XCTAssertEqual(try account(fixture.accountA, in: backInLosAngeles).todayUsage.totalTokens, 10)
        XCTAssertEqual(try account(fixture.accountB, in: backInLosAngeles).todayUsage.totalTokens, 0)

        await fixture.provider.updateCalendar(fixture.tokyo)
        try appendTokyoRollover(to: fixture)
        let afterTokyoRollover = try await fixture.provider.fetchSnapshot()
        let tokyoSecondDay = fixture.tokyo.startOfDay(
            for: try XCTUnwrap(fixture.formatter.date(from: "2026-09-17T15:15:00Z"))
        )
        assertConservation(afterTokyoRollover, today: 5)
        XCTAssertEqual(try account(fixture.accountA, in: afterTokyoRollover).todayUsage.totalTokens, 0)
        XCTAssertEqual(try account(fixture.accountB, in: afterTokyoRollover).todayUsage.totalTokens, 5)
        XCTAssertEqual(
            try account(fixture.accountA, in: afterTokyoRollover).dailyTotals?[tokyoFirstDay],
            10
        )
        XCTAssertEqual(
            try account(fixture.accountB, in: afterTokyoRollover).dailyTotals?[tokyoSecondDay],
            5
        )
    }

    func testR09D_01_deletingOldIdentitySessionPreservesRemainingFileOwnership() async throws {
        let codex = codexDirectory()
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let clock = CodexProviderTestClock(try XCTUnwrap(formatter.date(from: "2026-09-17T02:16:40Z")))
        try writeIdentity("acct-a", to: codex)
        let sessionA = try writeSession("session-a.jsonl", to: codex, events: [codexEvent(
            totalTokens: 10,
            lastTokens: 10,
            timestamp: "2026-09-17T02:14:00Z"
        )])
        let provider = CodexProvider(
            parser: CodexJSONLParser(calendar: utcCalendar(), now: { clock.read() }),
            codexDirectory: codex,
            environment: [:],
            now: { clock.read() }
        )
        let initial = try await provider.fetchSnapshot()
        let accountA = try XCTUnwrap(initial.accounts?.first?.accountID)

        try writeIdentity("acct-b", to: codex)
        let switched = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(switched.accounts?.first { $0.accountID != accountA }?.accountID)
        clock.set(try XCTUnwrap(formatter.date(from: "2026-09-18T02:16:40Z")))
        try writeSession("session-b.jsonl", to: codex, events: [codexEvent(
            totalTokens: 5,
            lastTokens: 5,
            timestamp: "2026-09-18T02:15:00Z",
            usedPercent: 35
        )])

        let beforeDeletion = try await provider.fetchSnapshot()
        assertConservation(beforeDeletion, today: 5)
        XCTAssertEqual(try account(accountA, in: beforeDeletion).todayUsage.totalTokens, 0)
        XCTAssertEqual(try account(accountB, in: beforeDeletion).todayUsage.totalTokens, 5)
        XCTAssertEqual(try account(accountA, in: beforeDeletion).dailyTotals?.values.reduce(0, +), 10)
        XCTAssertEqual(try account(accountB, in: beforeDeletion).dailyTotals?.values.reduce(0, +), 5)

        try FileManager.default.removeItem(at: sessionA)
        for _ in 0..<2 {
            let afterDeletion = try await provider.fetchSnapshot()
            assertConservation(afterDeletion, today: 5)
            XCTAssertEqual(try account(accountA, in: afterDeletion).todayUsage.totalTokens, 0)
            XCTAssertEqual(try account(accountB, in: afterDeletion).todayUsage.totalTokens, 5)
            let deletedTotal = try account(accountA, in: afterDeletion).dailyTotals?.values.reduce(0, +)
            let retainedTotal = try account(accountB, in: afterDeletion).dailyTotals?.values.reduce(0, +)
            XCTAssertEqual(deletedTotal, 0)
            XCTAssertEqual(retainedTotal, 5)
        }
    }

    func testPerFileOwnershipAttributesStraddlingSessionToIdentityAtFirstEvent() async throws {
        let formatter = ISO8601DateFormatter()
        let clock = CodexProviderTestClock(try XCTUnwrap(formatter.date(from: "2026-09-17T02:16:40Z")))
        let codex = codexDirectory()
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try writeIdentity("acct-a", to: codex)
        let session = try writeSession("straddling.jsonl", to: codex, events: [codexEvent(
            totalTokens: 10,
            lastTokens: 10,
            timestamp: "2026-09-17T02:14:00Z"
        )])
        let provider = CodexProvider(
            parser: CodexJSONLParser(calendar: utcCalendar(), now: { clock.read() }),
            codexDirectory: codex,
            environment: [:],
            now: { clock.read() }
        )
        let initial = try await provider.fetchSnapshot()
        let accountA = try XCTUnwrap(initial.accounts?.first?.accountID)
        try writeIdentity("acct-b", to: codex)
        let switched = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(switched.accounts?.first { $0.accountID != accountA }?.accountID)

        try Data([
            codexEvent(
                totalTokens: 10,
                lastTokens: 10,
                timestamp: "2026-09-17T02:14:00Z"
            ),
            codexEvent(
                totalTokens: 15,
                lastTokens: 5,
                timestamp: "2026-09-17T02:17:00Z",
                usedPercent: 35
            )
        ].joined(separator: "\n").utf8).write(to: session, options: .atomic)
        clock.set(try XCTUnwrap(formatter.date(from: "2026-09-17T02:17:00Z")))
        let straddled = try await provider.fetchSnapshot()

        assertConservation(straddled, today: 15)
        XCTAssertEqual(try account(accountA, in: straddled).todayUsage.totalTokens, 15)
        XCTAssertEqual(try account(accountB, in: straddled).todayUsage.totalTokens, 0)
        XCTAssertEqual(try account(accountB, in: straddled).quotaStatus, .eligible)
    }
}
