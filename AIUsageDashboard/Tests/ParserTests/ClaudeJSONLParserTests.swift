import XCTest
@testable import AIUsageDashboardCore

final class ClaudeJSONLParserTests: XCTestCase {
    var tempDirectory: URL!
  var utcCalendar: Calendar!

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

  private func makeSource(url: URL, sessionID: String = "test-session") -> LogSource {
    LogSource(providerID: .claudeCode, url: url, sessionID: sessionID)
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

  private func makeParser(now: Date? = nil) -> ClaudeJSONLParser {
    let fixed = now ?? referenceNow()
    return ClaudeJSONLParser(calendar: utcCalendar, now: { fixed })
  }

    func testEmptyLogSources() async {
    let parser = makeParser()
        let usage = await parser.parse(logSources: [])
        XCTAssertEqual(usage.lifetime.totalTokens, 0)
        XCTAssertEqual(usage.lifetime.confidence, .localParsed)
    }

  func testRealSchemaAggregation() async {
    let url = writeFixture(ClaudeFixtures.twoDistinctMessages(), named: "real.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])

    XCTAssertEqual(usage.lifetime.inputTokens, 300)
    XCTAssertEqual(usage.lifetime.outputTokens, 150)
    XCTAssertEqual(usage.lifetime.cacheReadTokens, 50)
    XCTAssertEqual(usage.lifetime.cacheCreationTokens, 25)
    XCTAssertEqual(usage.lifetime.totalTokens, 525)
  }

  func testDeduplicationByMessageId() async {
    let url = writeFixture(ClaudeFixtures.duplicateAssistantBlocks, named: "dup.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.inputTokens, 100)
    XCTAssertEqual(usage.lifetime.outputTokens, 50)
  }

  func testDeduplicationAcrossFiles() async {
    let content = ClaudeFixtures.crossFileDuplicate()
    let url1 = writeFixture(content, named: "file1.jsonl")
    let url2 = writeFixture(content, named: "file2.jsonl")
    let usage = await makeParser().parse(logSources: [
      makeSource(url: url1, sessionID: "s1"),
      makeSource(url: url2, sessionID: "s2"),
    ])
    XCTAssertEqual(usage.lifetime.inputTokens, 100)
  }

  func testFractionalTimestamp() async {
    let url = writeFixture(ClaudeFixtures.assistantLine, named: "frac.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])

    XCTAssertEqual(usage.lifetime.inputTokens, 4)
    XCTAssertEqual(usage.lifetime.outputTokens, 250)
    XCTAssertEqual(usage.lifetime.cacheReadTokens, 14085)
    XCTAssertEqual(usage.lifetime.cacheCreationTokens, 24924)
    XCTAssertGreaterThan(usage.today.inputTokens ?? 0, 0)
    XCTAssertGreaterThan(usage.week.inputTokens ?? 0, 0)
    XCTAssertGreaterThan(usage.month.inputTokens ?? 0, 0)
  }

  func testEpochTimestamp() async {
    let url = writeFixture(ClaudeFixtures.epochTimestampLine, named: "epoch.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.inputTokens, 10)
    XCTAssertEqual(usage.lifetime.totalTokens, 15)
  }

  func testNonFractionalTimestamp() async {
    let url = writeFixture(ClaudeFixtures.isoTimestampLine, named: "iso.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.inputTokens, 20)
    XCTAssertGreaterThan(usage.today.inputTokens ?? 0, 0)
  }

  func testSkipsLinesWithoutUsage() async {
    let content = """
    \(ClaudeFixtures.userLine)
    \(ClaudeFixtures.summaryLine)
    """
    let url = writeFixture(content, named: "skip.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.totalTokens, 0)
  }

  func testSidechainCounted() async {
    let url = writeFixture(ClaudeFixtures.sidechainLine, named: "sidechain.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.inputTokens, 30)
    XCTAssertEqual(usage.lifetime.outputTokens, 15)
    XCTAssertEqual(usage.lifetime.cacheReadTokens, 5)
    XCTAssertEqual(usage.lifetime.cacheCreationTokens, 2)
    XCTAssertEqual(usage.lifetime.totalTokens, 52)
  }

  func testMalformedLinesWarning() async {
    let url = writeFixture(ClaudeFixtures.validWithMalformed(), named: "malformed.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.inputTokens, 100)
    XCTAssertEqual(usage.warnings.count, 1)
    XCTAssertTrue(usage.warnings[0].message.contains("malformed"))
    XCTAssertEqual(usage.warnings[0].level, .warning)
  }

  func testWindowBucketing() async {
    let now = referenceNow()
    let content = ClaudeFixtures.windowBucketLines(referenceNow: now)
    let url = writeFixture(content, named: "windows.jsonl")
    let usage = await makeParser(now: now).parse(logSources: [makeSource(url: url)])

    XCTAssertEqual(usage.lifetime.inputTokens, 100)
    XCTAssertEqual(usage.today.inputTokens, 10)
    XCTAssertEqual(usage.week.inputTokens, 30)   // today(10) + week(20)
    XCTAssertEqual(usage.month.inputTokens, 60)   // today + week + month(30)
  }

  func testBucketsHourlyTotalsWithinFourteenDayWindow() async {
    let hour = date("2026-07-06", hour: 5)
    let sameHour = hour.addingTimeInterval(30 * 60)
    let oldHour = date("2026-06-20", hour: 5)

    func line(id: String, input: Int, timestamp: Date) -> String {
      """
      {"message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_\(id)","type":"assistant","uuid":"uuid_\(id)","timestamp":"\(isoString(timestamp))"}
      """
    }

    let url = writeFixture([
      line(id: "recent-a", input: 10, timestamp: hour),
      line(id: "recent-b", input: 20, timestamp: sameHour),
      line(id: "old", input: 40, timestamp: oldHour),
    ].joined(separator: "\n"), named: "hourly.jsonl")

    let usage = await makeParser(now: referenceNow()).parse(logSources: [makeSource(url: url)])

    XCTAssertEqual(usage.hourlyTotals?[hour], 30)
    XCTAssertNil(usage.hourlyTotals?[oldHour])
    XCTAssertEqual(usage.hourlyTotals?.values.reduce(0, +), 30)
  }

  func testLegacyTopLevelUsage() async {
    let url = writeFixture(ClaudeFixtures.legacyTopLevelUsage, named: "legacy.jsonl")
    let usage = await makeParser().parse(logSources: [makeSource(url: url)])
    XCTAssertEqual(usage.lifetime.inputTokens, 100)
    XCTAssertEqual(usage.lifetime.outputTokens, 50)
    XCTAssertEqual(usage.lifetime.totalTokens, 180)
  }
}
