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

    func testProviderPricesOnlyCurrentCalendarMonthAndRetainsBothMonths() async throws {
        let reference = Date()
        let calendar = Calendar.current
        let month = try XCTUnwrap(calendar.dateInterval(of: .month, for: reference))
        let previous = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: month.start))
        let formatter = ISO8601DateFormatter()
        try write(shutdown(formatter.string(from: previous), input: 1_000_000, output: 0) + "\n"
                  + shutdown(formatter.string(from: month.start), input: 2_000_000, output: 0))
        let parser = CopilotSessionParser(sessionStateDirectory: directory, calendar: calendar, now: { reference })
        let provider = CopilotProvider(installationMarkers: [], extensionDirectories: [], sessionParser: parser,
                                       calendar: calendar, now: { reference })
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(try XCTUnwrap(snapshot.costUsage?.amount), 2, accuracy: 0.000001)
        XCTAssertEqual(snapshot.dailyModelUsage?.count, 2)
        XCTAssertEqual(snapshot.lifetimeUsage?.inputTokens, 2_000_000)
    }

    func testDailyModelMapKeeps92DaysWithoutLosingOlderResumeBaseline() async throws {
        let reference = Date(timeIntervalSince1970: 1_793_188_800)
        let today = calendar.startOfDay(for: reference)
        let offsets = [-93, -92, -91, -28, 0]
        let rows = try offsets.enumerated().map { index, offset in
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
            return shutdown(ISO8601DateFormatter().string(from: day), input: (index + 1) * 100, output: 0)
        }
        try write(rows.joined(separator: "\n"))
        let result = await parser().parse()
        let expected = try Set([-91, -28, 0].map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: today))
        })
        XCTAssertEqual(Set(result.dailyModelUsage.keys), expected)
        XCTAssertEqual(result.lifetime.inputTokens, 500)
        XCTAssertEqual(result.dailyModelUsage.values.reduce(0) { $0 + ($1["gpt-6.1-sol"]?.inputTokens ?? 0) }, 300)
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
        try handle.write(contentsOf: Data((shutdown("2026-10-28T11:00:00Z", input: 150, output: 80) + "\n").utf8))
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

    func testDottedClaudeModelsKeepTheirUsageKeysAndPriceInTheProvider() async throws {
        let record = #"{"type":"session.shutdown","timestamp":"2026-10-28T10:00:00Z","data":{"modelMetrics":{ "#
            + #""claude-sonnet-4.6":{"usage":{"inputTokens":1000000,"outputTokens":100000}},"#
            + #""claude-opus-5.5":{"usage":{"inputTokens":1000000,"outputTokens":100000}}}}}"#
        try write(record)
        let provider = CopilotProvider(installationMarkers: [], extensionDirectories: [], sessionParser: parser())
        let snapshot = try await provider.fetchSnapshot()
        let models = try XCTUnwrap(snapshot.dailyModelUsage?.values.first)
        XCTAssertEqual(Set(models.keys), ["claude-sonnet-4.6", "claude-opus-5.5"])
        // Sonnet: $3 input + $1.50 output. Opus: $4 input + $2 output.
        XCTAssertEqual(try XCTUnwrap(snapshot.costUsage?.amount), 10.5, accuracy: 0.000001)
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
        try (shutdown("2026-10-28T11:00:00Z", input: 100, output: 50) + "\n")
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

    func testIndependentPythonRecountMatchesHandCountedResumedFixture() async throws {
        let first = shutdown("2026-10-27T12:00:00Z", input: 100, output: 30,
                             components: ["cacheReadTokens": 20, "cacheWriteTokens": 10, "reasoningTokens": 10])
        let corrected = shutdown("2026-10-28T10:00:00Z", input: 100, output: 30,
                                 components: ["cacheReadTokens": 20, "cacheWriteTokens": 10, "reasoningTokens": 15])
        let resumed = shutdown("2026-10-28T11:00:00Z", input: 160, output: 50,
                               components: ["cacheReadTokens": 30, "cacheWriteTokens": 10, "reasoningTokens": 20])
        try write([first, corrected, resumed, resumed].joined(separator: "\n"))
        let parsed = await parser().parse()
        let reference = Date(timeIntervalSince1970: 1_793_188_800)
        let python = try WP1CopilotOracle.counts(root: directory, cutoff: reference)
        // 160 total prompt minus 30 read/10 written = 120 uncached; total = 160 + 50 = 210.
        let expected = ["shutdowns": 4, "input": 120, "cacheRead": 30, "cacheWrite": 10,
                        "output": 50, "reasoning": 20, "reportedInput": 160, "total": 210]
        XCTAssertEqual(python, expected)
        XCTAssertEqual(WP1CopilotOracle.counts(parsed), expected)
        XCTAssertEqual(parsed.today.totalTokens, 80)
    }

    func testUnterminatedTailWaitsForNewlineBeforeUsageOrMalformedWarning() async throws {
        let row = Data(shutdown("2026-10-28T11:00:00Z", input: 160, output: 80).utf8)
        let split = row.count / 2
        let fixtures: [CopilotTailFixture] = [
            .init(name: "partial JSON", prefix: Data(row.prefix(split)), suffix: Data(row.suffix(row.count - split)),
                  count: 2, input: 160, warnings: 0),
            .init(name: "valid JSON awaiting newline", prefix: row, suffix: Data(), count: 2, input: 160, warnings: 0),
            .init(name: "oversized unfinished line", prefix: Data(repeating: 0x78, count: 16 * 1024 * 1024 + 1),
                  suffix: Data(), count: 1, input: 100, warnings: 1),
            .init(name: "malformed unfinished shutdown", prefix: Data(#"{"type":"session.shutdown"}"#.utf8),
                  suffix: Data(), count: 1, input: 100, warnings: 1)
        ]
        for fixture in fixtures {
            let url = try write(shutdown("2026-10-28T10:00:00Z", input: 100, output: 50))
            try appendBytes(fixture.prefix, to: url)
            let parser = parser()
            let pending = await parser.parse()
            XCTAssertEqual(pending.shutdownCount, 1, fixture.name)
            XCTAssertEqual(pending.lifetime.inputTokens, 100, fixture.name)
            XCTAssertTrue(pending.warnings.isEmpty, fixture.name)
            try appendBytes(fixture.suffix + Data([0x0A]), to: url)
            let completed = await parser.parse()
            XCTAssertEqual(completed.shutdownCount, fixture.count, fixture.name)
            XCTAssertEqual(completed.lifetime.inputTokens, fixture.input, fixture.name)
            XCTAssertEqual(completed.warnings.count, fixture.warnings, fixture.name)
        }
    }

    private func appendBytes(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
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
        // Completed fixtures end with a newline; tail tests append their unfinished bytes directly.
        try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
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

private struct CopilotTailFixture {
    let name: String
    let prefix: Data
    let suffix: Data
    let count: Int
    let input: Int
    let warnings: Int
}

private final class CopilotReadCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
