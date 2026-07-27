import Foundation
import XCTest

/// Shared scaffolding for the `tokei` CLI / MCP tests (issue #59).
///
/// The CLI's only real input is a file on disk, so every test here writes a fixture to a
/// unique temp path and points a `SnapshotReader` at it with an injected clock. Nothing
/// touches `~/Library/Application Support`, and nothing depends on the wall clock.
enum CLITestSupport {
  /// Writes `json` to a fresh temp file and returns its URL. Caller owns cleanup via
  /// `XCTestCase.trackForCleanup(_:)`.
  static func writeSnapshot(_ json: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("tokei-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("agent-snapshot.json")
    try Data(json.utf8).write(to: url)
    return url
  }

  /// A path that is guaranteed not to exist.
  static func missingSnapshotURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("tokei-cli-tests-missing-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("agent-snapshot.json")
  }
}

extension XCTestCase {
  /// Deletes `url`'s containing directory at teardown.
  func trackForCleanup(_ url: URL) {
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
  }

  /// `AgentSnapshotFixtures.generatedAt` offset by `seconds` — the injected "now".
  func snapshotClock(plus seconds: TimeInterval) -> () -> Date {
    let now = AgentSnapshotFixtures.generatedAt.addingTimeInterval(seconds)
    return { now }
  }
}

/// Captures the newline-delimited frames an `MCPServer` writes, so tests assert the
/// framing itself rather than re-deriving it.
final class FrameCapture {
  private(set) var raw = Data()

  var write: (Data) -> Void { { [self] data in raw.append(data) } }

  /// Every complete frame, with the trailing newline removed.
  var lines: [String] {
    guard let text = String(data: raw, encoding: .utf8) else { return [] }
    return text.split(separator: "\n", omittingEmptySubsequences: false)
      .dropLast() // a well-framed stream always ends with the delimiter
      .map(String.init)
  }

  /// The single frame written, decoded as JSON. Fails the test if there wasn't exactly one.
  func onlyObject(file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
    guard lines.count == 1 else {
      XCTFail("expected exactly 1 frame, got \(lines.count): \(lines)", file: file, line: line)
      return [:]
    }
    return try object(at: 0, file: file, line: line)
  }

  func object(at index: Int, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
    let text = lines[index]
    guard
      let data = text.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      XCTFail("frame \(index) is not a JSON object: \(text)", file: file, line: line)
      return [:]
    }
    return object
  }
}
