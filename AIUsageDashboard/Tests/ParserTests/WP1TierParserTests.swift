import XCTest
@testable import AIUsageDashboardCore

final class WP1TierParserTests: XCTestCase {
    private var directory: URL!
    private var calendar: Calendar!
    private let now = Date(timeIntervalSince1970: 1_793_188_800)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testClaudeSplitSurvivesLargestCorrectionAndEveryWindow() async throws {
        let url = directory.appendingPathComponent("claude.jsonl")
        let text =
            (#"{"timestamp":"2026-10-28T10:00:00Z","message":{"id":"a","model":"claude-sonnet-4-6","usage":{"i"#
            + #"nput_tokens":100,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_1h_input_token"#
            + #"s":600}}}}"#)
            + "\n" + (#"{"timestamp":"2026-10-28T11:00:00Z","message":{"id":"a","model":"claude-sonnet-4-6","usage":{"i"#
            + #"nput_tokens":100,"output_tokens":20,"cache_creation_input_tokens":1000,"cache_creation":{"ephem"#
            + #"eral_1h_input_tokens":600}}}}"#)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let fixed = now
        let result = await ClaudeJSONLParser(calendar: calendar, now: { fixed })
            .parse(logSources: [LogSource(providerID: .claudeCode, url: url)])
        for usage in [result.today, result.week, result.month, result.lifetime] {
            XCTAssertEqual(usage.cacheCreation1hTokens, 600)
            XCTAssertEqual(usage.cacheCreationTokens, 1000)
            XCTAssertEqual(usage.totalTokens, 1120)
        }
        XCTAssertEqual(result.dailyModelUsage.values.first?["claude-sonnet-4-6"]?.cacheCreation1hTokens, 600)
    }

    func testClaudeFastIsSeparatedFromStandardModelTokens() async throws {
        let url = directory.appendingPathComponent("claude.jsonl")
        try (#"{"timestamp":"2026-10-28T10:00:00Z","message":{"id":"a","model":"claude-opus-5-5","usage":{"inp"#
            + #"ut_tokens":100,"speed":"fast"}}}"#)
            .write(to: url, atomically: true, encoding: .utf8)
        let fixed = now
        let result = await ClaudeJSONLParser(calendar: calendar, now: { fixed })
            .parse(logSources: [LogSource(providerID: .claudeCode, url: url)])
        XCTAssertEqual(result.dailyModelUsage.values.first?["claude-opus-5-5@fast"]?.inputTokens, 100)
    }

    func testCodexTierPersistsAcrossIncrementalAppendAndResetsToStandard() async throws {
        let url = directory.appendingPathComponent("codex.jsonl")
        let initial = #"{"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"# + "\n"
            + (#"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tie"#
            + #"r":"priority"}}}"#) + "\n"
        try initial.write(to: url, atomically: true, encoding: .utf8)
        let fixed = now
        let parser = CodexJSONLParser(calendar: calendar, now: { fixed })
        let sources = [LogSource(providerID: .codex, url: url)]
        _ = await parser.parse(logSources: sources)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let token = (#"{"timestamp":"2026-10-28T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"#
            + #""last_token_usage":{"input_tokens":100}}}}"#) + "\n"
        try handle.write(contentsOf: Data((token
            + (#"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tie"#
            + #"r":"default"}}}"#)
            + "\n" + token).utf8))
        try handle.close()
        let result = await parser.parse(logSources: sources)
        XCTAssertEqual(result.lifetimeModelUsage["gpt-6.1-sol@priority"]?.inputTokens, 100)
        XCTAssertEqual(result.lifetimeModelUsage["gpt-6.1-sol"]?.inputTokens, 100)
    }
}
