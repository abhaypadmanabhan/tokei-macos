import CryptoKit
import Foundation
import XCTest
@testable import AIUsageDashboardCore

final class ZstdRealLogsOracleTests: XCTestCase {
    func testEveryCompressedCodexRolloutMatchesZstdCLI() throws {
        try requireRealLogsOptIn()
        let executable = try XCTUnwrap(zstdExecutable(), "Install zstd to run the independent corpus oracle")
        let sessions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        ))
        let files = enumerator.compactMap { $0 as? URL }.filter { url in
            guard url.lastPathComponent.hasSuffix(".jsonl.zst"),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
                return false
            }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { $0.path < $1.path }
        try XCTSkipIf(files.isEmpty, "No compressed Codex rollouts on this machine")
        print("ZSTD-CORPUS-START files=\(files.count)")
        var seconds = 0.0
        var totalBytes = 0
        var mismatches = 0
        for (index, file) in files.enumerated() {
            try autoreleasepool {
                var hash = SHA256()
                var bytes = 0
                let start = ProcessInfo.processInfo.systemUptime
                do {
                    try ZstdDecoder.decode(fileAt: file) { chunk in
                        hash.update(data: chunk)
                        bytes += chunk.count
                    }
                } catch {
                    seconds += ProcessInfo.processInfo.systemUptime - start
                    mismatches += 1
                    XCTFail("Decoder failed at corpus index \(index): \(error)")
                    return
                }
                seconds += ProcessInfo.processInfo.systemUptime - start
                totalBytes += bytes
                let expected = try referenceDigest(file: file, executable: executable)
                if Data(hash.finalize()) != expected {
                    mismatches += 1
                    XCTFail("SHA-256 mismatch at corpus index \(index)")
                }
            }
            if (index + 1) % 100 == 0 { print("ZSTD-CORPUS-PROGRESS files=\(index + 1) mismatches=\(mismatches)") }
        }
        let rate = Double(totalBytes) / max(seconds, 0.000001) / 1_000_000
        print("ZSTD-CORPUS files=\(files.count) mismatches=\(mismatches) bytes=\(totalBytes) "
            + "decodeSeconds=\(seconds) MBps=\(rate)")
        XCTAssertEqual(mismatches, 0)
    }

    private func zstdExecutable() throws -> URL? {
        for path in ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
            where FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        throw XCTSkip("zstd is absent; every file skipped because there is no independent decoder")
    }

    private func referenceDigest(file: URL, executable: URL) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-q", "-d", "-c", "--", file.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        defer {
            output.fileHandleForReading.closeFile()
            errors.fileHandleForReading.closeFile()
            if process.isRunning { process.terminate(); process.waitUntilExit() }
        }
        var hash = SHA256()
        while let chunk = try output.fileHandleForReading.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        process.waitUntilExit()
        // Never print rollout content or stderr (which may include private file names).
        guard process.terminationStatus == 0 else { throw OracleError.referenceFailed }
        return Data(hash.finalize())
    }

    private enum OracleError: Error { case referenceFailed }
}
