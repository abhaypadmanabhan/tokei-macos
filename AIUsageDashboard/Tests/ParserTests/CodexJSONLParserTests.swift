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
