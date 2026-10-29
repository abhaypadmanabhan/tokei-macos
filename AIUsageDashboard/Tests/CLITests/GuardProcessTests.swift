import XCTest
@testable import AIUsageDashboardCore

final class GuardProcessTests: XCTestCase {
    func testGuardExitCodesAndSingleLineOutput() throws {
        for (headroom, age, arguments, expected) in [
            (85.0, 0.0, [String](), Int32(0)),
            (14, 0, [], 1),
            (15, 0, ["--min-headroom", "15"], 0),
            (85, 601, [], 69),
            (85, 0, ["--provider", "codex"], 0),
            (85, 0, ["--provider", "gemini"], 69),
            (85, 0, ["--provider", "bad"], 64),
            (85, 0, ["--min-headroom", "nan"], 64),
            (85, 0, ["--min-headroom", "101"], 64),
            (85, 0, ["--min-headroom"], 64),
            (85, 0, ["--unexpected"], 64)
        ] {
            let now = Date()
            let window = AgentWindow(type: "session", usedPercent: 100 - headroom,
                                      resetsAt: now.addingTimeInterval(1_000), confidence: "official",
                                      source: "fixture", observedAt: now)
            let account = AgentAccount(id: "/fixture", label: "fixture", windows: [window], tokensToday: 0,
                                        accountID: "codex:fixture", quota: AgentAccountQuota(
                                            status: "eligible", usedPercent: 100 - headroom,
                                            headroomPercent: headroom, bindingWindowIndex: 0,
                                            validUntil: now.addingTimeInterval(600)))
            let provider = AgentProvider(id: "codex", displayName: "Codex", windows: [window],
                                          tokensToday: 0, lastUpdated: now, accounts: [account],
                                          headlineAccountID: account.accountID)
            let snapshot = AgentSnapshot(generatedAt: now.addingTimeInterval(-age), providers: [provider],
                                          aggregateUtilizationPercent: nil, recommendation: AgentRecommendation(
                                            routeTo: "codex", avoid: [], reason: "fixture",
                                            validUntil: now.addingTimeInterval(600)))
            let directory = try CLITestSupport.temporaryDirectory()
            let url = try CLITestSupport.writeSnapshot(snapshot, in: directory)
            trackForCleanup(url)
            let process = Process()
            process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
                .appendingPathComponent("tokei")
            process.arguments = ["guard"] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment["TOKEI_SNAPSHOT_PATH"] = url.path
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, expected, "args: \(arguments), headroom: \(headroom)")
            XCTAssertEqual(String(bytes: data, encoding: .utf8)?.split(separator: "\n").count, 1)
        }
    }

    func testMCPClosedStdoutExitsCleanly() throws {
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("tokei")
        process.arguments = ["mcp"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try output.fileHandleForReading.close()
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8))
        try input.fileHandleForWriting.write(contentsOf: Data([0x0A]))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
