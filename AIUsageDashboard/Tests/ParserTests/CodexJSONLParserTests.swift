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
}
