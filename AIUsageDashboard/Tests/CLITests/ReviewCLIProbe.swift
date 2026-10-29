import Foundation
import XCTest
@testable import AIUsageDashboardCore

enum ReviewCLIProbe {
    struct Output {
        let status: Int32
        let reason: Process.TerminationReason
        let text: String
    }

    static func run(_ arguments: [String], snapshot: AgentSnapshot? = nil, closedOutput: Bool = false) throws -> Output {
        let directory = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = Bundle(for: FrameCapture.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("tokei")
        process.arguments = arguments
        if let snapshot {
            let url = try CLITestSupport.writeSnapshot(snapshot, in: directory)
            var environment = ProcessInfo.processInfo.environment
            environment["TOKEI_SNAPSHOT_PATH"] = url.path
            process.environment = environment
        }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if closedOutput { try output.fileHandleForReading.close() }
        try process.run()
        let data = closedOutput ? Data() : output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, reason: process.terminationReason,
                      text: String(bytes: data, encoding: .utf8) ?? "")
    }
}
