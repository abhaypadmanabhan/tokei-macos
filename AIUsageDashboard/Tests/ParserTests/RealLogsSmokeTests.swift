import Darwin
import XCTest
@testable import AIUsageDashboardCore

/// Runs the shipping parser against this machine's real Claude Code logs.
/// Skips on machines without logs. Prints totals so integration can diff them
/// against an independent baseline (dedupe by message.id ?? requestId ?? uuid).
final class RealLogsSmokeTests: XCTestCase {
    func testRealLogsParse() async throws {
        try requireRealLogsOptIn()

        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: projects.path),
            "No Claude Code logs on this machine"
        )

        let provider = ClaudeCodeProvider()
        let sources = try await provider.discoverLogSources()
        try XCTSkipIf(sources.isEmpty, "Claude projects directory is empty")

        let usage = await ClaudeJSONLParser().parse(logSources: sources)

        print("REAL-LOGS files=\(sources.count) lifetime=\(usage.lifetime.totalTokens ?? -1) today=\(usage.today.totalTokens ?? -1) week=\(usage.week.totalTokens ?? -1) month=\(usage.month.totalTokens ?? -1) warnings=\(usage.warnings.count)")

        XCTAssertGreaterThan(usage.lifetime.totalTokens ?? 0, 0)
    }
}

/// Opt-in proof of the shipping parsers and MTD value engine. Reads transcript
/// directories directly, so this test never discovers accounts or reads auth files.
final class ValueByModelRealLogsSmokeTests: XCTestCase {
    func testValueByModelOnRealCorpus() async throws {
        try requireRealLogsOptIn()
        let now = Date()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [".claude", ".claude-account-1"].map { home.appendingPathComponent($0) }
        let accounts = try roots.map { root in
            ClaudeJSONLParser.AccountLogSources(
                accountID: root.path,
                logSources: try sources(in: root.appendingPathComponent("projects"), provider: .claudeCode)
            )
        }
        let codexSources = try sources(in: home.appendingPathComponent(".codex/sessions"), provider: .codex)
        try XCTSkipIf(
            accounts.allSatisfy { $0.logSources.isEmpty } || codexSources.isEmpty, "Missing real transcripts"
        )
        let formatter = ISO8601DateFormatter()
        let month = try XCTUnwrap(Calendar.current.dateInterval(of: .month, for: now))
        print("REAL-LOGS value-by-model monthStart=\(formatter.string(from: month.start)) "
              + "now=\(formatter.string(from: now))")
        let pricing = PricingEngine(table: PricingService.cachedTable())
        let claudeParser = ClaudeJSONLParser(now: { now })
        var started = Date()
        let claude = await claudeParser.parse(accountLogSources: accounts)
        let claudeColdMS = Date().timeIntervalSince(started) * 1_000
        started = Date()
        _ = await claudeParser.parse(accountLogSources: accounts)
        let claudeWarmMS = Date().timeIntervalSince(started) * 1_000
        let claudeModels = UsageAggregation.mergeModels(claude.byAccountID.values.map(\.dailyModelUsage))
        try report(.claudeCode, models: claudeModels, now: now, pricing: pricing)
        print("REAL-LOGS value-by-model provider=claude files=\(accounts.flatMap(\.logSources).count) "
              + "days=\(claudeModels.count) coldMS=\(claudeColdMS) warmMS=\(claudeWarmMS)")

        let codexParser = CodexJSONLParser(now: { now })
        started = Date()
        let codex = await codexParser.parse(logSources: codexSources)
        let codexColdMS = Date().timeIntervalSince(started) * 1_000
        let reads = await codexParser.fileReadCountForTesting()
        started = Date()
        _ = await codexParser.parse(logSources: codexSources)
        let codexWarmMS = Date().timeIntervalSince(started) * 1_000
        let warmReads = await codexParser.fileReadCountForTesting()
        XCTAssertEqual(warmReads, reads, "warm scan must not read transcript bodies")
        try report(.codex, models: codex.dailyModelUsage, now: now, pricing: pricing)
        var resourceUsage = rusage()
        let status = getrusage(RUSAGE_SELF, &resourceUsage)
        XCTAssertEqual(status, 0)
        print("REAL-LOGS value-by-model provider=codex files=\(codexSources.count) "
              + "days=\(codex.dailyModelUsage.count) coldMS=\(codexColdMS) warmMS=\(codexWarmMS) "
              + "warmFileReads=\(warmReads - reads) peakRSSBytes=\(resourceUsage.ru_maxrss)")
    }

    private func report(
        _ provider: ProviderID,
        models: [Date: [String: TokenUsage]],
        now: Date,
        pricing: PricingEngine
    ) throws {
        XCTAssertLessThanOrEqual(models.count, 31)
        let snapshot = ProviderSnapshot(
            providerID: provider, displayName: provider.rawValue, authStatus: .unknown,
            todayUsage: .unavailable, weekUsage: .unavailable, dailyModelUsage: models
        )
        let suite = "wp1-smoke-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = try XCTUnwrap(MaxxerValueEngine.scorecard(
            snapshots: [snapshot], planCosts: MaxxerPlanCostStore(defaults: defaults), now: now, pricing: pricing
        ).providers.first)
        XCTAssertGreaterThan(try XCTUnwrap(value.apiEquivalentUSD), 0)
        let name = provider == .claudeCode ? "claude" : "codex"
        let total = String(format: "%.6f", value.apiEquivalentUSD ?? 0)
        print("REAL-LOGS value-by-model provider=\(name) mtdUSD=\(total) "
              + "hasUnpricedTokens=\(value.hasUnpricedTokens)")
        for row in value.models {
            let amount = row.apiEquivalentUSD.map { String(format: "%.6f", $0) } ?? "unpriced"
            print("REAL-LOGS value-by-model provider=\(name) model=\(row.model) "
                  + "tokens=\(row.totalTokens) usd=\(amount)")
        }
    }

    private func sources(in root: URL, provider: ProviderID) throws -> [LogSource] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        var result: [LogSource] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            result.append(LogSource(providerID: provider, url: url,
                                    sessionID: url.deletingPathExtension().lastPathComponent,
                                    lastModified: values.contentModificationDate))
        }
        return result.sorted { $0.url.path < $1.url.path }
    }
}
