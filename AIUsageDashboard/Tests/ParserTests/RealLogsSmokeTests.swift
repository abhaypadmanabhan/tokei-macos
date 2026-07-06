import XCTest
@testable import AIUsageDashboardCore

/// Runs the shipping parser against this machine's real Claude Code logs.
/// Skips on machines without logs. Prints totals so integration can diff them
/// against an independent baseline (dedupe by message.id ?? requestId ?? uuid).
final class RealLogsSmokeTests: XCTestCase {
    func testRealLogsParse() async throws {
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
