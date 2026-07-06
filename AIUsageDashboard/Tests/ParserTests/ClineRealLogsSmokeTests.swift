import XCTest
@testable import AIUsageDashboardCore

/// Runs the Cline parser against this machine's local Cline CLI session logs.
/// Skips on machines without logs. Prints token totals and real dollar cost.
final class ClineRealLogsSmokeTests: XCTestCase {
    func testRealClineLogsParse() async throws {
        let cline = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cline", isDirectory: true)
        let sessions = cline.appendingPathComponent("data/sessions", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sessions.path),
            "No Cline session logs on this machine"
        )

        let provider = ClineProvider()
        let sources = try await provider.discoverLogSources()
        try XCTSkipIf(sources.isEmpty, "Cline sessions directory is empty")

        let usage = await ClineMessagesParser().parse(logSources: sources)

        print("CLINE-REAL-LOGS files=\(sources.count) lifetime=\(usage.lifetime.totalTokens ?? -1) today=\(usage.today.totalTokens ?? -1) week=\(usage.week.totalTokens ?? -1) month=\(usage.month.totalTokens ?? -1) totalCost=\(usage.totalCost) warnings=\(usage.warnings.count)")

        XCTAssertGreaterThan(usage.lifetime.totalTokens ?? 0, 0)
        XCTAssertGreaterThan(usage.totalCost, 0)
    }
}
