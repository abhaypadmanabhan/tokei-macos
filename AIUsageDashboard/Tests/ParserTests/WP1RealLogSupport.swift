import XCTest
@testable import AIUsageDashboardCore

/// Runs an explicitly opted-in separate-language recount against fixtures or real session logs.
enum WP1CopilotOracle {
    static func counts(root: URL, cutoff: Date) throws -> [String: Int] {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOKEI_REAL_LOGS"] == "1",
                          "Set TOKEI_REAL_LOGS=1 to run external Python oracle checks")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/wp1_copilot_oracle.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, root.path, String(cutoff.timeIntervalSince1970)]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(data: errorData, encoding: .utf8) ?? "Python failed")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
    }

    static func counts(_ parsed: CopilotSessionParser.AggregateUsage) -> [String: Int] {
        let tokens = parsed.lifetime
        let input = tokens.inputTokens ?? 0
        let cached = tokens.cacheReadTokens ?? 0
        let creation = tokens.cacheCreationTokens ?? 0
        return ["shutdowns": parsed.shutdownCount, "input": input, "cacheRead": cached, "cacheWrite": creation,
                "output": (tokens.outputTokens ?? 0) + (tokens.reasoningTokens ?? 0),
                "reasoning": tokens.reasoningTokens ?? 0, "reportedInput": input + cached + creation,
                "total": tokens.totalTokens ?? 0]
    }

    static func json(_ counts: [String: Int]) throws -> String {
        try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: counts, options: [.sortedKeys]),
                             encoding: .utf8))
    }
}

final class WP1CopilotOracleTests: XCTestCase {
    func testPythonOracleRequiresRealLogsOptInBeforeLaunching() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TOKEI_REAL_LOGS"] == "1",
                      "This check exercises the default unit-test mode")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try WP1CopilotOracle.counts(root: root, cutoff: Date())) { error in
            XCTAssertTrue(error is XCTSkip, "The opt-in check must run before any Python process")
        }
    }
}
