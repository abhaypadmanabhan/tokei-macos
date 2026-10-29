import SQLite3
import XCTest
@testable import AIUsageDashboardCore

final class AntigravityConversationParserTests: XCTestCase {
    private var directory: URL!
    private let timestamp: UInt64 = 1_793_181_600
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testUnionFindBridgesKeysAndUsesMaxBucketsAndDisplayName() async throws {
        let first = usage(input: 100, cached: 200, output: 30, response: "a")
        let bridge = first + text(12, "bridge")
        let third = usage(input: 150, cached: 100, output: 40, response: "b") + text(12, "bridge")
        try database("one.db", generations: [generation(bridge), generation(third)], steps: [step(first)])
        let result = await parser().parse()
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.lifetime.inputTokens, 150)
        XCTAssertEqual(result.lifetime.cacheReadTokens, 200)
        XCTAssertEqual(result.lifetime.outputTokens, 30)
        XCTAssertEqual(result.lifetime.reasoningTokens, 10)
        XCTAssertEqual(result.dailyModelUsage.values.first?["gemini-3.5-flash"]?.totalTokens, 390)
        XCTAssertTrue(result.warnings.isEmpty)
        for usage in [result.today, result.week, result.month] { XCTAssertEqual(usage.totalTokens, 390) }
    }

    func testRetriesCountOnceAndCorruptDatabaseMakesScanPartial() async throws {
        let primary = usage(input: 100, cached: 20, output: 30, response: "primary")
        let retry = usage(input: 50, cached: 10, output: 20, response: "retry")
        let attempts = bytes(17, bytes(2, primary)) + bytes(17, bytes(2, retry))
        try database("valid.db", generations: [generation(primary, extras: attempts)], steps: [step(primary)])
        try database("truncated.db", generations: [Data([10, 100, 0])], steps: [])
        let result = await parser().parse()
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.lifetime.inputTokens, 150)
        XCTAssertEqual(result.lifetime.cacheReadTokens, 30)
        XCTAssertEqual(result.lifetime.outputTokens, 30)
        XCTAssertEqual(result.lifetime.reasoningTokens, 20)
        XCTAssertTrue(result.warnings.contains { $0.message.contains("Some Antigravity history") })
    }

    func testUnchangedScanDoesNotCopyAndWALOnlyChangeInvalidatesCache() async throws {
        try database("one.db", generations: [generation(usage(input: 100, response: "a"))], steps: [])
        let calls = CopyCalls()
        let parser = AntigravityConversationParser(roots: [directory], calendar: calendar,
                                                  now: { Date(timeIntervalSince1970: 1_793_188_800) },
                                                  copier: { source, destination in
            calls.increment()
            try SQLiteSidecarCopy.copyDatabase(from: source, to: destination, using: .default)
        })
        _ = await parser.parse()
        _ = await parser.parse()
        XCTAssertEqual(calls.count, 1)
        // An actual WAL commit leaves the main database unchanged until checkpoint.
        var database: OpaquePointer?
        let url = directory.appendingPathComponent("one.db")
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA journal_mode=WAL", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "UPDATE gen_metadata SET idx=idx+1", nil, nil, nil), SQLITE_OK)
        _ = await parser.parse()
        XCTAssertEqual(calls.count, 2)
    }

    func testProtobufAcceptsUnknownMaxVarintAndRejectsTruncationAndBadUTF8() throws {
        let blob = varint(800) + Data(repeating: 255, count: 9) + Data([1])
        XCTAssertNoThrow(try AntigravityProtobuf(blob))
        XCTAssertThrowsError(try AntigravityProtobuf(Data([10, 2, 0])))
        XCTAssertThrowsError(try AntigravityProtobuf(Data([0])))
        XCTAssertThrowsError(try AntigravityProtobuf(bytes(1, Data([255]))).text(1))
    }

    func testProviderPublishesLocalTokensAndValueWithoutAQuotaSource() async throws {
        try database("one.db", generations: [generation(usage(input: 1_000_000, response: "a"))], steps: [])
        let suite = "ai.padzy.tokei.wp1.antigravity"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "antigravityOnlineQuotaEnabled")
        let provider = AntigravityProvider(stateDatabaseURL: directory.appendingPathComponent("missing-state"),
                                          conversationParser: parser(), userDefaults: defaults)
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.todayUsage.inputTokens, 1_000_000)
        XCTAssertEqual(snapshot.todayUsage.confidence, .localParsed)
        XCTAssertEqual(snapshot.dailyTotals?.values.first, 1_000_030)
        XCTAssertEqual(try XCTUnwrap(snapshot.costUsage?.amount), 1.50027, accuracy: 0.000001)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testUnpricedDisplayFallsBackToPricedSlugAndUnknownModelStaysUnpriced() async throws {
        let known = generation(usage(input: 100, response: "known"),
                               display: "Future marketing label", slug: "gemini-3.5-flash")
        let unknown = generation(usage(input: 50, response: "unknown"),
                                 display: "Future unpriced model", slug: "unknown-model")
        try database("one.db", generations: [known, unknown], steps: [])
        let result = await parser().parse()
        let models = try XCTUnwrap(result.dailyModelUsage.values.first)
        XCTAssertEqual(models["gemini-3.5-flash"]?.inputTokens, 100)
        XCTAssertEqual(models["future-unpriced-model"]?.inputTokens, 50)
        XCTAssertNil(PricingEngine().cost(model: "future-unpriced-model",
                                         tokens: try XCTUnwrap(models["future-unpriced-model"])))
    }

    func testCLIConversationHistoryEstablishesAvailabilityWithoutIDEState() async throws {
        try database("one.db", generations: [generation(usage(input: 100, response: "cli"))], steps: [])
        let provider = AntigravityProvider(stateDatabaseURL: directory.appendingPathComponent("missing-state"),
                                          conversationParser: parser())
        let availability = await provider.detectAvailability()
        XCTAssertEqual(availability, .installed)
    }

    func testCrossDatabaseModelLearningAndTransitiveDedupeUseNamedGeneration() async throws {
        try database("a.db", generations: [], steps: [step(usage(input: 100, response: "shared"))])
        try database("b.db", generations: [generation(usage(input: 150, response: "shared"))], steps: [])
        let result = await parser().parse()
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.dailyModelUsage.values.first?["gemini-3.5-flash"]?.inputTokens, 150)
    }

    private func parser() -> AntigravityConversationParser {
        AntigravityConversationParser(roots: [directory], calendar: calendar,
                                      now: { Date(timeIntervalSince1970: 1_793_188_800) })
    }

    private func database(_ name: String, generations: [Data], steps: [Data]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent(name).path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let schema = "CREATE TABLE gen_metadata(idx INTEGER, data BLOB);"
            + "CREATE TABLE steps(idx INTEGER, metadata BLOB, step_payload BLOB);"
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)
        for (table, rows, column) in [("gen_metadata", generations, "data"), ("steps", steps, "metadata")] {
            for (index, blob) in rows.enumerated() {
                let hex = blob.map { String(format: "%02x", $0) }.joined()
                let sql = "INSERT INTO \(table)(idx,\(column)) VALUES(\(index),X'\(hex)')"
                XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
            }
        }
    }

    private func generation(_ usage: Data, extras: Data = Data(),
                            display: String = "Gemini 3.5 Flash (Medium)",
                            slug: String = "gemini-3-flash-a") -> Data {
        bytes(1, integer(3, 1020) + text(19, slug) + text(21, display)
              + bytes(4, usage) + bytes(9, bytes(4, integer(1, timestamp))) + extras)
    }

    private func step(_ usage: Data) -> Data {
        bytes(9, usage) + bytes(8, integer(1, timestamp))
    }

    private func usage(input: UInt64, cached: UInt64 = 0, output: UInt64 = 30, response: String) -> Data {
        integer(1, 1020) + integer(2, input) + integer(3, output) + integer(5, cached)
            + integer(9, 10) + text(11, response)
    }

    private func integer(_ field: UInt64, _ value: UInt64) -> Data { varint(field << 3) + varint(value) }
    private func text(_ field: UInt64, _ value: String) -> Data { bytes(field, Data(value.utf8)) }
    private func bytes(_ field: UInt64, _ value: Data) -> Data {
        varint(field << 3 | 2) + varint(UInt64(value.count)) + value
    }
    private func varint(_ value: UInt64) -> Data {
        var value = value
        var result = Data()
        while value >= 128 { result.append(UInt8(value & 127) | 128); value >>= 7 }
        result.append(UInt8(value))
        return result
    }
}

private final class CopyCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
