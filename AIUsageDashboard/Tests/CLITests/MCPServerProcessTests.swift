import Darwin
import Foundation
import XCTest

enum MCPProcessHarnessError: Error {
  case helperMissing(URL)
  case invalidResponse
  case readFailed(Int32)
  case timedOut
}

final class MCPProcessHarness {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let error = Pipe()
  private var bufferedOutput = Data()

  init() throws {
    let helperURL = Bundle(for: MCPProcessHarness.self).bundleURL
      .deletingLastPathComponent()
      .appendingPathComponent("tokei")
    guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
      throw MCPProcessHarnessError.helperMissing(helperURL)
    }

    process.executableURL = helperURL
    process.arguments = ["mcp"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
  }

  deinit {
    stop()
  }

  var isRunning: Bool {
    process.isRunning
  }

  func write(_ text: String) throws {
    try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
  }

  func write(byte: UInt8, count: Int) throws {
    let chunk = Data(repeating: byte, count: 64 * 1024)
    var remaining = count
    while remaining > 0 {
      try input.fileHandleForWriting.write(contentsOf: chunk.prefix(min(chunk.count, remaining)))
      remaining -= min(chunk.count, remaining)
    }
  }

  func response(id: Int, timeout: TimeInterval) throws -> [String: Any] {
    let deadline = Date().addingTimeInterval(timeout)
    while deadline.timeIntervalSinceNow > 0 {
      let line = try readLine(timeout: deadline.timeIntervalSinceNow)
      guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        throw MCPProcessHarnessError.invalidResponse
      }
      if object["id"] as? Int == id { return object }
    }
    throw MCPProcessHarnessError.timedOut
  }

  func residentKiB() throws -> Int {
    let probe = Process()
    let output = Pipe()
    probe.executableURL = URL(fileURLWithPath: "/bin/ps")
    probe.arguments = ["-o", "rss=", "-p", String(process.processIdentifier)]
    probe.standardOutput = output
    try probe.run()
    probe.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard probe.terminationStatus == 0,
          let text = String(data: data, encoding: .utf8),
          let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      throw MCPProcessHarnessError.invalidResponse
    }
    return value
  }

  func stop() {
    guard process.isRunning else { return }
    process.terminate()
    process.waitUntilExit()
  }

  private func readLine(timeout: TimeInterval) throws -> Data {
    let deadline = Date().addingTimeInterval(timeout)
    let descriptor = output.fileHandleForReading.fileDescriptor

    while true {
      if let delimiter = bufferedOutput.firstIndex(of: 0x0A) {
        let line = Data(bufferedOutput[..<delimiter])
        bufferedOutput.removeSubrange(bufferedOutput.startIndex...delimiter)
        return line
      }

      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else { throw MCPProcessHarnessError.timedOut }
      var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      let milliseconds = Int32(min(remaining * 1_000, Double(Int32.max)))
      let pollResult = poll(&pollDescriptor, 1, max(milliseconds, 1))
      if pollResult == 0 { throw MCPProcessHarnessError.timedOut }
      if pollResult < 0 {
        if errno == EINTR { continue }
        throw MCPProcessHarnessError.readFailed(errno)
      }

      var bytes = [UInt8](repeating: 0, count: 4 * 1024)
      let count = bytes.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      guard count > 0 else { throw MCPProcessHarnessError.readFailed(errno) }
      bufferedOutput.append(contentsOf: bytes.prefix(count))
    }
  }
}

final class MCPServerProcessTests: XCTestCase {
  func testR14_01InitializeRespondsWithinOneSecondWhileStdinRemainsOpen() throws {
    let helper = try MCPProcessHarness()
    defer { helper.stop() }

    try helper.write(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"# + "\n")
    let response = try helper.response(id: 1, timeout: 1)

    XCTAssertNotNil(response["result"])
    XCTAssertTrue(helper.isRunning, "the response must not depend on stdin reaching EOF")
  }
}
