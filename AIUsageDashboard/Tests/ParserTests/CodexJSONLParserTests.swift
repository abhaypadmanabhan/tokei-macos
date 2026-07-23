import XCTest
@testable import AIUsageDashboardCore

final class CodexJSONLParserTests: XCTestCase {
    private var tempDirectory: URL!
    private var utcCalendar: Calendar!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func writeFixture(_ content: String, named: String) -> URL {
        let url = tempDirectory.appendingPathComponent(named)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeSource(url: URL, sessionID: String = "codex-session") -> LogSource {
        LogSource(providerID: .codex, url: url, sessionID: sessionID)
    }

    private func makeSourceWithModificationDate(
        url: URL,
        sessionID: String = "codex-session"
    ) -> LogSource {
        let modificationDate = try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        return LogSource(
            providerID: .codex,
            url: url,
            sessionID: sessionID,
            lastModified: modificationDate
        )
    }

    private func referenceNow() -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 6
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: comps)!
    }

    private func date(_ dayString: String, hour: Int) -> Date {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        return utcCalendar.date(from: DateComponents(
            timeZone: utcCalendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: hour
        ))!
    }

    private func isoString(_ date: Date) -> String {
        let comps = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                      comps.year!, comps.month!, comps.day!,
                      comps.hour!, comps.minute!, comps.second!)
    }

    private func makeParser(now: Date? = nil) -> CodexJSONLParser {
        let fixed = now ?? referenceNow()
        return CodexJSONLParser(calendar: utcCalendar, now: { fixed })
    }

    private func tokenCountLine(
        timestamp: String,
        delta: Int,
        cumulative: Int,
        rateLimitUsedPercent: Double
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulative),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(cumulative)},"last_token_usage":{"input_tokens":\(delta),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(delta)}},"rate_limits":{"plan_type":"plus","primary":{"used_percent":\(rateLimitUsedPercent),"limit_window_seconds":18000,"resets_at":1783324383},"secondary":null}}}
        """
    }

    private func appendLine(_ line: String, to url: URL) throws {
        try appendContent("\n\(line)", to: url)
    }

    private func appendContent(_ content: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(Data(content.utf8))
    }

    private func assertEqual(
        _ actual: CodexJSONLParser.AggregateUsage,
        _ expected: CodexJSONLParser.AggregateUsage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertEqual(actual.today, expected.today, file: file, line: line)
        assertEqual(actual.week, expected.week, file: file, line: line)
        assertEqual(actual.month, expected.month, file: file, line: line)
        assertEqual(actual.lifetime, expected.lifetime, file: file, line: line)
        XCTAssertEqual(actual.dailyTotals, expected.dailyTotals, file: file, line: line)
        XCTAssertEqual(actual.hourlyTotals, expected.hourlyTotals, file: file, line: line)
        XCTAssertEqual(
            actual.deltaReportedTotalTokens,
            expected.deltaReportedTotalTokens,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.finalReportedTotalTokens,
            expected.finalReportedTotalTokens,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.quotaWindows.count, expected.quotaWindows.count, file: file, line: line)
        for (actualWindow, expectedWindow) in zip(actual.quotaWindows, expected.quotaWindows) {
            XCTAssertEqual(actualWindow.id, expectedWindow.id, file: file, line: line)
            XCTAssertEqual(actualWindow.used, expectedWindow.used, file: file, line: line)
            XCTAssertEqual(actualWindow.limit, expectedWindow.limit, file: file, line: line)
            XCTAssertEqual(actualWindow.remaining, expectedWindow.remaining, file: file, line: line)
            XCTAssertEqual(actualWindow.resetAt, expectedWindow.resetAt, file: file, line: line)
            XCTAssertEqual(actualWindow.confidence, expectedWindow.confidence, file: file, line: line)
            XCTAssertEqual(actualWindow.source, expectedWindow.source, file: file, line: line)
        }
        XCTAssertEqual(actual.warnings.map(\.message), expected.warnings.map(\.message), file: file, line: line)
        XCTAssertEqual(actual.warnings.map(\.level), expected.warnings.map(\.level), file: file, line: line)
    }

    private func assertEqual(
        _ actual: TokenUsage,
        _ expected: TokenUsage,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.inputTokens, expected.inputTokens, file: file, line: line)
        XCTAssertEqual(actual.outputTokens, expected.outputTokens, file: file, line: line)
        XCTAssertEqual(actual.cacheReadTokens, expected.cacheReadTokens, file: file, line: line)
        XCTAssertEqual(actual.cacheCreationTokens, expected.cacheCreationTokens, file: file, line: line)
        XCTAssertEqual(actual.reasoningTokens, expected.reasoningTokens, file: file, line: line)
        XCTAssertEqual(actual.confidence, expected.confidence, file: file, line: line)
    }

    func testParsesTokenCountDeltasWithFractionalTimestamps() async {
        let url = writeFixture(CodexFixtures.twoTokenCountEvents(), named: "codex.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.lifetime.inputTokens, 125)
        XCTAssertEqual(usage.lifetime.outputTokens, 40)
        XCTAssertEqual(usage.lifetime.cacheReadTokens, 25)
        XCTAssertEqual(usage.lifetime.reasoningTokens, 10)
        XCTAssertEqual(usage.lifetime.totalTokens, 200)
        XCTAssertEqual(usage.deltaReportedTotalTokens, 200)
        XCTAssertEqual(usage.finalReportedTotalTokens, 200)
        XCTAssertEqual(usage.today.totalTokens, 200)
        XCTAssertEqual(usage.week.totalTokens, 200)
        XCTAssertEqual(usage.month.totalTokens, 200)
    }

    func testSkipsNonTokenCountLines() async {
        let url = writeFixture(CodexFixtures.ignoredEvent, named: "ignored.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.lifetime.totalTokens, 0)
        XCTAssertTrue(usage.quotaWindows.isEmpty)
        XCTAssertTrue(usage.warnings.isEmpty)
    }

    func testBucketsDailyTotalsByEventTimestamp() async {
        let now = referenceNow()
        let url = writeFixture(CodexFixtures.windowBucketLines(referenceNow: now), named: "windows.jsonl")
        let usage = await makeParser(now: now).parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.lifetime.totalTokens, 100)
        XCTAssertEqual(usage.today.totalTokens, 10)
        XCTAssertEqual(usage.week.totalTokens, 30)
        XCTAssertEqual(usage.month.totalTokens, 60)

        let todayStart = utcCalendar.startOfDay(for: now)
        let weekDay = utcCalendar.startOfDay(for: utcCalendar.date(byAdding: .day, value: -3, to: todayStart)!)
        let monthDay = utcCalendar.startOfDay(for: utcCalendar.date(byAdding: .day, value: -20, to: todayStart)!)
        XCTAssertEqual(usage.dailyTotals[todayStart], 10)
        XCTAssertEqual(usage.dailyTotals[weekDay], 20)
        XCTAssertEqual(usage.dailyTotals[monthDay], 30)
    }

    func testBucketsHourlyTotalsWithinFourteenDayWindow() async {
        let hour = date("2026-07-06", hour: 5)
        let sameHour = hour.addingTimeInterval(30 * 60)
        let oldHour = date("2026-06-20", hour: 5)

        func line(total: Int, timestamp: Date) -> String {
            """
            {"timestamp":"\(isoString(timestamp))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(total)},"last_token_usage":{"input_tokens":\(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(total)}},"rate_limits":null}}
            """
        }

        let url = writeFixture([
            line(total: 10, timestamp: hour),
            line(total: 20, timestamp: sameHour),
            line(total: 40, timestamp: oldHour),
        ].joined(separator: "\n"), named: "hourly.jsonl")

        let usage = await makeParser(now: referenceNow()).parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.hourlyTotals?[hour], 30)
        XCTAssertNil(usage.hourlyTotals?[oldHour])
        XCTAssertEqual(usage.hourlyTotals?.values.reduce(0, +), 30)
    }

    func testMapsQuotaWindowsFromNewestRateLimits() async {
        let url = writeFixture(CodexFixtures.twoTokenCountEvents(), named: "quota.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.quotaWindows.count, 2)
        let session = usage.quotaWindows.first { $0.type == .session }
        let weekly = usage.quotaWindows.first { $0.type == .weekly }

        XCTAssertEqual(session?.used, 12.5)
        XCTAssertEqual(session?.limit, 100)
        XCTAssertEqual(session?.remaining, 87.5)
        XCTAssertEqual(session?.resetAt, Date(timeIntervalSince1970: 1_783_324_383))
        XCTAssertEqual(session?.confidence, .providerReported)
        XCTAssertTrue(session?.source.contains("plus plan") == true)
        XCTAssertTrue(session?.source.contains("5h window") == true)

        XCTAssertEqual(weekly?.used, 33.0)
        XCTAssertEqual(weekly?.remaining, 67.0)
        XCTAssertEqual(weekly?.resetAt, Date(timeIntervalSince1970: 1_783_457_462))
        XCTAssertEqual(weekly?.confidence, .providerReported)
        XCTAssertTrue(weekly?.source.contains("weekly window") == true)
    }

    func testClassifiesWeeklyWindowInPrimarySlotByDuration() async {
        let url = writeFixture(CodexFixtures.weeklyInPrimarySlot(), named: "weekly-primary.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.quotaWindows.count, 1)
        let weekly = usage.quotaWindows.first { $0.type == .weekly }
        XCTAssertNotNil(weekly)
        XCTAssertNil(usage.quotaWindows.first { $0.type == .session })
        XCTAssertEqual(weekly?.used, 42.0)
        XCTAssertEqual(weekly?.remaining, 58.0)
        XCTAssertEqual(weekly?.resetAt, Date(timeIntervalSince1970: 1_783_457_462))
        XCTAssertTrue(weekly?.source.contains("free plan") == true)
        XCTAssertTrue(weekly?.source.contains("weekly window") == true)
    }

    func testClassifiesWindowsByLimitWindowSeconds() async {
        let url = writeFixture(CodexFixtures.limitWindowSecondsEvents(), named: "limit-seconds.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.quotaWindows.count, 2)
        let session = usage.quotaWindows.first { $0.type == .session }
        let weekly = usage.quotaWindows.first { $0.type == .weekly }
        XCTAssertEqual(session?.used, 15.0)
        XCTAssertEqual(weekly?.used, 25.0)
        XCTAssertTrue(session?.source.contains("5h window") == true)
        XCTAssertTrue(weekly?.source.contains("weekly window") == true)
    }

    func testSurfacesCreditsAndResetBankWhenPresent() async {
        let url = writeFixture(CodexFixtures.creditsAndResetBank(), named: "credits-reset.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.quotaWindows.count, 4)
        XCTAssertNotNil(usage.quotaWindows.first { $0.type == .session })
        XCTAssertNotNil(usage.quotaWindows.first { $0.type == .weekly })

        let monthlyCredits = usage.quotaWindows.first {
            $0.type == .credits && $0.bucketKey == "spend_control_individual_limit"
        }
        XCTAssertEqual(monthlyCredits?.label, "Monthly credit limit")
        XCTAssertEqual(monthlyCredits?.used, 32)
        XCTAssertEqual(monthlyCredits?.remaining, 68)
        XCTAssertEqual(monthlyCredits?.resetAt, Date(timeIntervalSince1970: 1_783_457_462))

        let resetBank = usage.quotaWindows.first {
            $0.type == .credits && $0.bucketKey == "reset_bank"
        }
        XCTAssertEqual(resetBank?.label, "Reset bank")
        XCTAssertEqual(resetBank?.remaining, 3)
        XCTAssertEqual(resetBank?.limit, 3)
    }

    func testPurchasableCreditsBalanceIsRemainingNotUsed() async {
        let url = writeFixture(CodexFixtures.purchasableCreditsBalanceOnly(), named: "credits-balance.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        let credits = usage.quotaWindows.first { $0.type == .credits && $0.bucketKey == "credits" }
        XCTAssertNotNil(credits, "purchasable credits window should surface from a balance")
        // The balance is credits REMAINING — it must never be stored as `used`
        // (else an 80-of-100-remaining balance renders as "80% used").
        XCTAssertNil(credits?.used)
        XCTAssertEqual(credits?.remaining, 80)
        XCTAssertEqual(credits?.limit, 100)
    }

    func testStaleQuotaWindowsAreEstimated() async {
        let url = writeFixture(CodexFixtures.staleRateLimits(), named: "stale.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.quotaWindows.count, 2)
        XCTAssertTrue(usage.quotaWindows.allSatisfy { $0.confidence == .estimated })
    }

    func testNullRateLimitFieldsDoNotCrash() async {
        let url = writeFixture(CodexFixtures.nullRateLimitFields(), named: "nulls.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.lifetime.totalTokens, 15)
        XCTAssertEqual(usage.quotaWindows.count, 1)
        XCTAssertNil(usage.quotaWindows[0].used)
        XCTAssertEqual(usage.quotaWindows[0].limit, 100)
        XCTAssertNil(usage.quotaWindows[0].remaining)
        XCTAssertNil(usage.quotaWindows[0].resetAt)
    }

    func testMalformedLinesProduceWarnings() async {
        let content = """
        \(CodexFixtures.twoTokenCountEvents())
        \(CodexFixtures.malformedLine)
        """
        let url = writeFixture(content, named: "malformed.jsonl")
        let usage = await makeParser().parse(logSources: [makeSource(url: url)])

        XCTAssertEqual(usage.lifetime.totalTokens, 200)
        XCTAssertEqual(usage.warnings.count, 1)
        XCTAssertTrue(usage.warnings[0].message.contains("malformed"))
        XCTAssertEqual(usage.warnings[0].level, .warning)
    }

    func testUnchangedFileReusesCachedAggregate() async throws {
        let line = tokenCountLine(
            timestamp: "2026-07-06T10:00:00.000Z",
            delta: 10,
            cumulative: 10,
            rateLimitUsedPercent: 10
        )
        let url = writeFixture(line, named: "unchanged.jsonl")
        let source = makeSourceWithModificationDate(url: url)
        let parser = makeParser()
        let first = await parser.parse(logSources: [source])

        let handle = try FileHandle(forWritingTo: url)
        handle.write(Data(String(repeating: "x", count: Data(line.utf8).count).utf8))
        handle.closeFile()
        let second = await parser.parse(logSources: [source])

        assertEqual(second, first)
        XCTAssertTrue(second.warnings.isEmpty)
    }

    func testIncrementalParseResumesAppendedLogsAndMatchesFullParse() async throws {
        let baseLine = tokenCountLine(
            timestamp: "2026-07-06T10:00:00.000Z",
            delta: 10,
            cumulative: 10,
            rateLimitUsedPercent: 10
        )
        let url = writeFixture(baseLine, named: "incremental.jsonl")
        let parser = makeParser()
        _ = await parser.parse(logSources: [
            makeSourceWithModificationDate(url: url, sessionID: "session-a"),
        ])

        try appendLine(tokenCountLine(
            timestamp: "2026-07-06T11:00:00.000Z",
            delta: 20,
            cumulative: 30,
            rateLimitUsedPercent: 20
        ), to: url)
        let updatedSource = makeSourceWithModificationDate(url: url, sessionID: "session-a")
        let incremental = await parser.parse(logSources: [updatedSource])
        let full = await makeParser().parse(logSources: [updatedSource])

        assertEqual(incremental, full)
        XCTAssertEqual(incremental.deltaReportedTotalTokens, 30)
        XCTAssertEqual(incremental.finalReportedTotalTokens, 30)
        XCTAssertEqual(incremental.quotaWindows.first?.used, 20)
    }

    func testIncrementalParseRetriesIncompleteTrailingRecord() async throws {
        let completeLine = tokenCountLine(
            timestamp: "2026-07-06T10:00:00.000Z",
            delta: 25,
            cumulative: 25,
            rateLimitUsedPercent: 25
        )
        let splitIndex = completeLine.index(completeLine.endIndex, offsetBy: -20)
        let prefix = String(completeLine[..<splitIndex])
        let suffix = String(completeLine[splitIndex...])
        let url = writeFixture(prefix, named: "partial.jsonl")
        let parser = makeParser()
        let first = await parser.parse(logSources: [
            makeSourceWithModificationDate(url: url, sessionID: "session-a"),
        ])
        XCTAssertEqual(first.lifetime.totalTokens, 0)
        XCTAssertTrue(first.warnings.isEmpty)

        try appendContent(suffix, to: url)
        let updatedSource = makeSourceWithModificationDate(url: url, sessionID: "session-a")
        let incremental = await parser.parse(logSources: [updatedSource])
        let full = await makeParser().parse(logSources: [updatedSource])

        assertEqual(incremental, full)
        XCTAssertEqual(incremental.deltaReportedTotalTokens, 25)
        XCTAssertEqual(incremental.finalReportedTotalTokens, 25)
        XCTAssertEqual(incremental.quotaWindows.first?.used, 25)
    }

    func testTruncatedFileReplacesCachedAggregate() async throws {
        let initial = [
            tokenCountLine(
                timestamp: "2026-07-06T10:00:00.000Z",
                delta: 100,
                cumulative: 100,
                rateLimitUsedPercent: 10
            ),
            tokenCountLine(
                timestamp: "2026-07-06T11:00:00.000Z",
                delta: 200,
                cumulative: 300,
                rateLimitUsedPercent: 20
            ),
        ].joined(separator: "\n")
        let url = writeFixture(initial, named: "rotated.jsonl")
        let parser = makeParser()
        _ = await parser.parse(logSources: [
            makeSourceWithModificationDate(url: url, sessionID: "session-a"),
        ])

        let replacement = tokenCountLine(
            timestamp: "2026-07-06T12:00:00.000Z",
            delta: 5,
            cumulative: 5,
            rateLimitUsedPercent: 5
        )
        try replacement.write(to: url, atomically: true, encoding: .utf8)
        let updatedSource = makeSourceWithModificationDate(url: url, sessionID: "session-a")
        let reparsed = await parser.parse(logSources: [updatedSource])
        let full = await makeParser().parse(logSources: [updatedSource])

        assertEqual(reparsed, full)
        XCTAssertEqual(reparsed.deltaReportedTotalTokens, 5)
        XCTAssertEqual(reparsed.finalReportedTotalTokens, 5)
        XCTAssertEqual(reparsed.quotaWindows.first?.used, 5)
    }

    func testLargerRotatedFileReplacesCachedAggregate() async throws {
        let initial = tokenCountLine(
            timestamp: "2026-07-06T10:00:00.000Z",
            delta: 100,
            cumulative: 100,
            rateLimitUsedPercent: 10
        )
        let url = writeFixture(initial, named: "rotated-larger.jsonl")
        let parser = makeParser()
        _ = await parser.parse(logSources: [
            makeSourceWithModificationDate(url: url, sessionID: "session-a"),
        ])

        let replacement = [
            tokenCountLine(
                timestamp: "2026-07-06T11:00:00.000Z",
                delta: 5,
                cumulative: 5,
                rateLimitUsedPercent: 5
            ),
            tokenCountLine(
                timestamp: "2026-07-06T12:00:00.000Z",
                delta: 10,
                cumulative: 15,
                rateLimitUsedPercent: 15
            ),
        ].joined(separator: "\n")
        try replacement.write(to: url, atomically: true, encoding: .utf8)
        let updatedSource = makeSourceWithModificationDate(url: url, sessionID: "session-a")
        let reparsed = await parser.parse(logSources: [updatedSource])
        let full = await makeParser().parse(logSources: [updatedSource])

        assertEqual(reparsed, full)
        XCTAssertEqual(reparsed.deltaReportedTotalTokens, 15)
        XCTAssertEqual(reparsed.finalReportedTotalTokens, 15)
        XCTAssertEqual(reparsed.quotaWindows.first?.used, 15)
    }

    func testSameInodeTruncateAndRegrowReplacesCachedAggregate() async throws {
        let initial = tokenCountLine(
            timestamp: "2026-07-06T10:00:00.000Z",
            delta: 100,
            cumulative: 100,
            rateLimitUsedPercent: 10
        )
        let url = writeFixture(initial, named: "copy-truncated-larger.jsonl")
        let initialIdentifier = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.systemFileNumber] as? NSNumber
        let parser = makeParser()
        _ = await parser.parse(logSources: [
            makeSourceWithModificationDate(url: url, sessionID: "session-a"),
        ])

        let replacement = [
            tokenCountLine(
                timestamp: "2026-07-06T11:00:00.000Z",
                delta: 5,
                cumulative: 5,
                rateLimitUsedPercent: 5
            ),
            tokenCountLine(
                timestamp: "2026-07-06T12:00:00.000Z",
                delta: 10,
                cumulative: 15,
                rateLimitUsedPercent: 15
            ),
            tokenCountLine(
                timestamp: "2026-07-06T13:00:00.000Z",
                delta: 15,
                cumulative: 30,
                rateLimitUsedPercent: 30
            ),
        ].joined(separator: "\n")
        try replacement.write(to: url, atomically: false, encoding: .utf8)
        let updatedIdentifier = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.systemFileNumber] as? NSNumber
        XCTAssertEqual(updatedIdentifier, initialIdentifier)

        let updatedSource = makeSourceWithModificationDate(url: url, sessionID: "session-a")
        let reparsed = await parser.parse(logSources: [updatedSource])
        let full = await makeParser().parse(logSources: [updatedSource])

        assertEqual(reparsed, full)
        XCTAssertEqual(reparsed.deltaReportedTotalTokens, 30)
        XCTAssertEqual(reparsed.finalReportedTotalTokens, 30)
        XCTAssertEqual(reparsed.quotaWindows.first?.used, 30)
    }

    func testInteriorBlankLinesDoNotProduceMalformedWarnings() async {
        let content = [
            tokenCountLine(
                timestamp: "2026-07-06T10:00:00.000Z",
                delta: 10,
                cumulative: 10,
                rateLimitUsedPercent: 10
            ),
            "",
            tokenCountLine(
                timestamp: "2026-07-06T11:00:00.000Z",
                delta: 20,
                cumulative: 30,
                rateLimitUsedPercent: 30
            ),
        ].joined(separator: "\n")
        let url = writeFixture(content, named: "blank-lines.jsonl")

        let aggregate = await makeParser().parse(logSources: [
            makeSourceWithModificationDate(url: url, sessionID: "session-a"),
        ])

        XCTAssertTrue(aggregate.warnings.isEmpty)
        XCTAssertEqual(aggregate.deltaReportedTotalTokens, 30)
        XCTAssertEqual(aggregate.finalReportedTotalTokens, 30)
    }

    func testMultiFileLatestValuesMatchFullParseAfterIncrementalAppends() async throws {
        let firstURL = writeFixture(tokenCountLine(
            timestamp: "2026-07-06T09:00:00.000Z",
            delta: 10,
            cumulative: 100,
            rateLimitUsedPercent: 10
        ), named: "multi-a.jsonl")
        let secondURL = writeFixture(tokenCountLine(
            timestamp: "2026-07-06T10:00:00.000Z",
            delta: 20,
            cumulative: 200,
            rateLimitUsedPercent: 20
        ), named: "multi-b.jsonl")
        let thirdURL = writeFixture(tokenCountLine(
            timestamp: "2026-07-06T08:00:00.000Z",
            delta: 5,
            cumulative: 50,
            rateLimitUsedPercent: 5
        ), named: "multi-c.jsonl")
        let parser = makeParser()
        _ = await parser.parse(logSources: [
            makeSourceWithModificationDate(url: firstURL, sessionID: "shared-session"),
            makeSourceWithModificationDate(url: secondURL, sessionID: "shared-session"),
            makeSourceWithModificationDate(url: thirdURL, sessionID: "other-session"),
        ])

        try appendLine(tokenCountLine(
            timestamp: "2026-07-06T12:00:00.000Z",
            delta: 30,
            cumulative: 150,
            rateLimitUsedPercent: 30
        ), to: firstURL)
        try appendLine(tokenCountLine(
            timestamp: "2026-07-06T13:00:00.000Z",
            delta: 40,
            cumulative: 250,
            rateLimitUsedPercent: 40
        ), to: secondURL)
        let updatedSources = [
            makeSourceWithModificationDate(url: firstURL, sessionID: "shared-session"),
            makeSourceWithModificationDate(url: secondURL, sessionID: "shared-session"),
            makeSourceWithModificationDate(url: thirdURL, sessionID: "other-session"),
        ]
        let incremental = await parser.parse(logSources: updatedSources)
        let full = await makeParser().parse(logSources: updatedSources)

        assertEqual(incremental, full)
        XCTAssertEqual(incremental.deltaReportedTotalTokens, 105)
        XCTAssertEqual(incremental.finalReportedTotalTokens, 300)
        XCTAssertEqual(incremental.quotaWindows.first?.used, 40)
    }
}
