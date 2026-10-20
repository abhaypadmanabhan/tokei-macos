import XCTest
@testable import AIUsageDashboardCore

private final class CodexFirstEventClock: @unchecked Sendable {
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

final class CodexFirstEventBoundsTests: XCTestCase {
    private struct Fixture {
        let parser: CodexJSONLParser
        let provider: CodexProvider
        let session: URL
        let clock: CodexFirstEventClock
        let accountA: String
        let accountB: String
    }

    private var tempDirectory: URL!
    private let formatter = ISO8601DateFormatter()

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

    func testR09E_01_sessionMetadataTimestampOwnsLaterUsage() async throws {
        let metadata = #"{"timestamp":"2026-09-17T02:13:00Z","type":"session_meta","payload":{"id":"session"}}"#
        try await assertFirstTimestampOwnsSession(initialEvents: [metadata], expectedLifetime: 10)
    }

    func testR09E_01_userEventTimestampOwnsLaterUsage() async throws {
        let userEvent = #"{"timestamp":"2026-09-17T02:13:00Z","type":"event_msg","payload":{"type":"user_message"}}"#
        try await assertFirstTimestampOwnsSession(initialEvents: [userEvent], expectedLifetime: 10)
    }

    func testR09E_01_untimedUsageAfterTimestampedMetadataDoesNotMoveFileStart() async throws {
        let metadata = #"{"timestamp":"2026-09-17T02:13:00Z","type":"session_meta","payload":{"id":"session"}}"#
        try await assertFirstTimestampOwnsSession(
            initialEvents: [metadata, tokenEvent(tokens: 3, timestamp: nil)],
            expectedLifetime: 13
        )
    }

    private func assertFirstTimestampOwnsSession(
        initialEvents: [String],
        expectedLifetime: Int
    ) async throws {
        let fixture = try await makeSwitchedFixture(initialEvents: initialEvents)
        try append(tokenEvent(tokens: 10, timestamp: "2026-09-17T02:17:00Z"), to: fixture.session)
        fixture.clock.set(try date("2026-09-17T02:17:00Z"))

        let appended = try await fixture.provider.fetchSnapshot()
        try assertOwnership(appended, fixture: fixture, expectedLifetime: expectedLifetime)

        let aggregate = await fixture.parser.parse(logSources: [
            LogSource(providerID: .codex, url: fixture.session, sessionID: "first-event")
        ])
        XCTAssertEqual(aggregate.files.first?.firstEventAt, try date("2026-09-17T02:13:00Z"))

        var tokyo = utcCalendar()
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        await fixture.provider.updateCalendar(tokyo)
        let rebuilt = try await fixture.provider.fetchSnapshot()
        try assertOwnership(rebuilt, fixture: fixture, expectedLifetime: expectedLifetime)
    }

    private func makeSwitchedFixture(initialEvents: [String]) async throws -> Fixture {
        let codex = tempDirectory.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codex.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try writeIdentity("acct-a", to: codex)
        let session = sessions.appendingPathComponent("first-event.jsonl")
        try Data(initialEvents.joined(separator: "\n").utf8).write(to: session, options: .atomic)
        let clock = CodexFirstEventClock(try date("2026-09-17T02:14:00Z"))
        let parser = CodexJSONLParser(calendar: utcCalendar(), now: { clock.read() })
        let provider = CodexProvider(
            parser: parser,
            codexDirectory: codex,
            environment: [:],
            now: { clock.read() }
        )
        let initial = try await provider.fetchSnapshot()
        let accountA = try XCTUnwrap(initial.accounts?.first?.accountID)

        clock.set(try date("2026-09-17T02:16:40Z"))
        try writeIdentity("acct-b", to: codex)
        let switched = try await provider.fetchSnapshot()
        let accountB = try XCTUnwrap(
            switched.accounts?.first { $0.accountID != accountA }?.accountID
        )
        return Fixture(
            parser: parser,
            provider: provider,
            session: session,
            clock: clock,
            accountA: accountA,
            accountB: accountB
        )
    }

    private func assertOwnership(
        _ snapshot: ProviderSnapshot,
        fixture: Fixture,
        expectedLifetime: Int
    ) throws {
        let accounts = try XCTUnwrap(snapshot.accounts)
        let accountA = try XCTUnwrap(accounts.first { $0.accountID == fixture.accountA })
        let accountB = try XCTUnwrap(accounts.first { $0.accountID == fixture.accountB })
        XCTAssertEqual(snapshot.todayUsage.totalTokens, 10)
        XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, expectedLifetime)
        XCTAssertEqual(accounts.reduce(0) { $0 + ($1.todayUsage.totalTokens ?? 0) }, 10)
        XCTAssertEqual(accountA.todayUsage.totalTokens, 10)
        XCTAssertEqual(accountB.todayUsage.totalTokens, 0)
    }

    private func tokenEvent(tokens: Int, timestamp: String?) -> String {
        let timestampField = timestamp.map { #""timestamp":"\#($0)","# } ?? ""
        return "{\(timestampField)\"type\":\"event_msg\",\"payload\":{" +
            "\"type\":\"token_count\",\"info\":{\"last_token_usage\":{" +
            "\"input_tokens\":\(tokens),\"total_tokens\":\(tokens)}}}}"
    }

    private func append(_ event: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + event).utf8))
        try handle.close()
    }

    private func writeIdentity(_ identity: String, to codex: URL) throws {
        let data = Data(#"{"tokens":{"account_id":"\#(identity)"}}"#.utf8)
        try data.write(to: codex.appendingPathComponent("auth.json"), options: .atomic)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(formatter.date(from: value))
    }
}
