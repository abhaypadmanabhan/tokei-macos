import XCTest
@testable import AIUsageDashboardCore

/// Runs the Codex parser against this machine's local Codex CLI session logs.
/// Skips on machines without logs. Prints both token delta and final cumulative
/// totals so the relay can verify the parser against Codex's own counters.
final class CodexRealLogsSmokeTests: XCTestCase {
    func testRealCodexLogsParse() async throws {
        let codex = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let sessions = codex.appendingPathComponent("sessions", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sessions.path),
            "No Codex session logs on this machine"
        )

        let provider = CodexProvider()
        let sources = try await provider.discoverLogSources()
        try XCTSkipIf(sources.isEmpty, "Codex sessions directory is empty")

        let usage = await CodexJSONLParser().parse(logSources: sources)
        let quotaSummary = usage.quotaWindows
            .map { "\($0.type.rawValue)=\($0.used ?? -1)% reset=\($0.resetAt?.description ?? "nil") confidence=\($0.confidence.rawValue)" }
            .joined(separator: ", ")

        print("CODEX-REAL-LOGS files=\(sources.count) deltaTotal=\(usage.deltaReportedTotalTokens) finalSessionTotal=\(usage.finalReportedTotalTokens) lifetime=\(usage.lifetime.totalTokens ?? -1) today=\(usage.today.totalTokens ?? -1) week=\(usage.week.totalTokens ?? -1) month=\(usage.month.totalTokens ?? -1) quota=[\(quotaSummary)] warnings=\(usage.warnings.count)")

        XCTAssertGreaterThan(usage.deltaReportedTotalTokens, 0)
        XCTAssertGreaterThan(usage.finalReportedTotalTokens, 0)
        let diff = abs(usage.deltaReportedTotalTokens - usage.finalReportedTotalTokens)
        XCTAssertLessThanOrEqual(Double(diff) / Double(usage.finalReportedTotalTokens), 0.05)
        XCTAssertFalse(usage.quotaWindows.isEmpty)
    }
}
