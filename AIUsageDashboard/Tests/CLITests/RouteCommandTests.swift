import XCTest
@testable import AIUsageDashboardCore

final class RouteCommandTests: XCTestCase {
    private func snapshot(used: Double = 40, age: TimeInterval = 0, reset: TimeInterval = 600) -> AgentSnapshot {
        let now = Date().addingTimeInterval(-age)
        let window = QuotaWindow(providerID: .codex, type: .fiveHour, used: used, limit: 100,
                                  resetAt: now.addingTimeInterval(reset), confidence: .providerReported,
                                  source: "fixture", observedAt: now)
        let provider = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                        quotaWindows: [window], todayUsage: .unavailable, weekUsage: .unavailable)
        return AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
    }

    func testProcessFormattingJSONAndExitCodes() throws {
        for (value, arguments, expected) in [
            (snapshot(), [String](), Int32(0)),
            (snapshot(used: 85), [], 1),
            (snapshot(used: 100), [], 1),
            (snapshot(age: 601), [], 69),
            (snapshot(reset: -1), [], 69),
            (snapshot(), ["--for", "codex"], 0),
            (snapshot(), ["--for", "gemini"], 69),
            (snapshot(), ["--for", "nope"], 64),
            (snapshot(), ["--for"], 64),
            (snapshot(), ["--json", "--json"], 64),
            (snapshot(), ["--surprise"], 64)
        ] {
            let result = try ReviewCLIProbe.run(["route"] + arguments, snapshot: value)
            XCTAssertEqual(result.status, expected, "\(arguments), expected \(expected): \(result.text)")
            XCTAssertLessThan(result.text.split(separator: "\n").count, 16)
        }
        let json = try ReviewCLIProbe.run(["route", "--json"], snapshot: snapshot())
        XCTAssertEqual(json.status, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.text.utf8)) as? [String: Any])
        XCTAssertEqual(object["status"] as? String, "ready")
        XCTAssertEqual((object["rows"] as? [[String: Any]])?.count, 1)
        let help = try ReviewCLIProbe.run(["help"])
        for phrase in ["tokei route", "0 recommendation", "1 all plans", "69 missing", "64 invalid"] {
            XCTAssertTrue(help.text.contains(phrase), phrase)
        }
    }

    func testOldSnapshotFailsClosedAndJSONRemainsValid() throws {
        let old = AgentSnapshot(generatedAt: Date(), providers: [], aggregateUtilizationPercent: nil, recommendation: nil)
        let result = try ReviewCLIProbe.run(["route", "--json"], snapshot: old)
        XCTAssertEqual(result.status, 69)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(result.text.utf8)))
    }

    func testS5AgentWithoutAFlatRatePlanExplainsThatRefreshingWillNotHelp() throws {
        let value = AgentSnapshot(generatedAt: Date(), providers: [], aggregateUtilizationPercent: nil, recommendation: nil,
                                   route: AgentRoute(generatedAt: Date(), rows: [], unknown: []))
        let result = try ReviewCLIProbe.run(["route", "--for", "cline"], snapshot: value)
        XCTAssertEqual(result.status, 69)
        XCTAssertTrue(result.text.contains("Cline has no flat-rate plan to route to"))
        XCTAssertFalse(result.text.lowercased().contains("refresh"))
        let old = AgentSnapshot(generatedAt: Date(), providers: [], aggregateUtilizationPercent: nil, recommendation: nil)
        let legacy = try ReviewCLIProbe.run(["route", "--for", "cline"], snapshot: old)
        XCTAssertTrue(legacy.text.contains("No fresh plan recommendation"))
    }

    func testExpiredDecisionAndSanitizationAtReaderBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let row = AgentRouteRow(id: "/private/profile", provider: "codex", providerName: "bad\nname",
                                accountLabel: "person@example.com", windowType: "fiveHour", windowLabel: "bad\u{1b}[2J",
                                remainingPercent: 60, resetAt: now.addingTimeInterval(600), secondsToReset: 999,
                                paceState: "bad\nstate", disposition: "ready", reason: "bad\nreason",
                                validUntil: now.addingTimeInterval(100), expiringAt: now.addingTimeInterval(600))
        let value = AgentSnapshot(generatedAt: now, providers: [], aggregateUtilizationPercent: nil, recommendation: nil,
                                  route: AgentRoute(generatedAt: now, rows: [row], unknown: []))
        let result = RouteFormatting.output(value, now: now)
        let json = String(decoding: try AgentSnapshot.makeEncoder().encode(result), as: UTF8.self)
        for forbidden in ["person@", "/private", "bad", "999"] { XCTAssertFalse(json.contains(forbidden)) }
        XCTAssertEqual(result.rows[0].secondsToReset, 600)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(RouteFormatting.output(value, now: now.addingTimeInterval(101)).exitCode, 69)
        XCTAssertEqual(RouteFormatting.output(value, now: now.addingTimeInterval(-61)).exitCode, 69)
    }
}
