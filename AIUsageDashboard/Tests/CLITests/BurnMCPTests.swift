import XCTest
@testable import AIUsageDashboardCore

final class BurnMCPTests: XCTestCase {
    let now = AgentSnapshotFixtures.generatedAt.addingTimeInterval(60)

    func fixture(stale: Bool = false) -> AgentSnapshot {
        let windows = [
            AgentBurnWindow(provider: "codex", providerName: "Codex", accountID: "codex:a", type: "fiveHour",
                            usedPercent: 38, unusedPercent: 62, resetAt: now.addingTimeInterval(2_460), observedAt: now),
            AgentBurnWindow(provider: "claude_code", providerName: "Claude Code", type: "weekly",
                            usedPercent: 10, unusedPercent: 90, resetAt: now.addingTimeInterval(600), observedAt: now),
            AgentBurnWindow(provider: "codex", providerName: "Codex", type: "credits",
                            usedPercent: 0, unusedPercent: 100, resetAt: now.addingTimeInterval(60), observedAt: now),
            AgentBurnWindow(provider: "codex", providerName: "Codex", type: "daily",
                            usedPercent: 0, unusedPercent: 100, resetAt: now.addingTimeInterval(-1), observedAt: now),
            AgentBurnWindow(provider: "codex", providerName: "Codex", type: "daily",
                            usedPercent: 0, unusedPercent: 100, resetAt: now.addingTimeInterval(60), observedAt: now.addingTimeInterval(-1_801))
        ]
        return AgentSnapshot(generatedAt: stale ? now.addingTimeInterval(-601) : AgentSnapshotFixtures.generatedAt,
            providers: [], aggregateUtilizationPercent: nil, recommendation: nil,
            burn: AgentBurn(expiring: windows, streak: AgentBurnStreak(current: 7, todayHit: true),
                           today: AgentBurnToday(valueUSD: 12.5, goal: AgentBurnGoal(unit: "usd", target: 10), progress: 1.25)))
    }

    func call(snapshot: AgentSnapshot, name: String = "get_burn_opportunities", arguments: [String: Any] = [:]) throws -> [String: Any] {
        let directory = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try CLITestSupport.writeSnapshot(snapshot, in: directory)
        let capture = FrameCapture()
        let server = MCPServer(reader: SnapshotReader(fileURL: url, now: { self.now }), version: mcpTestVersion, output: capture.write)
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        server.handle(line: String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self))
        let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
        return try XCTUnwrap(result["structuredContent"] as? [String: Any])
    }

    func testBurnToolAdvertisesReadOnlyAndExactAdvice() throws {
        let (server, _) = try makeProtocolServer()
        let tool = try XCTUnwrap(server.toolDefinitions().first { $0["name"] as? String == "get_burn_opportunities" })
        XCTAssertEqual(server.toolDefinitions().count, 3)
        XCTAssertEqual(tool["title"] as? String, "Use it or lose it")
        XCTAssertEqual((tool["annotations"] as? [String: Bool])?["readOnlyHint"], true)
        XCTAssertTrue(MCPServer.instructions.contains("Never spend credits or paid overage"))
        let result = try call(snapshot: fixture())
        let rows = try XCTUnwrap(result["expiring"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0["provider"] as? String }, ["claude_code", "codex"])
        XCTAssertEqual(rows[1]["accountID"] as? String, "codex:a")
        XCTAssertEqual(rows[1]["advice"] as? String,
            "Codex 5-hour window has 62% left and resets in 41 min: run optional or batch work there first")
    }

    func testStaleSnapshotDoesNotOfferCapacity() throws {
        XCTAssertEqual((try call(snapshot: fixture(stale: true))["expiring"] as? [[String: Any]])?.count, 0)
    }

    func testAbsentDetailKeepsFullDocumentedShapeAndSummaryIsSmaller() throws {
        let original = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: Data(AgentSnapshotFixtures.full.utf8))
        let full = try call(snapshot: original, name: "get_usage")
        let data = try JSONSerialization.data(withJSONObject: full)
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)
        XCTAssertEqual(decoded.providers, original.providers)
        XCTAssertEqual(decoded.schemaVersion, 1)
        let summary = try call(snapshot: original, name: "get_usage", arguments: ["detail": "summary"])
        let rows = try XCTUnwrap(summary["providers"] as? [[String: Any]])
        XCTAssertEqual(rows.count, original.providers.count)
        XCTAssertTrue(rows.allSatisfy { ($0["summary"] as? String)?.contains("\n") == false })
        XCTAssertLessThan(try JSONSerialization.data(withJSONObject: summary).count, data.count / 2)
    }

    func testBurnFormattingIsOneScreenAndIncludesGoalAndStreak() {
        let text = BurnFormatting.render(fixture().withStaleness(asOf: now), now: now)
        XCTAssertTrue(text.contains("62% left and resets in 41 min"))
        XCTAssertTrue(text.contains("Streak: 7 days · today's goal hit"))
        XCTAssertTrue(text.contains("Today: $12.50 API-equivalent value · goal $10.00 · 125%"))
        XCTAssertFalse(text.contains("codex:a"))
        XCTAssertLessThan(text.split(separator: "\n").count, 15)
    }

    func testBurnFormattingOldSnapshotAndStaleState() {
        let old = AgentSnapshot(generatedAt: now, providers: [], aggregateUtilizationPercent: nil, recommendation: nil)
        XCTAssertTrue(BurnFormatting.render(old, now: now).contains("No fresh plan windows"))
        let text = BurnFormatting.render(fixture(stale: true).withStaleness(asOf: now), now: now)
        XCTAssertTrue(text.contains("out of date"))
        XCTAssertFalse(text.contains("62% left"))
    }
}
