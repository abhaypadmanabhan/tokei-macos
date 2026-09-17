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

  private func makeSourceWithModificationDate(url: URL, sessionID: String = "test-session") -> LogSource {
    let modificationDate = try? url.resourceValues(
      forKeys: [.contentModificationDateKey]
    ).contentModificationDate
    return LogSource(
      providerID: .claudeCode,
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

  private func usageLine(
    id: String,
    input: Int,
    output: Int,
    cacheRead: Int,
    cacheCreation: Int,
    timestamp: String = "2026-07-06T10:00:00.000Z"
  ) -> String {
    #"{"message":{"id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":\#(cacheRead),"cache_creation_input_tokens":\#(cacheCreation)}},"type":"assistant","timestamp":"\#(timestamp)"}"#
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

  func testIncrementalParseResumesAppendedLogs() async {
    let parser = makeParser()
    let baseLine = """
    {"message":{"id":"msg_base","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_base","type":"assistant","uuid":"uuid-base","timestamp":"2026-07-06T10:00:00.000Z"}
    """
    let url = writeFixture(baseLine, named: "incremental.jsonl")
    let source = makeSourceWithModificationDate(url: url, sessionID: "s1")
    let first = await parser.parse(logSources: [source])
    XCTAssertEqual(first.lifetime.totalTokens, 15)

    let appendedLine = """
    {"message":{"id":"msg_appended","usage":{"input_tokens":20,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_appended","type":"assistant","uuid":"uuid-appended","timestamp":"2026-07-06T11:00:00.000Z"}
    """
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(Data("\n\(appendedLine)".utf8))
      handle.closeFile()
    }

    let updatedSource = makeSourceWithModificationDate(url: url, sessionID: "s1")
    let second = await parser.parse(logSources: [updatedSource])
    XCTAssertEqual(second.lifetime.totalTokens, 45)
  }

  /// D2: repeated Claude usage rows are updates to one message, not independent usage.
  func testD2_updatedUsageRecordReplacesEarlierContribution() async {
    let initial = usageLine(
      id: "msg_updated",
      input: 10,
      output: 1,
      cacheRead: 100,
      cacheCreation: 0
    )
    let final = usageLine(
      id: "msg_updated",
      input: 10,
      output: 25,
      cacheRead: 100,
      cacheCreation: 0
    )
    let url = writeFixture(initial, named: "d2-updated.jsonl")
    let parser = makeParser()

    let preliminary = await parser.parse(logSources: [makeSourceWithModificationDate(url: url)])
    XCTAssertEqual(preliminary.lifetime.totalTokens, 111)

    let handle = try? FileHandle(forWritingTo: url)
    handle?.seekToEndOfFile()
    handle?.write(Data("\n\(final)".utf8))
    handle?.closeFile()

    let updated = await parser.parse(logSources: [makeSourceWithModificationDate(url: url)])
    XCTAssertEqual(updated.lifetime.totalTokens, 135, "an appended update replaces its earlier value")

    let copied = writeFixture(final, named: "d2-copy.jsonl")
    let usage = await parser.parse(logSources: [
      makeSourceWithModificationDate(url: url),
      makeSourceWithModificationDate(url: copied)
    ])

    XCTAssertEqual(usage.lifetime.totalTokens, 135, "updates reconcile across files; copies still dedupe")
  }

  /// D3: an unfinished final JSON object must remain unread until its suffix arrives.
  func testD3_splitRecordAppendMatchesColdParseWithoutMalformedWarning() async throws {
    let parser = makeParser()
    let line = usageLine(
      id: "msg_split",
      input: 10,
      output: 25,
      cacheRead: 100,
      cacheCreation: 0
    )
    let split = line.index(line.startIndex, offsetBy: line.count / 2)
    let prefix = String(line[..<split])
    let suffix = String(line[split...])
    let url = writeFixture(prefix, named: "d3-split.jsonl")

    let incomplete = await parser.parse(logSources: [makeSourceWithModificationDate(url: url)])
    XCTAssertEqual(incomplete.lifetime.totalTokens, 0)

    let handle = try FileHandle(forWritingTo: url)
    handle.seekToEndOfFile()
    handle.write(Data(suffix.utf8))
    handle.closeFile()

    let warm = await parser.parse(logSources: [makeSourceWithModificationDate(url: url)])
    let cold = await makeParser().parse(logSources: [makeSourceWithModificationDate(url: url)])
    XCTAssertEqual(warm.lifetime.totalTokens, 135)
    XCTAssertEqual(warm.lifetime.totalTokens, cold.lifetime.totalTokens)
    XCTAssertTrue(warm.warnings.isEmpty, "an unfinished tail is not permanently malformed")
  }

  /// D4: equal-length content replacement is not an append at EOF.
  func testD4_sameSizeRewriteReparsesInsteadOfServingOldAggregate() async throws {
    let parser = makeParser()
    let firstLine = ClaudeFixtures.usageLine(id: "msg_rewrite", output: 100)
    let secondLine = ClaudeFixtures.usageLine(id: "msg_rewrite", output: 900)
    XCTAssertEqual(firstLine.utf8.count, secondLine.utf8.count)
    let url = writeFixture(firstLine, named: "d4-rewrite.jsonl")

    let firstSource = makeSourceWithModificationDate(url: url)
    let first = await parser.parse(logSources: [firstSource])
    XCTAssertEqual(first.lifetime.totalTokens, 100)

    try secondLine.write(to: url, atomically: true, encoding: .utf8)
    let newer = (firstSource.lastModified ?? Date()).addingTimeInterval(2)
    try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: url.path)

    let rewritten = await parser.parse(logSources: [makeSourceWithModificationDate(url: url)])
    XCTAssertEqual(rewritten.lifetime.totalTokens, 900)
  }

  /// D6-core: the month fallback is the same trailing 30 calendar dates as the 30D chart.
  func testD6_monthUsageUsesThirtyCalendarDays() async {
    let now = date("2026-09-16", hour: 12)
    let outsideThirtyDays = ClaudeFixtures.usageLine(
      id: "msg_aug17",
      output: 77,
      timestamp: "2026-08-17T12:00:00.000Z"
    )
    let firstIncludedDay = ClaudeFixtures.usageLine(
      id: "msg_aug18",
      output: 23,
      timestamp: "2026-08-18T12:00:00.000Z"
    )
    let url = writeFixture(
      [outsideThirtyDays, firstIncludedDay].joined(separator: "\n"),
      named: "d6-month.jsonl"
    )

    let usage = await makeParser(now: now).parse(logSources: [makeSource(url: url)])

    XCTAssertEqual(usage.month.totalTokens, 23)
  }

  /// D10: records from the next local day remain lifetime history, not today's usage.
  func testD10_tomorrowsRecordIsExcludedFromCurrentWindows() async {
    let now = date("2026-07-06", hour: 12)
    let tomorrow = ClaudeFixtures.usageLine(
      id: "msg_future",
      output: 50,
      timestamp: "2026-07-07T00:00:00.000Z"
    )
    let url = writeFixture(tomorrow, named: "d10-future.jsonl")

    let usage = await makeParser(now: now).parse(logSources: [makeSource(url: url)])

    XCTAssertEqual(usage.today.totalTokens, 0)
    XCTAssertEqual(usage.week.totalTokens, 0)
    XCTAssertEqual(usage.month.totalTokens, 0)
    XCTAssertEqual(usage.lifetime.totalTokens, 50)
    XCTAssertTrue(usage.dailyTotals.isEmpty)
  }

  /// D9: cached bucket keys must be rebuilt from original timestamps after a timezone change.
  func testD9_effectiveCalendarChangeRebuildsCachedDayBuckets() async throws {
    let originalTimeZone = NSTimeZone.default
    defer { NSTimeZone.default = originalTimeZone }
    NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

    let now = try XCTUnwrap(JSONLDateParsing.iso8601("2026-01-15T20:00:00Z"))
    let parser = ClaudeJSONLParser(calendar: .autoupdatingCurrent, now: { now })
    let line = ClaudeFixtures.usageLine(
      id: "msg_timezone",
      output: 111,
      timestamp: "2026-01-15T07:30:00.000Z"
    )
    let url = writeFixture(line, named: "d9-timezone.jsonl")
    let source = makeSourceWithModificationDate(url: url)

    let losAngeles = await parser.parse(logSources: [source])
    let losAngelesDay = try XCTUnwrap(JSONLDateParsing.iso8601("2026-01-14T08:00:00Z"))
    XCTAssertEqual(losAngeles.dailyTotals[losAngelesDay], 111)

    NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
    let tokyo = await parser.parse(logSources: [source])
    let tokyoDay = try XCTUnwrap(JSONLDateParsing.iso8601("2026-01-14T15:00:00Z"))
    XCTAssertEqual(tokyo.dailyTotals, [tokyoDay: 111])
  }

  /// One parser instance is shared by every Claude account, and `ClaudeCodeProvider`
  /// calls `parse` once per account — so a call's source list is one account's slice of
  /// the corpus, never all of it. Cache eviction must not treat "absent from this call"
  /// as "gone", or each account's parse wipes the others' entries and every account
  /// re-reads its whole corpus on every refresh (measured: 0 cache hits, ~600 MB
  /// re-parsed every 2 s, one core pegged).
  ///
  /// The probe rewrites account A's log in place with the same byte count and the same
  /// modification date, so the cache key is unchanged: a served-from-cache read still
  /// reports the old total, while a re-parse would pick up the new one.
  func testCacheSurvivesAnInterleavedParseOfAnotherAccount() async throws {
    let parser = makeParser()
    func line(id: String, output: Int) -> String {
      #"{"message":{"id":"\#(id)","usage":{"input_tokens":0,"output_tokens":\#(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"type":"assistant","timestamp":"2026-07-06T10:00:00.000Z"}"#
    }

    let accountA = writeFixture(line(id: "msg_a", output: 100), named: "account-a.jsonl")
    let accountB = writeFixture(line(id: "msg_b", output: 200), named: "account-b.jsonl")
    let sourceA = makeSourceWithModificationDate(url: accountA)
    let modifiedAt = try XCTUnwrap(sourceA.lastModified)

    let firstA = await parser.parse(logSources: [sourceA])
    XCTAssertEqual(firstA.lifetime.totalTokens, 100)
    // The other account's refresh: same parser, a disjoint source list.
    let firstB = await parser.parse(logSources: [makeSourceWithModificationDate(url: accountB)])
    XCTAssertEqual(firstB.lifetime.totalTokens, 200)

    // Same length, same mtime — indistinguishable to the cache key, different if re-read.
    let rewritten = line(id: "msg_a", output: 999)
    XCTAssertEqual(rewritten.utf8.count, line(id: "msg_a", output: 100).utf8.count)
    try rewritten.write(to: accountA, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: accountA.path)

    let reread = await parser.parse(logSources: [makeSourceWithModificationDate(url: accountA)])
    XCTAssertEqual(
      reread.lifetime.totalTokens, 100,
      "account A's cache entry was evicted by account B's parse, forcing a full re-read"
    )
  }

  /// A per-file aggregate is only safely additive across files if the files' dedupe keys
  /// are disjoint. When one file is served from cache its whole aggregate is applied at
  /// once, so an ID it shares with a file parsed earlier in the same call gets counted a
  /// second time. Before the parse cache actually hit (50276d2) this was unreachable;
  /// now it is the normal path, and token totals are the one number this app cannot get
  /// wrong.
  ///
  /// Order matters: the *fresh* file has to come first. If the cached file leads, its IDs
  /// are in `seenIDs` before the fresh parse starts and the fresh parse's own dedup
  /// catches the duplicate.
  func testCacheHitDoesNotDoubleCountAnIDAlreadySeenInAFreshFile() async {
    let parser = makeParser()
    let shared = ClaudeFixtures.usageLine(id: "msg_shared", output: 100)
    let fileA = writeFixture([shared, ClaudeFixtures.usageLine(id: "msg_a", output: 7)]
      .joined(separator: "\n"), named: "shared-a.jsonl")
    let fileB = writeFixture([shared, ClaudeFixtures.usageLine(id: "msg_b", output: 30)]
      .joined(separator: "\n"), named: "shared-b.jsonl")

    // Warm the cache for A only, so the next call mixes a cache hit with a fresh parse.
    let warm = await parser.parse(logSources: [makeSourceWithModificationDate(url: fileA)])
    XCTAssertEqual(warm.lifetime.totalTokens, 107)

    let mixed = await parser.parse(logSources: [
      makeSourceWithModificationDate(url: fileB, sessionID: "s2"),  // fresh
      makeSourceWithModificationDate(url: fileA, sessionID: "s1"),  // cache hit
    ])

    XCTAssertEqual(
      mixed.lifetime.totalTokens, 137,
      "msg_shared was counted twice: once by B's fresh parse, again inside A's cached aggregate"
    )
    XCTAssertEqual(mixed.today.totalTokens, 137)
  }

  /// The mirror of the above: a fresh parse dedups against the running `seenIDs`, so the
  /// aggregate it caches is missing whatever an earlier file in that same call happened to
  /// claim. That entry then under-reports for every later call it is served from cache in,
  /// including calls the other file is not part of. A cached per-file aggregate has to
  /// describe the file, not the order it was first seen in.
  func testCachedAggregateIsIndependentOfWhichFileWasParsedFirst() async {
    let parser = makeParser()
    let shared = ClaudeFixtures.usageLine(id: "msg_shared", output: 100)
    let fileA = writeFixture([shared, ClaudeFixtures.usageLine(id: "msg_a", output: 7)]
      .joined(separator: "\n"), named: "order-a.jsonl")
    let fileB = writeFixture([shared, ClaudeFixtures.usageLine(id: "msg_b", output: 30)]
      .joined(separator: "\n"), named: "order-b.jsonl")

    let both = await parser.parse(logSources: [
      makeSourceWithModificationDate(url: fileA, sessionID: "s1"),
      makeSourceWithModificationDate(url: fileB, sessionID: "s2"),
    ])
    XCTAssertEqual(both.lifetime.totalTokens, 137)

    // B alone, entirely from cache. Its own content is msg_shared + msg_b = 130.
    let bAlone = await parser.parse(logSources: [
      makeSourceWithModificationDate(url: fileB, sessionID: "s2"),
    ])
    XCTAssertEqual(
      bAlone.lifetime.totalTokens, 130,
      "B's cached aggregate dropped msg_shared because A claimed it during the first call"
    )
  }

  /// Resolving an overlap costs a re-read of the overlapping file, which would be a
  /// regression if it happened on every refresh — on this machine's corpus the files that
  /// share IDs are session forks totalling ~22 MB, and the refresh cadence is 2 s. The
  /// resolved aggregate is therefore kept until the overlapping set itself changes.
  ///
  /// Same probe as the eviction test: rewrite the file in place at the same byte count and
  /// modification date, so a re-read would show the new number and a served-from-cache
  /// read would not.
  func testOverlapCorrectionIsNotRecomputedOnEveryRefresh() async throws {
    let parser = makeParser()
    let shared = ClaudeFixtures.usageLine(id: "msg_shared", output: 100)
    let aUnique = ClaudeFixtures.usageLine(id: "msg_a", output: 700)
    let fileA = writeFixture([shared, aUnique].joined(separator: "\n"), named: "memo-a.jsonl")
    let fileB = writeFixture(
      [shared, ClaudeFixtures.usageLine(id: "msg_b", output: 30)].joined(separator: "\n"),
      named: "memo-b.jsonl"
    )
    let sources = [
      makeSourceWithModificationDate(url: fileB, sessionID: "s2"),
      makeSourceWithModificationDate(url: fileA, sessionID: "s1"),
    ]
    let modifiedAt = try XCTUnwrap(sources[1].lastModified)

    let first = await parser.parse(logSources: sources)
    XCTAssertEqual(first.lifetime.totalTokens, 830)

    let rewritten = [shared, ClaudeFixtures.usageLine(id: "msg_a", output: 999)]
      .joined(separator: "\n")
    XCTAssertEqual(rewritten.utf8.count, [shared, aUnique].joined(separator: "\n").utf8.count)
    try rewritten.write(to: fileA, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: fileA.path)

    let second = await parser.parse(logSources: [
      makeSourceWithModificationDate(url: fileB, sessionID: "s2"),
      makeSourceWithModificationDate(url: fileA, sessionID: "s1"),
    ])
    XCTAssertEqual(
      second.lifetime.totalTokens, 830,
      "the overlapping file was re-read even though neither it nor the overlap changed"
    )
  }

  /// A file can both overlap another and still be the one being written to — a forked
  /// session keeps appending. Appending must not throw away the resolved aggregate and
  /// send the whole file back through the parser.
  func testAppendExtendsTheOverlapCorrectionInsteadOfDiscardingIt() async throws {
    let parser = makeParser()
    let shared = ClaudeFixtures.usageLine(id: "msg_shared", output: 100)
    let aUnique = ClaudeFixtures.usageLine(id: "msg_a", output: 700)
    let fileA = writeFixture([shared, aUnique].joined(separator: "\n"), named: "grow-a.jsonl")
    let fileB = writeFixture(
      [shared, ClaudeFixtures.usageLine(id: "msg_b", output: 30)].joined(separator: "\n"),
      named: "grow-b.jsonl"
    )
    func sources() -> [LogSource] {
      [
        makeSourceWithModificationDate(url: fileB, sessionID: "s2"),
        makeSourceWithModificationDate(url: fileA, sessionID: "s1"),
      ]
    }

    let warm = await parser.parse(logSources: sources())
    XCTAssertEqual(warm.lifetime.totalTokens, 830)

    // Rewrite the already-parsed prefix at the same width *and* append: only a full
    // re-read would pick the 999 up.
    let poisoned = [shared, ClaudeFixtures.usageLine(id: "msg_a", output: 999)]
      .joined(separator: "\n")
    try poisoned.write(to: fileA, atomically: false, encoding: .utf8)
    if let handle = try? FileHandle(forWritingTo: fileA) {
      handle.seekToEndOfFile()
      handle.write(Data("\n\(ClaudeFixtures.usageLine(id: "msg_c", output: 5))".utf8))
      handle.closeFile()
    }

    let grown = await parser.parse(logSources: sources())
    // D4: the prefix changed before the append, so continuity verification must reject the
    // append fast path and rebuild from disk rather than deliberately serving cached 700.
    XCTAssertEqual(
      grown.lifetime.totalTokens, 1134,
      "expected shared(100) + rewritten a(999) + b(30) + appended c(5)"
    )
  }

  func testParseErrorWarningContainsFilenameNotFullPath() async throws {
    let parser = makeParser()
    let dirURL = tempDirectory.appendingPathComponent("notAFile.jsonl", isDirectory: true)
    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

    let usage = await parser.parse(logSources: [makeSource(url: dirURL)])

    XCTAssertEqual(usage.warnings.count, 1)
    let message = usage.warnings.first?.message ?? ""
    XCTAssertTrue(message.contains("notAFile.jsonl"), "warning should contain the filename: \(message)")
    XCTAssertFalse(
      message.contains(tempDirectory.path),
      "warning should not contain the full filesystem path: \(message)"
    )
  }
}
