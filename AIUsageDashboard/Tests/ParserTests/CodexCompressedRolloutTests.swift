import XCTest
@testable import AIUsageDashboardCore

struct CodexLogOnlyDiscovery: AccountDiscovering {
    let providerID: ProviderID = .codex
    let root: URL

    func discover(context: DiscoveryContext) throws -> [ProviderAccount] {
        ProviderAccountNormalizer.normalize(providerID: .codex, candidates: [
            .init(root: root, label: "Log-only fixture", quotaIdentity: nil, selector: nil)
        ])
    }
}

final class CodexCompressedRolloutTests: XCTestCase {
    private var root: URL!
    private var reference: Date!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"),
                                               withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath().standardizedFileURL
        reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z"))
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func fixture(_ name: String = "usage") throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name + ".jsonl", withExtension: "zst"))
        return try Data(contentsOf: url)
    }

    private func write(_ name: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent("sessions").appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func inode(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value
    }

    private func source(_ url: URL) -> LogSource { LogSource(providerID: .codex, url: url) }

    private func parser() -> CodexJSONLParser {
        let reference = reference!
        return CodexJSONLParser(calendar: calendar, now: { reference })
    }

    private func provider(_ parser: CodexJSONLParser) -> CodexProvider {
        let reference = reference!
        return CodexProvider(
            parser: parser, codexDirectory: root,
            pricing: PricingService(refresher: NoOpPricingTableRefresher(),
                                    cacheURL: root.appendingPathComponent("prices.json")),
            environment: [:], discoverer: CodexLogOnlyDiscovery(root: root), now: { reference }
        )
    }

    func testProviderSumsPlainAndCompressedAndReusesCache() async throws {
        let data = try fixture()
        try write("plain.jsonl", ZstdDecoder.decode(data))
        try write("compressed.jsonl.zst", data)
        let parser = parser()
        let provider = provider(parser)
        let sources = try await provider.discoverLogSources()
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(Set(sources.compactMap(\.sessionID)), ["plain", "compressed"])
        let first = try await provider.fetchSnapshot()
        let second = try await provider.fetchSnapshot()
        XCTAssertEqual(first.monthUsage?.totalTokens, 300)
        XCTAssertEqual(second.monthUsage?.totalTokens, 300)
        let reads = await parser.fileReadCountForTesting()
        XCTAssertEqual(reads, 2)
    }

    func testPlainWinsRegardlessOfInputOrder() async throws {
        let compressed = try write("same.jsonl.zst", fixture())
        let plain = try write("same.jsonl", Data("""
        {"type":"event_msg","timestamp":"2026-10-28T10:00:00Z","payload":{\
        "type":"token_count","info":{"last_token_usage":{"input_tokens":7}}}}
        """.utf8))
        for urls in [[plain, compressed], [compressed, plain]] {
            let parsed = await parser().parse(logSources: urls.map(source))
            XCTAssertEqual(parsed.lifetime.totalTokens, 7)
        }
        let discovered = try await provider(parser()).discoverLogSources()
        XCTAssertEqual(discovered.map(\.url.lastPathComponent), ["same.jsonl"])
        let discoveredURL = try XCTUnwrap(discovered.first?.url)
        XCTAssertEqual(try inode(discoveredURL), inode(plain))
    }

    func testCorruptionDiscardsProvisionalRecordsAndCachesFailure() async throws {
        let good = try write("good.jsonl", ZstdDecoder.decode(fixture()))
        var damaged = try fixture()
        damaged[damaged.count - 1] ^= 1
        let bad = try write("bad.jsonl.zst", damaged)
        let parser = parser()
        let provider = provider(parser)
        for _ in 0..<2 {
            let snapshot = try await provider.fetchSnapshot()
            XCTAssertEqual(snapshot.lifetimeUsage?.totalTokens, 150)
            XCTAssertEqual(snapshot.warnings.count, 1)
            XCTAssertEqual(snapshot.warnings.first?.level, .info)
        }
        let fresh = self.parser()
        _ = await fresh.parse(logSources: [source(bad), source(good)])
        let freshReads = await fresh.fileReadCountForTesting()
        XCTAssertEqual(freshReads, 1, "The failed compressed fingerprint must be shared across parsers")
        let reads = await parser.fileReadCountForTesting()
        XCTAssertEqual(reads, 2)
    }

    func testProcessCacheSurvivesParserAndCalendarChanges() async throws {
        let url = try write("immutable.jsonl.zst", fixture())
        let first = parser()
        let original = await first.parse(logSources: [source(url)])
        let second = parser()
        let reused = await second.parse(logSources: [source(url)])
        var tokyo = calendar!
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        await first.updateCalendar(tokyo)
        let rebucketed = await first.parse(logSources: [source(url)])
        XCTAssertEqual(original.lifetime.totalTokens, 150)
        XCTAssertEqual(reused.lifetime.totalTokens, 150)
        XCTAssertEqual(rebucketed.lifetime.totalTokens, 150)
        let firstReads = await first.fileReadCountForTesting()
        let secondReads = await second.fileReadCountForTesting()
        XCTAssertEqual(firstReads, 1)
        XCTAssertEqual(secondReads, 0)
        XCTAssertEqual(rebucketed.dailyUsage.keys.first, tokyo.startOfDay(for: reference.addingTimeInterval(-86_400)))
    }

    func testFreshFingerprintDetectsReplacementDespiteStaleSourceDate() async throws {
        let url = try write("replaced.jsonl.zst", fixture())
        let oldDate = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let stale = LogSource(providerID: .codex, url: url, lastModified: oldDate)
        let parser = parser()
        _ = await parser.parse(logSources: [stale])
        var damaged = try fixture()
        damaged[damaged.count - 1] ^= 1
        try damaged.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        let replaced = await parser.parse(logSources: [stale])
        XCTAssertEqual(replaced.lifetime.totalTokens, 0)
        XCTAssertEqual(replaced.warnings.first?.level, .info)
        let reads = await parser.fileReadCountForTesting()
        XCTAssertEqual(reads, 2)
    }

    func testConcurrentParsersShareOneDecodeAttempt() async throws {
        let url = try write("concurrent.jsonl.zst", fixture())
        let sources = [source(url)]
        let first = parser()
        let second = parser()
        async let left = first.parse(logSources: sources)
        async let right = second.parse(logSources: sources)
        let results = await (left, right)
        XCTAssertEqual(results.0.lifetime.totalTokens, 150)
        XCTAssertEqual(results.1.lifetime.totalTokens, 150)
        let reads = await first.fileReadCountForTesting() + second.fileReadCountForTesting()
        XCTAssertEqual(reads, 1)
    }

    func testMtimeAndSizeInvalidateWithStaleLogSource() async throws {
        let url = try write("metadata.jsonl.zst", fixture())
        let oldDate = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let stale = LogSource(providerID: .codex, url: url, lastModified: oldDate)
        let parser = parser()
        _ = await parser.parse(logSources: [stale])
        let file = try FileHandle(forWritingTo: url)
        defer { file.closeFile() }
        let data = try fixture()
        try file.seek(toOffset: UInt64(data.count - 1))
        try file.write(contentsOf: Data([data[data.count - 1] ^ 1]))
        let changedDate = oldDate.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: changedDate], ofItemAtPath: url.path)
        _ = await parser.parse(logSources: [stale])
        try file.seekToEnd()
        try file.write(contentsOf: Data([0]))
        try FileManager.default.setAttributes([.modificationDate: changedDate], ofItemAtPath: url.path)
        let failed = await parser.parse(logSources: [stale])
        XCTAssertEqual(failed.warnings.first?.level, .info)
        let reads = await parser.fileReadCountForTesting()
        XCTAssertEqual(reads, 3)
    }

    func testRecordCapAndUnterminatedFinalRecordUseSharedFraming() async throws {
        let large = try write("large.jsonl.zst", fixture("oversized"))
        let tail = try write("tail.jsonl.zst", fixture("tail"))
        let parsed = await parser().parse(logSources: [source(large), source(tail)])
        XCTAssertEqual(parsed.lifetime.totalTokens, 300)
        XCTAssertEqual(parsed.warnings.count, 1)
        XCTAssertTrue(parsed.warnings[0].message.contains("1 malformed"))
    }

    func testDiscoveryRejectsDirectoriesAndSymbolicLinks() async throws {
        let target = try write("regular.jsonl.zst", fixture())
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions/directory.jsonl.zst"),
                                               withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("sessions/link.jsonl.zst"),
                                                   withDestinationURL: target)
        let sources = try await provider(parser()).discoverLogSources()
        XCTAssertEqual(sources.map(\.url.lastPathComponent), ["regular.jsonl.zst"])
        let discoveredURL = try XCTUnwrap(sources.first?.url)
        XCTAssertEqual(try inode(discoveredURL), inode(target))
    }
}
