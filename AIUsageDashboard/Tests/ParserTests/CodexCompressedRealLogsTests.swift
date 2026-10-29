import XCTest
@testable import AIUsageDashboardCore

private enum WP5CodexOracle {
    struct Counts: Decodable {
        let files: Int
        let compressedFiles: Int
        let errors: Int
        let selfCheck: Bool
        let tokens: Int
        let input: Int
        let output: Int
        let cacheRead: Int
        let reasoning: Int
        let lifetimeTokens: Int
        let mtdUsd: Double
    }

    static func count(root: URL, reference: Date) throws -> Counts {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOKEI_REAL_LOGS"] == "1",
                          "Set TOKEI_REAL_LOGS=1 to launch the independent Python/zstd recount")
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let script = tests.appendingPathComponent("Fixtures/wp5_codex_oracle.py")
        let seed = tests.deletingLastPathComponent()
            .appendingPathComponent("AIUsageDashboardApp/Core/Pricing/PricingSeed.swift")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, root.path, String(reference.timeIntervalSince1970), seed.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw OracleError.referenceFailed }
        return try JSONDecoder().decode(Counts.self, from: data)
    }

    private enum OracleError: Error { case referenceFailed }
}

final class CodexCompressedRealLogsTests: XCTestCase {
    func testOracleCannotLaunchWithoutExplicitOptIn() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TOKEI_REAL_LOGS"] == "1", "Tests the default mode")
        XCTAssertThrowsError(try WP5CodexOracle.count(root: URL(fileURLWithPath: "/not-used"), reference: Date())) {
            XCTAssertTrue($0 is XCTSkip)
        }
    }

    func testOctoberTokensAndValueMatchIndependentRecount() async throws {
        try requireRealLogsOptIn()
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let reference = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let priorTimeZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = priorTimeZone }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let pricing = PricingService(refresher: NoOpPricingTableRefresher(),
                                     cacheURL: temporary.appendingPathComponent("prices.json"))
        let parser = CodexJSONLParser(calendar: calendar, now: { reference })
        // The discovery adapter supplies only the log root; it never reads credential contents.
        let provider = CodexProvider(parser: parser, codexDirectory: root, pricing: pricing,
                                     environment: [:], discoverer: CodexLogOnlyDiscovery(root: root),
                                     now: { reference })
        let sources = try await provider.discoverLogSources()
        try XCTSkipIf(sources.isEmpty, "No Codex session logs")
        let compressedFiles = sources.filter { CodexRolloutFiles.isCompressed($0.url) }.count
        XCTAssertGreaterThan(compressedFiles, 0)
        let coldStart = ProcessInfo.processInfo.systemUptime
        let snapshot = try await provider.fetchSnapshot()
        let coldSeconds = ProcessInfo.processInfo.systemUptime - coldStart
        let decoderSeconds = await parser.compressedDecodeSecondsForTesting()
        let readCount = await parser.fileReadCountForTesting()
        let month = try XCTUnwrap(calendar.dateInterval(of: .month, for: reference))
        let days = snapshot.dailyModelUsage ?? [:]
        let selected = days.filter { $0.key >= month.start && $0.key <= reference }.map(\.value)
        let models = UsageAggregation.sumModels(selected)
        let totals = UsageAggregation.sum(Array(models.values))
        let amount = try XCTUnwrap(snapshot.costUsage?.amount)
        let warmStart = ProcessInfo.processInfo.systemUptime
        _ = await parser.parse(logSources: sources)
        let warmSeconds = ProcessInfo.processInfo.systemUptime - warmStart
        let warmDecoderSeconds = await parser.compressedDecodeSecondsForTesting()
        XCTAssertEqual(warmDecoderSeconds, decoderSeconds, "Unchanged compressed fingerprints must never decode twice")
        let oracle = try WP5CodexOracle.count(root: root, reference: reference)
        compare(snapshot: snapshot, totals: totals, oracle: oracle,
                files: sources.count, compressedFiles: compressedFiles)
        print("WP5_CODEX files=\(sources.count) compressed=\(compressedFiles) filesRead=\(readCount) "
            + "octoberTokens=\(totals.totalTokens ?? 0) mtdUsd=\(amount) warnings=\(snapshot.warnings.count)")
        print("WP5_ORACLE files=\(oracle.files) compressed=\(oracle.compressedFiles) "
            + "octoberTokens=\(oracle.tokens) mtdUsd=\(oracle.mtdUsd) errors=\(oracle.errors)")
        print("WP5_TIMING coldSeconds=\(coldSeconds) decoderSeconds=\(decoderSeconds) warmSeconds=\(warmSeconds) "
            + "decoderTargetSeconds=15 targetMet=\(decoderSeconds < 15)")
        XCTAssertLessThan(decoderSeconds, 15, "Record the host load and timing; do not claim the CPU gate passed")
    }

    private func compare(snapshot: ProviderSnapshot, totals: TokenUsage,
                         oracle: WP5CodexOracle.Counts, files: Int, compressedFiles: Int) {
        XCTAssertTrue(oracle.selfCheck)
        XCTAssertEqual(oracle.errors, 0)
        XCTAssertEqual(files, oracle.files)
        XCTAssertEqual(compressedFiles, oracle.compressedFiles)
        assertNear(totals.totalTokens ?? 0, oracle.tokens)
        assertNear(totals.inputTokens ?? 0, oracle.input)
        assertNear(totals.cacheReadTokens ?? 0, oracle.cacheRead)
        assertNear(totals.outputTokens ?? 0, oracle.output)
        assertNear(totals.reasoningTokens ?? 0, oracle.reasoning)
        assertNear(snapshot.lifetimeUsage?.totalTokens ?? 0, oracle.lifetimeTokens)
        XCTAssertEqual(snapshot.costUsage?.amount ?? -1, oracle.mtdUsd,
                       accuracy: max(0.000001, oracle.mtdUsd * 0.005))
    }

    private func assertNear(_ actual: Int, _ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(actual), Double(expected), accuracy: max(1, Double(expected) * 0.005),
                       file: file, line: line)
    }
}
