import Foundation
import XCTest
@testable import AIUsageDashboardCore

let mcpTestVersion = "9.9.9"

func rpcError(
  _ response: [String: Any],
  code: Int,
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> [String: Any] {
  XCTAssertNil(
    response["result"],
    "a JSON-RPC message carries result XOR error",
    file: file,
    line: line
  )
  let error = try XCTUnwrap(response["error"] as? [String: Any], file: file, line: line)
  XCTAssertEqual(error["code"] as? Int, code, file: file, line: line)
  return error
}

struct AccountAwareCLIFixture {
  let directory: URL
  let snapshotURL: URL
  let selectorDirectory: URL
  let validUntil: Date
}

/// Shared scaffolding for the `tokei` CLI / MCP tests (issue #59).
///
/// The CLI's only real input is a file on disk, so every test here writes a fixture to a
/// unique temp path and points a `SnapshotReader` at it with an injected clock. Nothing
/// touches `~/Library/Application Support`, and nothing depends on the wall clock.
enum CLITestSupport {
  static func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("tokei-cli-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /// Writes `json` to a fresh temp file and returns its URL. Caller owns cleanup via
  /// `XCTestCase.trackForCleanup(_:)`.
  static func writeSnapshot(_ json: String) throws -> URL {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("agent-snapshot.json")
    try Data(json.utf8).write(to: url)
    return url
  }

  static func writeSnapshot(_ snapshot: AgentSnapshot, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("agent-snapshot.json")
    try AgentSnapshot.makeEncoder().encode(snapshot).write(to: url)
    return url
  }

  static func accountAwareFixture(validFor seconds: TimeInterval) throws -> AccountAwareCLIFixture {
    let directory = try temporaryDirectory()
    let selectorDirectory = directory.appendingPathComponent("profile with spaces 'quotes' $(literal)")
    try FileManager.default.createDirectory(at: selectorDirectory, withIntermediateDirectories: true)
    let validUntil = AgentSnapshotFixtures.generatedAt.addingTimeInterval(seconds)
    let snapshot = accountAwareSnapshot(selectorDirectory: selectorDirectory, validUntil: validUntil)
    return AccountAwareCLIFixture(
      directory: directory,
      snapshotURL: try writeSnapshot(snapshot, in: directory),
      selectorDirectory: selectorDirectory,
      validUntil: validUntil
    )
  }

  private static func accountAwareSnapshot(
    selectorDirectory: URL,
    validUntil: Date
  ) -> AgentSnapshot {
    let target = AgentRecommendationTarget(
      provider: "codex",
      accountID: "codex:fixture-account",
      selector: AccountSelector(env: ["CODEX_HOME": selectorDirectory.path])
    )
    let account = AgentAccount(
      id: selectorDirectory.path,
      label: "default",
      windows: [],
      tokensToday: 0,
      accountID: "codex:fixture-account",
      selector: target.selector,
      quota: AgentAccountQuota(
        status: "eligible",
        usedPercent: 20,
        headroomPercent: 80,
        bindingWindowIndex: 0,
        validUntil: validUntil
      )
    )
    let provider = AgentProvider(
      id: "codex",
      displayName: "OpenAI Codex",
      windows: [],
      tokensToday: 0,
      lastUpdated: AgentSnapshotFixtures.generatedAt,
      accounts: [account],
      headlineAccountID: account.accountID
    )
    return AgentSnapshot(
      generatedAt: AgentSnapshotFixtures.generatedAt,
      providers: [provider],
      aggregateUtilizationPercent: 20,
      recommendation: AgentRecommendation(
        routeTo: "codex",
        avoid: [],
        reason: "fresh fixture",
        target: target,
        avoidAccounts: [],
        validUntil: validUntil
      )
    )
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

  func makeProtocolServer(
    json: String = AgentSnapshotFixtures.full,
    secondsAfterGeneration: TimeInterval = 60
  ) throws -> (MCPServer, FrameCapture) {
    let url = try CLITestSupport.writeSnapshot(json)
    trackForCleanup(url)
    return try makeProtocolServer(fileURL: url, secondsAfterGeneration: secondsAfterGeneration)
  }

  func makeProtocolServer(
    fileURL: URL,
    secondsAfterGeneration: TimeInterval = 60
  ) throws -> (MCPServer, FrameCapture) {
    let capture = FrameCapture()
    let reader = SnapshotReader(fileURL: fileURL, now: snapshotClock(plus: secondsAfterGeneration))
    return (MCPServer(reader: reader, version: mcpTestVersion, output: capture.write), capture)
  }

  func toolCallText(
    _ result: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> (text: String, isError: Bool) {
    let content = try XCTUnwrap(result["content"] as? [[String: Any]], file: file, line: line)
    XCTAssertFalse(content.isEmpty, "at least one text block per call", file: file, line: line)
    XCTAssertEqual(content[0]["type"] as? String, "text", file: file, line: line)
    return (
      try XCTUnwrap(content[0]["text"] as? String, file: file, line: line),
      try XCTUnwrap(result["isError"] as? Bool, file: file, line: line)
    )
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
