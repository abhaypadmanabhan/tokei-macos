import XCTest
@testable import AIUsageDashboardCore

final class CLIVersionProcessTests: XCTestCase {
    func testS6AppVerificationRunsTheBundledHelperGateBeforeAnyLaunch() throws {
        let directory = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Tokei.app")
        let binary = app.appendingPathComponent("Contents/MacOS/Tokei")
        let helper = app.appendingPathComponent("Contents/Helpers/tokei")
        for file in [binary, helper] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try Data("#!/bin/sh\necho 'tokei fixture-drift'\n".utf8).write(to: helper)
        for file in [binary, helper] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [project.appendingPathComponent("scripts/verify-app.sh").path, app.path]
        process.currentDirectoryURL = project.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["TOKEI_VERIFY_SKIP_LAUNCH"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        let output = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(output.contains("built helper reports tokei fixture-drift"), output)
        XCTAssertFalse(output.contains("app TeamIdentifier="), "version drift must stop before signing or launch checks")
    }

    func testBuiltHelperReportsProjectMarketingVersion() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("project.yml")
        let source = try String(contentsOf: project, encoding: .utf8)
        let line = try XCTUnwrap(source.split(separator: "\n").first { $0.contains("MARKETING_VERSION:") })
        let version = try XCTUnwrap(line.split(separator: "\"").dropFirst().first)
        let result = try ReviewCLIProbe.run(["version"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.text, "tokei \(version)\n")
    }
}
