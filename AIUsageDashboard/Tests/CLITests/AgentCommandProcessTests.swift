import XCTest
import Foundation

final class AgentCommandProcessTests: XCTestCase {
    func run(_ arguments: [String], root: URL) throws -> (Int32, String) {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("tokei")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = ["HOME": root.path, "PATH": root.appendingPathComponent("bin").path,
            "CLAUDE_CONFIG_DIR": root.appendingPathComponent("fake-claude").path,
            "CODEX_HOME": root.appendingPathComponent("fake-codex").path]
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testDryRunDispatchesClientFlagsWithoutExecutingClient() throws {
        let root = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["claude", "codex"] {
            let script = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 99\n".utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        for client in ["claude", "codex", "cursor"] {
            let (status, output) = try run(["mcp", "install", "--dry-run", "--client", client], root: root)
            XCTAssertEqual(status, 0, output)
            XCTAssertTrue(output.contains("Would"))
            XCTAssertTrue(output.contains("mcp"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fake-codex").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor").path))
    }

    func testInvalidOptionsFailBeforeAnyClientCanRun() throws {
        let root = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for args in [["mcp", "install", "--client"], ["mcp", "install", "--client", "typo"],
                     ["mcp", "install", "--dry-run", "--dry-run"], ["mcp", "unknown"],
                     ["install", "--unknown"], ["burn", "--unknown"]] {
            XCTAssertEqual(try run(args, root: root).0, 64, args.joined(separator: " "))
        }
        let (_, help) = try run(["help"], root: root)
        for phrase in ["get_burn_opportunities", "summary", "uninstall", "tokei install", "tokei burn"] {
            XCTAssertTrue(help.contains(phrase), phrase)
        }
    }
}
