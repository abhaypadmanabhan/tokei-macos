import XCTest
@testable import AIUsageDashboardCore

private func rpcError(
  _ response: [String: Any],
  code: Int,
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> [String: Any] {
  XCTAssertNil(response["result"], "a JSON-RPC message carries result XOR error", file: file, line: line)
  let error = try XCTUnwrap(response["error"] as? [String: Any], file: file, line: line)
  XCTAssertEqual(error["code"] as? Int, code, file: file, line: line)
  return error
}

/// Protocol-level coverage for `tokei mcp` (issue #59).
///
/// This is the surface every external coding agent reads quota through, and a protocol
/// regression has already shipped once through it — an untested serializer sitting in
/// front of the just-fixed trust rule in `f725bac`. These tests assert the JSON-RPC
/// *wire shape*: the framing, the envelope, the handshake, the tool contract, and the
/// error objects. Anything an MCP client would reject must fail here first.
final class MCPServerTests: XCTestCase {

  private let testVersion = "9.9.9"

  /// A server backed by `json` on disk, with the clock `seconds` after `generatedAt`.
  private func makeServer(
    json: String = AgentSnapshotFixtures.full,
    secondsAfterGeneration: TimeInterval = 60
  ) throws -> (MCPServer, FrameCapture) {
    let url = try CLITestSupport.writeSnapshot(json)
    trackForCleanup(url)
    return try makeServer(fileURL: url, secondsAfterGeneration: secondsAfterGeneration)
  }

  private func makeServer(
    fileURL: URL,
    secondsAfterGeneration: TimeInterval = 60
  ) throws -> (MCPServer, FrameCapture) {
    let capture = FrameCapture()
    let reader = SnapshotReader(fileURL: fileURL, now: snapshotClock(plus: secondsAfterGeneration))
    return (MCPServer(reader: reader, version: testVersion, output: capture.write), capture)
  }

  /// The `content[0].text` of a `tools/call` result, plus its `isError` flag.
  private func toolCallText(
    _ result: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> (text: String, isError: Bool) {
    let content = try XCTUnwrap(result["content"] as? [[String: Any]], file: file, line: line)
    XCTAssertEqual(content.count, 1, "one text block per call", file: file, line: line)
    XCTAssertEqual(content[0]["type"] as? String, "text", file: file, line: line)
    return (
      try XCTUnwrap(content[0]["text"] as? String, file: file, line: line),
      try XCTUnwrap(result["isError"] as? Bool, file: file, line: line)
    )
  }

  // MARK: - Framing

  /// Newline-delimited JSON: exactly one frame per request, terminated by exactly one
  /// `\n`, with no stray bytes. Get this wrong and every client hangs.
  func testEachResponseIsOneNewlineTerminatedFrame() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)

    XCTAssertEqual(capture.raw.last, 0x0A, "frame must end with the delimiter")
    XCTAssertEqual(capture.raw.filter { $0 == 0x0A }.count, 1, "exactly one delimiter per frame")
    XCTAssertEqual(capture.lines.count, 1)
  }

  /// The read loop: blank lines are skipped, and each message produces its own frame in
  /// order. This covers the stdio transport, not just the dispatcher.
  func testRunLoopSkipsBlankLinesAndFramesEachMessage() throws {
    let (server, capture) = try makeServer()
    var inbox = [
      #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#,
      "",
      "   ",
      #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
      #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
    ]

    server.run(nextLine: { inbox.isEmpty ? nil : inbox.removeFirst() })

    XCTAssertEqual(capture.lines.count, 2, "2 requests + 1 notification + blanks = 2 replies")
    XCTAssertEqual(try capture.object(at: 0)["id"] as? Int, 1)
    XCTAssertEqual(try capture.object(at: 1)["id"] as? Int, 2)
  }

  func testResponseEnvelopeCarriesJSONRPCVersionAndEchoesID() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":"abc-123","method":"ping"}"#)

    let response = try capture.onlyObject()
    XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
    XCTAssertEqual(response["id"] as? String, "abc-123", "string ids must round-trip unchanged")
    XCTAssertNotNil(response["result"])
    XCTAssertNil(response["error"])
  }

  // MARK: - initialize

  /// THE regression guard for issue #59. The server must answer with the protocol
  /// revision it actually implements, never the one the client asked for and never an
  /// error. Claude Code 2.1.x requests `2025-11-25`; erroring on that is what made
  /// `claude mcp add tokei` register and then never connect. Echoing the client's value
  /// back is the opposite bug — claiming support we do not have.
  func testInitializeAnswersWithOurProtocolVersionNotTheClientsRequest() throws {
    let (server, capture) = try makeServer()

    server.handle(line: """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25",\
      "capabilities":{},"clientInfo":{"name":"claude-code","version":"2.1.0"}}}
      """)

    let response = try capture.onlyObject()
    XCTAssertNil(response["error"], "a newer client revision must never be an error")
    let result = try XCTUnwrap(response["result"] as? [String: Any])
    XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.protocolVersion)
    XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
    XCTAssertNotEqual(result["protocolVersion"] as? String, "2025-11-25")
  }

  func testInitializeAdvertisesToolsCapabilityAndServerInfo() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
    XCTAssertNotNil(capabilities["tools"], "a client only lists tools if this key exists")

    let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
    XCTAssertEqual(serverInfo["name"] as? String, "tokei")
    XCTAssertEqual(serverInfo["version"] as? String, testVersion, "version is injected, not hardcoded")
  }

  /// `instructions` is surfaced to the model once at connect time; it is what makes an
  /// agent call the tools unprompted. Losing it is a silent behavioural regression.
  func testInitializeCarriesInstructionsWithTheTrustRules() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let instructions = try XCTUnwrap(result["instructions"] as? String)
    XCTAssertFalse(instructions.isEmpty)
    // The f725bac trust rules must reach the agent, not just the routing engine.
    XCTAssertTrue(instructions.contains("local_estimate"))
    XCTAssertTrue(instructions.contains("85%"))
    XCTAssertTrue(instructions.contains("CLAUDE_CONFIG_DIR"), "multi-account targeting must be documented")
  }

  // MARK: - tools/list

  func testToolsListAdvertisesExactlyTheTwoTools() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
    XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["get_usage", "get_route_recommendation"])
  }

  /// Every tool needs a non-empty description and a valid JSON Schema, or clients drop
  /// it from the model's tool list without saying why.
  func testEachToolHasADescriptionAndAClosedObjectInputSchema() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
    for tool in tools {
      let name = try XCTUnwrap(tool["name"] as? String)
      let description = try XCTUnwrap(tool["description"] as? String, "\(name) has no description")
      XCTAssertFalse(description.isEmpty)
      let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any], "\(name) has no inputSchema")
      XCTAssertEqual(schema["type"] as? String, "object")
      XCTAssertNotNil(schema["properties"])
      XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }
  }

  // MARK: - tools/call · get_usage

  func testGetUsageReturnsTheDecodableSnapshot() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_usage","arguments":{}}}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let (text, isError) = try toolCallText(result)
    XCTAssertFalse(isError)

    // The payload must round-trip through the frozen schema, not merely look like JSON.
    let snapshot = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: Data(text.utf8))
    XCTAssertEqual(snapshot.schemaVersion, 1)
    XCTAssertEqual(snapshot.providers.map(\.id), ["claude_code", "codex", "cursor", "antigravity"])
    XCTAssertEqual(snapshot.stale, false)
    XCTAssertEqual(snapshot.ageSeconds, 60, "reader-side freshness must be served, not stripped")
    XCTAssertEqual(snapshot.providers.first?.accounts?.count, 2)
  }

  // MARK: - tools/call · get_route_recommendation

  func testGetRouteRecommendationReturnsOnlyTheRecommendation() throws {
    let (server, capture) = try makeServer()

    server.handle(line: """
      {"jsonrpc":"2.0","id":3,"method":"tools/call",\
      "params":{"name":"get_route_recommendation","arguments":{}}}
      """)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let (text, isError) = try toolCallText(result)
    XCTAssertFalse(isError)

    let recommendation = try AgentSnapshot.makeDecoder()
      .decode(AgentRecommendation.self, from: Data(text.utf8))
    XCTAssertEqual(recommendation.routeTo, "claude_code")
    XCTAssertEqual(recommendation.avoid, ["codex"])
    XCTAssertFalse(recommendation.reason.isEmpty)
    XCTAssertFalse(text.contains("\"providers\""), "this tool is the cheap one — no full snapshot")
  }

  /// No recommendation is a first-class answer, not an error: refusing to route is
  /// exactly what `f725bac` made the engine do when nothing is trustworthy.
  func testGetRouteRecommendationExplainsAbsenceWithoutErroring() throws {
    let (server, capture) = try makeServer(json: AgentSnapshotFixtures.minimal)

    server.handle(line: """
      {"jsonrpc":"2.0","id":3,"method":"tools/call",\
      "params":{"name":"get_route_recommendation"}}
      """)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let (text, isError) = try toolCallText(result)
    XCTAssertFalse(isError, "\"nothing to recommend\" is a valid answer, not a failure")
    XCTAssertTrue(text.contains("No routing recommendation available"))
  }

  // MARK: - tools/call · staleness

  /// Never serve stale data silently. The warning has to be in the text the model reads,
  /// not only in a flag it might ignore.
  func testStaleSnapshotPrefixesAWarningOnBothTools() throws {
    for tool in ["get_usage", "get_route_recommendation"] {
      let (server, capture) = try makeServer(secondsAfterGeneration: 7200)

      server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"\#(tool)"}}"#)

      let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
      let (text, isError) = try toolCallText(result)
      XCTAssertFalse(isError, "\(tool): a stale read still succeeds")
      XCTAssertTrue(text.hasPrefix("⚠︎ Tokei data is stale"), "\(tool): missing stale warning")
      XCTAssertTrue(text.contains("2h old"), "\(tool): the warning must state the age")
    }
  }

  func testFreshSnapshotHasNoStaleWarning() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage"}}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let text = try toolCallText(result).text
    XCTAssertFalse(text.hasPrefix("⚠︎"), "no warning banner on a fresh read")
    XCTAssertFalse(text.contains("Tokei data is stale"))
    // The payload itself still carries the flag — that is the structured half.
    XCTAssertTrue(text.contains("\"stale\" : false"))
  }

  // MARK: - tools/call · errors

  /// A tool failure is `isError: true` inside a *successful* JSON-RPC result — an MCP
  /// client shows it to the model. Returning a JSON-RPC error object instead would
  /// surface as a transport fault and hide the actionable message.
  func testMissingSnapshotIsAToolErrorNotAProtocolError() throws {
    for tool in ["get_usage", "get_route_recommendation"] {
      let (server, capture) = try makeServer(fileURL: CLITestSupport.missingSnapshotURL())

      server.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"\(tool)\"}}")

      let response = try capture.onlyObject()
      XCTAssertNil(response["error"], "\(tool): must not be a protocol-level error")
      let result = try XCTUnwrap(response["result"] as? [String: Any])
      let (text, isError) = try toolCallText(result)
      XCTAssertTrue(isError, tool)
      XCTAssertTrue(text.contains("no usage snapshot found"), tool)
      XCTAssertTrue(text.contains("Launch Tokei"), tool)
    }
  }

  func testMalformedSnapshotIsReportedAsAToolError() throws {
    for tool in ["get_usage", "get_route_recommendation"] {
      let (server, capture) = try makeServer(json: AgentSnapshotFixtures.malformedJSON)

      server.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"\(tool)\"}}")

      let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
      let (text, isError) = try toolCallText(result)
      XCTAssertTrue(isError, tool)
      XCTAssertTrue(text.contains("not valid JSON"), tool)
    }
  }

  // A8 corrected the old test that blessed an MCP execution error. An unknown tool
  // is invalid tools/call parameters and must be rejected before any snapshot read.
  func testA8UnknownToolWithMissingSnapshotIsInvalidParamsBeforeFileRead() throws {
    let (server, capture) = try makeServer(fileURL: CLITestSupport.missingSnapshotURL())

    server.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"drop_database"}}"#)

    let response = try capture.onlyObject()
    let error = try rpcError(response, code: -32602)
    XCTAssertTrue((error["message"] as? String)?.contains("Unknown tool: drop_database") == true)
  }

  // A8 corrected the old test that blessed an MCP execution error. A missing tool
  // name is invalid call parameters, not a failure of a valid tool execution.
  func testA8ToolsCallWithoutANameReturnsInvalidParams() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"arguments":{}}}"#)

    let error = try rpcError(try capture.onlyObject(), code: -32602)
    XCTAssertTrue((error["message"] as? String)?.contains("Missing tool name") == true)
  }

  func testA8ToolsCallRejectsExtraOrMalformedArguments() throws {
    let invalidRequests = [
      #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"get_usage","arguments":{"unadvertised":1}}}"#,
      #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"get_usage","arguments":"not-object"}}"#
    ]

    for request in invalidRequests {
      let (server, capture) = try makeServer()
      server.handle(line: request)

      _ = try rpcError(capture.onlyObject(), code: -32602)
    }
  }

  func testA8ToolsCallRejectsMissingOrMalformedParams() throws {
    let invalidRequests = [
      #"{"jsonrpc":"2.0","id":14,"method":"tools/call"}"#,
      #"{"jsonrpc":"2.0","id":15,"method":"tools/call","params":[]}"#
    ]

    for request in invalidRequests {
      let (server, capture) = try makeServer()
      server.handle(line: request)

      _ = try rpcError(capture.onlyObject(), code: -32602)
    }
  }

  // MARK: - JSON-RPC error objects

  func testUnknownMethodReturnsMethodNotFound() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":42,"method":"resources/list"}"#)

    let response = try capture.onlyObject()
    XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
    XCTAssertEqual(response["id"] as? Int, 42, "an error must still echo the request id")
    XCTAssertNil(response["result"], "a JSON-RPC message carries result XOR error")
    let error = try XCTUnwrap(response["error"] as? [String: Any])
    XCTAssertEqual(error["code"] as? Int, -32601)
    let message = try XCTUnwrap(error["message"] as? String)
    XCTAssertTrue(message.contains("resources/list"), "name the method so the client can debug it")
  }

}
