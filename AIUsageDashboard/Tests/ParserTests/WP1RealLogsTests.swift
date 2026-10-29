import XCTest
@testable import AIUsageDashboardCore

final class WP1RealLogsTests: XCTestCase {
    func testClaudeMonthToDateBeforeAndAfterOneHourCachePricing() async throws {
        try requireRealLogsOptIn()
        let reference = Date()
        let calendar = Calendar.current
        let accounts = try claudeAccounts()
        XCTAssertFalse(accounts.isEmpty)
        let parsed = await ClaudeJSONLParser(calendar: calendar, now: { reference }).parse(accountLogSources: accounts)
        let models = UsageAggregation.sumModels(UsageAggregation.mergeModels(parsed.byAccountID.values
            .map(\.dailyModelUsage)).filter { $0.key <= reference }.map(\.value))
        let pricing = PricingEngine(table: PricingService.cachedTable())
        var before = 0.0
        var after = 0.0
        var oneHour = 0
        var unpriced = 0
        for (model, tokens) in models {
            let legacy = TokenUsage(inputTokens: tokens.inputTokens, outputTokens: tokens.outputTokens,
                                    cacheReadTokens: tokens.cacheReadTokens,
                                    cacheCreationTokens: tokens.cacheCreationTokens,
                                    reasoningTokens: tokens.reasoningTokens, confidence: tokens.confidence)
            oneHour += tokens.cacheCreation1hTokens ?? 0
            guard let oldCost = pricing.cost(model: model, tokens: legacy),
                  let newCost = pricing.cost(model: model, tokens: tokens) else { unpriced += 1; continue }
            before += oldCost
            after += newCost
        }
        print(String(format: "CLAUDE_MTD before_usd=%.6f after_usd=%.6f delta_usd=%.6f",
                     locale: Locale(identifier: "en_US_POSIX"), before, after, after - before)
              + " one_hour_tokens=\(oneHour) unpriced_models=\(unpriced)"
              + " files=\(accounts.flatMap(\.logSources).count)")
        XCTAssertGreaterThan(oneHour, 0)
        XCTAssertGreaterThan(after, before)
    }

    func testAntigravityHistoryMatchesIndependentResearchOracle() async throws {
        try requireRealLogsOptIn()
        let parsed = await AntigravityConversationParser().parse()
        let output = (parsed.lifetime.outputTokens ?? 0) + (parsed.lifetime.reasoningTokens ?? 0)
        let models = UsageAggregation.sumModels(Array(parsed.dailyModelUsage.values))
        let pricing = PricingEngine(table: PricingService.cachedTable())
        let cost = models.compactMap { pricing.cost(model: $0.key, tokens: $0.value) }.reduce(0, +)
        let files = AntigravityConversationFiles.discover(AntigravityConversationFiles.defaultRoots()).files.count
        print("ANTIGRAVITY files=\(files) records=\(parsed.records.count)"
              + " input=\(parsed.lifetime.inputTokens ?? 0) cached=\(parsed.lifetime.cacheReadTokens ?? 0)"
              + " output=\(output) reasoning=\(parsed.lifetime.reasoningTokens ?? 0)"
              + String(format: " usd=%.6f", locale: Locale(identifier: "en_US_POSIX"), cost))
        XCTAssertTrue(parsed.warnings.isEmpty)
        if parsed.records.count == 1_587 {
            XCTAssertEqual(parsed.lifetime.inputTokens, 12_191_150)
            XCTAssertEqual(parsed.lifetime.cacheReadTokens, 118_753_352)
            XCTAssertEqual(output, 1_007_948)
            XCTAssertEqual(parsed.lifetime.reasoningTokens, 573_512)
            XCTAssertEqual(cost, 41.66, accuracy: 0.4166)
        } else {
            // Drift is accepted only when extra dated requests explain the additional records.
            let afterOracle = Date(timeIntervalSince1970: 1_786_665_600) // 2026-08-14 00:00 UTC
            let newRows = parsed.records.filter { $0.timestamp >= afterOracle }.count
            XCTAssertGreaterThan(parsed.records.count, 1_587)
            XCTAssertGreaterThanOrEqual(newRows, parsed.records.count - 1_587)
            XCTAssertGreaterThanOrEqual(parsed.lifetime.inputTokens ?? 0, 12_191_150)
            XCTAssertGreaterThanOrEqual(parsed.lifetime.cacheReadTokens ?? 0, 118_753_352)
            XCTAssertGreaterThanOrEqual(output, 1_007_948)
            print("ANTIGRAVITY_ORACLE_DRIFT new_dated_records=\(newRows)")
        }
    }

    func testCopilotCountsMatchIndependentPythonRecountExactly() async throws {
        try requireRealLogsOptIn()
        let reference = Date()
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/session-state")
        let parsed = await CopilotSessionParser(sessionStateDirectory: root, now: { reference }).parse()
        let swift = try WP1CopilotOracle.json(WP1CopilotOracle.counts(parsed))
        let python = try WP1CopilotOracle.json(WP1CopilotOracle.counts(root: root, cutoff: reference))
        print("COPILOT_SWIFT \(swift)")
        print("COPILOT_PYTHON \(python)")
        print("COPILOT_WARNINGS count=\(parsed.warnings.count)")
        XCTAssertGreaterThan(parsed.shutdownCount, 0)
        XCTAssertEqual(swift, python)
    }

    /// Walk only project JSONL files. Never enter configuration, credential or plugin directories.
    private func claudeAccounts() throws -> [ClaudeJSONLParser.AccountLogSources] {
        let manager = FileManager.default
        let roots = try manager.contentsOfDirectory(at: manager.homeDirectoryForCurrentUser,
                                                    includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent == ".claude" || $0.lastPathComponent.hasPrefix(".claude-") }
        return roots.sorted { $0.path < $1.path }.compactMap { root in
            let projects = root.appendingPathComponent("projects")
            guard manager.fileExists(atPath: projects.path),
                  let enumerator = manager.enumerator(at: projects,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return nil }
            var sources: [LogSource] = []
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if url.pathExtension == "jsonl", values?.isRegularFile == true {
                    sources.append(LogSource(providerID: .claudeCode, url: url))
                }
            }
            guard !sources.isEmpty else { return nil }
            return ClaudeJSONLParser.AccountLogSources(accountID: root.path, logSources: sources)
        }
    }
}
