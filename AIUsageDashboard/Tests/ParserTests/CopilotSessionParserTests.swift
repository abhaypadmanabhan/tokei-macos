import XCTest
@testable import AIUsageDashboardCore

final class CopilotSessionParserTests: XCTestCase {
    private var directory: URL!
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testResumeCountsOnlyDeltaOnShutdownDayAndSeparatesModels() async throws {
        let first = shutdown("2026-10-27T12:00:00Z", input: 100, output: 50)
        let resumed = shutdown("2026-10-28T10:00:00Z", input: 160, output: 70)
        try write(first + "\n" + resumed + "\n" + resumed)
        let result = await parser().parse()
        XCTAssertEqual(result.today.inputTokens, 60)
        XCTAssertEqual(result.today.outputTokens, 20)
        XCTAssertEqual(result.week.inputTokens, 160)
        XCTAssertEqual(result.lifetime.outputTokens, 70)
        XCTAssertEqual(result.dailyModelUsage.count, 2)
        XCTAssertEqual(result.shutdownCount, 3)
        XCTAssertEqual(result.dailyTotals[calendar.startOfDay(for: Date(timeIntervalSince1970: 1_793_188_800))], 80)
    }

    func testUnchangedFingerprintSkipsReaderAndAppendCountsOnlyNewDelta() async throws {
        let url = try write(shutdown("2026-10-28T10:00:00Z", input: 100, output: 50))
        let calls = CopilotReadCalls()
        let parser = CopilotSessionParser(sessionStateDirectory: directory, calendar: calendar,
                                          now: { Date(timeIntervalSince1970: 1_793_188_800) },
                                          chunkReader: { handle in
            calls.increment()
            return try handle.read(upToCount: 64 * 1024)
        })
        _ = await parser.parse()
        let initialReads = calls.count
        XCTAssertGreaterThan(initialReads, 0)
        _ = await parser.parse()
        XCTAssertEqual(calls.count, initialReads)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + shutdown("2026-10-28T11:00:00Z", input: 150, output: 80)).utf8))
        try handle.close()
        let result = await parser.parse()
        XCTAssertGreaterThan(calls.count, initialReads)
        XCTAssertEqual(result.lifetime.inputTokens, 150)
        XCTAssertEqual(result.lifetime.outputTokens, 80)
    }

    func testOversizedRecordIsDiscardedAndSymlinkIsNeverRead() async throws {
        let url = try write(String(repeating: "x", count: 16 * 1024 * 1024 + 1)
                            + "\n" + shutdown("2026-10-28T10:00:00Z", input: 100, output: 50))
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias.appendingPathComponent("events.jsonl"),
                                                   withDestinationURL: url)
        let result = await parser().parse()
        XCTAssertEqual(result.lifetime.inputTokens, 100)
        XCTAssertEqual(result.shutdownCount, 1)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testPerModelHighWaterAndReasoningSubset() async throws {
        let record = #"{"type":"session.shutdown","timestamp":"2026-10-28T10:00:00Z","data":{"modelMetrics":{ "#
            + #""gpt-6.1-sol":{"usage":{"inputTokens":100,"outputTokens":30,"reasoningTokens":10}},"#
            + #""unpriced-model":{"usage":{"inputTokens":50,"cacheReadTokens":20,"cacheWriteTokens":5}}}}}"#
        try write(record)
        let result = await parser().parse()
        let models = try XCTUnwrap(result.dailyModelUsage.values.first)
        XCTAssertEqual(models["gpt-6.1-sol"]?.outputTokens, 20)
        XCTAssertEqual(models["gpt-6.1-sol"]?.reasoningTokens, 10)
        // 50 total prompt tokens contain 20 cache reads and 5 writes.
        XCTAssertEqual(models["unpriced-model"]?.inputTokens, 25)
        XCTAssertEqual(models["unpriced-model"]?.totalTokens, 50)
    }

    func testProviderPricesCLIModelAndPublishesLocalDailyUsage() async throws {
        try write(shutdown("2026-10-28T10:00:00Z", input: 1_000_000, output: 100_000))
        let provider = CopilotProvider(installationMarkers: [], extensionDirectories: [], sessionParser: parser())
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.todayUsage.inputTokens, 1_000_000)
        XCTAssertEqual(snapshot.todayUsage.confidence, .localParsed)
        XCTAssertEqual(try XCTUnwrap(snapshot.costUsage?.amount), 3, accuracy: 0.000001)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        XCTAssertFalse(snapshot.warnings.contains { $0.message.contains("unavailable") })
    }

    func testCacheSubsetsAndLaterReasoningCorrectionDoNotAddTokens() async throws {
        let first = shutdown("2026-10-27T12:00:00Z", input: 100, output: 30,
                             components: ["cacheReadTokens": 20, "cacheWriteTokens": 10, "reasoningTokens": 10])
        let corrected = shutdown("2026-10-28T10:00:00Z", input: 100, output: 30,
                                 components: ["cacheReadTokens": 20, "cacheWriteTokens": 10, "reasoningTokens": 15])
        try write(first + "\n" + corrected)
        let result = await parser().parse()
        XCTAssertEqual(result.lifetime.inputTokens, 70)
        XCTAssertEqual(result.lifetime.cacheReadTokens, 20)
        XCTAssertEqual(result.lifetime.cacheCreationTokens, 10)
        XCTAssertEqual(result.lifetime.outputTokens, 15)
        XCTAssertEqual(result.lifetime.reasoningTokens, 15)
        XCTAssertEqual(result.lifetime.totalTokens, 130)
        XCTAssertEqual(result.today.totalTokens, 0)
    }

    func testIndependentSessionsAndModelsDoNotShareCumulativeCounters() async throws {
        try write(shutdown("2026-10-28T10:00:00Z", input: 100, output: 50))
        let second = directory.appendingPathComponent("session-2")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try shutdown("2026-10-28T11:00:00Z", input: 100, output: 50)
            .write(to: second.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        let result = await parser().parse()
        XCTAssertEqual(result.lifetime.inputTokens, 200)
        XCTAssertEqual(result.lifetime.outputTokens, 100)
        XCTAssertEqual(result.shutdownCount, 2)
    }

    func testUnchangedFailedReadIsCachedUntilTheFileChanges() async throws {
        try write(shutdown("2026-10-28T10:00:00Z", input: 100, output: 50))
        let calls = CopilotReadCalls()
        let parser = CopilotSessionParser(sessionStateDirectory: directory, chunkReader: { _ in
            calls.increment()
            throw CocoaError(.fileReadUnknown)
        })
        let first = await parser.parse()
        let second = await parser.parse()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(first.warnings.count, 1)
        XCTAssertEqual(second.warnings.count, 1)
        XCTAssertEqual(second.lifetime.confidence, .unavailable)
    }

    func testSixteenMiBRecordAtBoundaryIsAccepted() async throws {
        let prefix = #"{"type":"ignored","padding":""#
        let suffix = #""}"#
        let padding = 16 * 1024 * 1024 - prefix.utf8.count - suffix.utf8.count
        try write(prefix + String(repeating: "x", count: padding) + suffix + "\n"
                  + shutdown("2026-10-28T10:00:00Z", input: 100, output: 50))
        let result = await parser().parse()
        XCTAssertEqual(result.shutdownCount, 1)
        XCTAssertEqual(result.lifetime.totalTokens, 150)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    private func parser() -> CopilotSessionParser {
        CopilotSessionParser(sessionStateDirectory: directory, calendar: calendar,
                             now: { Date(timeIntervalSince1970: 1_793_188_800) })
    }

    @discardableResult
    private func write(_ text: String) throws -> URL {
        let session = directory.appendingPathComponent("session-1")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let url = session.appendingPathComponent("events.jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func shutdown(_ timestamp: String, input: Int, output: Int,
                          components: [String: Int] = [:]) -> String {
        var usage = components
        usage["inputTokens"] = input
        usage["outputTokens"] = output
        let fields = usage.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        return "{\"type\":\"session.shutdown\",\"timestamp\":\"\(timestamp)\",\"data\":{\"modelMetrics\":{"
            + "\"gpt-6.1-sol\":{\"usage\":{\(fields)}}}}}"
    }

}

private final class CopilotReadCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
