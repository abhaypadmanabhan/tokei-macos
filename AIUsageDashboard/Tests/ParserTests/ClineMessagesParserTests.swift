import XCTest
@testable import AIUsageDashboardCore

final class ClineMessagesParserTests: XCTestCase {
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

    private func writeFixture(_ content: String, sessionID: String) -> URL {
        let sessionDir = tempDirectory.appendingPathComponent(sessionID, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let url = sessionDir.appendingPathComponent("\(sessionID).messages.json")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeSource(url: URL, sessionID: String) -> LogSource {
        LogSource(providerID: .cline, url: url, sessionID: sessionID)
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

    private func millis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private func makeParser(now: Date? = nil) -> ClineMessagesParser {
        let fixed = now ?? referenceNow()
        return ClineMessagesParser(calendar: utcCalendar, now: { fixed })
    }

    func testParsesAssistantMessagesWithCostAndMillisTimestamps() async {
        let sessionID = "1783325327533_test"
        let url = writeFixture(ClineFixtures.twoAssistantMessages(sessionID: sessionID), sessionID: sessionID)
        let usage = await makeParser().parse(logSources: [makeSource(url: url, sessionID: sessionID)])

        XCTAssertEqual(usage.lifetime.inputTokens, 300)
        XCTAssertEqual(usage.lifetime.outputTokens, 150)
        XCTAssertEqual(usage.lifetime.cacheReadTokens, 50)
        XCTAssertEqual(usage.lifetime.cacheCreationTokens, 25)
        XCTAssertEqual(usage.lifetime.totalTokens, 525)
        XCTAssertEqual(usage.totalCost, 0.03, accuracy: 0.0001)
        XCTAssertEqual(usage.today.totalTokens, 525)
        XCTAssertEqual(usage.week.totalTokens, 525)
        XCTAssertEqual(usage.month.totalTokens, 525)
        XCTAssertTrue(usage.warnings.isEmpty)
    }

    func testDedupesMessagesByIDAcrossFiles() async {
        let sessionA = "1783325327533_a"
        let sessionB = "1783325327533_b"
        let urlA = writeFixture(ClineFixtures.duplicateMessage(sessionID: sessionA), sessionID: sessionA)
        let urlB = writeFixture(ClineFixtures.duplicateMessage(sessionID: sessionB), sessionID: sessionB)
        let usage = await makeParser().parse(logSources: [
            makeSource(url: urlA, sessionID: sessionA),
            makeSource(url: urlB, sessionID: sessionB),
        ])

        XCTAssertEqual(usage.lifetime.totalTokens, 180)
        XCTAssertEqual(usage.totalCost, 0.01, accuracy: 0.0001)
    }

    func testSkipsMessagesWithoutMetrics() async {
        let sessionID = "1783325327533_nom"
        let url = writeFixture(ClineFixtures.messageWithoutMetrics(sessionID: sessionID), sessionID: sessionID)
        let usage = await makeParser().parse(logSources: [makeSource(url: url, sessionID: sessionID)])

        XCTAssertEqual(usage.lifetime.totalTokens, 15)
        XCTAssertEqual(usage.totalCost, 0.001, accuracy: 0.0001)
    }

    func testMalformedJSONProducesWarning() async {
        let sessionID = "1783325327533_bad"
        let url = writeFixture(ClineFixtures.malformedJSON, sessionID: sessionID)
        let usage = await makeParser().parse(logSources: [makeSource(url: url, sessionID: sessionID)])

        XCTAssertEqual(usage.lifetime.totalTokens, 0)
        XCTAssertEqual(usage.warnings.count, 1)
        XCTAssertEqual(usage.warnings.first?.level, .warning)
        XCTAssertTrue(usage.warnings.first?.message.contains("malformed") == true
            || usage.warnings.first?.message.contains("Failed to parse") == true)
    }

    func testBucketsDailyTotalsByMessageTimestamp() async {
        let now = referenceNow()
        let sessionID = "1783325327533_win"
        let url = writeFixture(
            ClineFixtures.windowBucketMessages(referenceNow: now, sessionID: sessionID),
            sessionID: sessionID
        )
        let usage = await makeParser(now: now).parse(logSources: [makeSource(url: url, sessionID: sessionID)])

        XCTAssertEqual(usage.lifetime.totalTokens, 100)
        XCTAssertEqual(usage.today.totalTokens, 10)
        XCTAssertEqual(usage.week.totalTokens, 30)
        XCTAssertEqual(usage.month.totalTokens, 60)
        XCTAssertEqual(usage.dailyTotals.values.reduce(0, +), 100)
        XCTAssertEqual(usage.totalCost, 0.004, accuracy: 0.0001)
    }

    func testBucketsHourlyTotalsWithinFourteenDayWindow() async {
        let hour = date("2026-07-06", hour: 5)
        let sameHour = hour.addingTimeInterval(30 * 60)
        let oldHour = date("2026-06-20", hour: 5)
        let sessionID = "1783325327533_hourly"
        let content = """
        {"version":1,"sessionId":"\(sessionID)","messages":[
          {"id":"recent-a","role":"assistant","ts":\(millis(hour)),"metrics":{"inputTokens":10,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"cost":0.001}},
          {"id":"recent-b","role":"assistant","ts":\(millis(sameHour)),"metrics":{"inputTokens":20,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"cost":0.001}},
          {"id":"old","role":"assistant","ts":\(millis(oldHour)),"metrics":{"inputTokens":40,"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"cost":0.001}}
        ]}
        """
        let url = writeFixture(content, sessionID: sessionID)

        let usage = await makeParser(now: referenceNow()).parse(logSources: [makeSource(url: url, sessionID: sessionID)])

        XCTAssertEqual(usage.hourlyTotals?[hour], 30)
        XCTAssertNil(usage.hourlyTotals?[oldHour])
        XCTAssertEqual(usage.hourlyTotals?.values.reduce(0, +), 30)
    }
}
