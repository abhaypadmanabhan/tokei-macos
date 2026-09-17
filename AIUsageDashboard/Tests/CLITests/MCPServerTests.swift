import XCTest
@testable import AIUsageDashboardCore

/// Protocol-level coverage for `tokei mcp` (issue #59).
///
/// This is the surface every external coding agent reads quota through, and a protocol
/// regression has already shipped once through it — an untested serializer sitting in
/// front of the just-fixed trust rule in `f725bac`. These tests assert the JSON-RPC
/// *wire shape*: the framing, the envelope, the handshake, the tool contract, and the
/// error objects. Anything an MCP client would reject must fail here first.
final class MCPServerTests: XCTestCase {

  // MARK: - Framing

  /// Newline-delimited JSON: exactly one frame per request, terminated by exactly one
  /// `\n`, with no stray bytes. Get this wrong and every client hangs.
  func testEachResponseIsOneNewlineTerminatedFrame() throws {
    let (server, capture) = try makeProtocolServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)

    XCTAssertEqual(capture.raw.last, 0x0A, "frame must end with the delimiter")
    XCTAssertEqual(capture.raw.filter { $0 == 0x0A }.count, 1, "exactly one delimiter per frame")
    XCTAssertEqual(capture.lines.count, 1)
  }

  /// The read loop: blank lines are skipped, and each message produces its own frame in
  /// order. This covers the stdio transport, not just the dispatcher.
  func testRunLoopSkipsBlankLinesAndFramesEachMessage() throws {
    let (server, capture) = try makeProtocolServer()
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

  func testS03SixteenMiBUnterminatedFrameStopsAccumulatingAtOneMiB() {
    let exactLimitFrame = Data(repeating: 0x58, count: MCPFrameReader.maximumFrameBytes)
    var exactLimitInput = exactLimitFrame
    exactLimitInput.append(0x0A)
    var exactLimitOffset = 0
    var exactLimitReader = MCPFrameReader { requestedBytes in
      guard exactLimitOffset < exactLimitInput.count else { return nil }
      let end = min(exactLimitOffset + requestedBytes, exactLimitInput.count)
      defer { exactLimitOffset = end }
      return exactLimitInput.subdata(in: exactLimitOffset..<end)
    }
    XCTAssertEqual(exactLimitReader.nextFrame(), .data(exactLimitFrame))

    let fixture = Data(repeating: 0x58, count: 16 * 1024 * 1024)
    var offset = 0
    var reader = MCPFrameReader { requestedBytes in
      guard offset < fixture.count else { return nil }
      let end = min(offset + requestedBytes, fixture.count)
      defer { offset = end }
      return fixture.subdata(in: offset..<end)
    }

    XCTAssertEqual(reader.nextFrame(), .oversized)
    while reader.nextFrame() != nil {}

    XCTAssertEqual(offset, fixture.count)
    XCTAssertLessThanOrEqual(
      reader.peakBufferedByteCount,
      MCPFrameReader.maximumFrameBytes + 1
    )
  }

  func testS03OversizedFrameAndIDReturnFixedErrorThenContinue() throws {
    let (server, capture) = try makeProtocolServer()
    let oversizedID = String(repeating: "i", count: MCPFrameReader.maximumFrameBytes)
    let input = Data(
      "{\"jsonrpc\":\"2.0\",\"id\":\"\(oversizedID)\",\"method\":\"ping\"}\n"
        .appending(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        .utf8
    )
    var offset = 0
    var reader = MCPFrameReader { requestedBytes in
      guard offset < input.count else { return nil }
      let end = min(offset + requestedBytes, input.count)
      defer { offset = end }
      return input.subdata(in: offset..<end)
    }

    server.run(frameReader: &reader)

    XCTAssertEqual(capture.lines.count, 2)
    let oversizedResponse = try capture.object(at: 0)
    let error = try rpcError(oversizedResponse, code: -32600)
    XCTAssertEqual(error["message"] as? String, MCPServer.oversizedFrameMessage)
    XCTAssertTrue(oversizedResponse["id"] is NSNull, "oversized ids are never reflected")
    XCTAssertEqual(try capture.object(at: 1)["id"] as? Int, 7)
  }

  func testResponseEnvelopeCarriesJSONRPCVersionAndEchoesID() throws {
    let (server, capture) = try makeProtocolServer()

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
    let (server, capture) = try makeProtocolServer()

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
    let (server, capture) = try makeProtocolServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
    XCTAssertNotNil(capabilities["tools"], "a client only lists tools if this key exists")

    let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
    XCTAssertEqual(serverInfo["name"] as? String, "tokei")
    XCTAssertEqual(serverInfo["version"] as? String, mcpTestVersion, "version is injected, not hardcoded")
  }

  /// `instructions` is surfaced to the model once at connect time; it is what makes an
  /// agent call the tools unprompted. Losing it is a silent behavioural regression.
  func testInitializeCarriesInstructionsWithTheTrustRules() throws {
    let (server, capture) = try makeProtocolServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let instructions = try XCTUnwrap(result["instructions"] as? String)
    XCTAssertFalse(instructions.isEmpty)
    // The f725bac trust rules must reach the agent, not just the routing engine.
    XCTAssertTrue(instructions.contains("local_estimate"))
    XCTAssertTrue(instructions.contains("85%"))
    XCTAssertTrue(instructions.contains("accountID"), "stable account identity must be documented")
    XCTAssertTrue(instructions.contains("selector.env"), "structured account targeting must be documented")
    XCTAssertTrue(instructions.contains("process API"), "selection must name the safe execution boundary")
    XCTAssertFalse(instructions.contains("export CLAUDE_CONFIG_DIR"))
  }

  // MARK: - tools/list

  func testToolsListAdvertisesExactlyTheTwoTools() throws {
    let (server, capture) = try makeProtocolServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
    XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["get_usage", "get_route_recommendation"])
  }

  /// Every tool needs a non-empty description and a valid JSON Schema, or clients drop
  /// it from the model's tool list without saying why.
  func testEachToolHasADescriptionAndAClosedObjectInputSchema() throws {
    let (server, capture) = try makeProtocolServer()

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
    let (server, capture) = try makeProtocolServer()

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
    let (server, capture) = try makeProtocolServer()

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

  // MARK: - tools/call · staleness

  /// Never serve stale data silently. The warning has to be in the text the model reads,
  /// not only in a flag it might ignore.
  func testStaleSnapshotKeepsJSONFirstAndAddsAWarningOnBothTools() throws {
    for tool in ["get_usage", "get_route_recommendation"] {
      let (server, capture) = try makeProtocolServer(secondsAfterGeneration: 7200)

      server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"\#(tool)"}}"#)

      let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
      let (text, isError) = try toolCallText(result)
      XCTAssertFalse(isError, "\(tool): a stale read still succeeds")
      XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(text.utf8)))
      let content = try XCTUnwrap(result["content"] as? [[String: Any]])
      XCTAssertEqual(content.count, 2, "\(tool): structured JSON first, warning second")
      let warning = try XCTUnwrap(content[1]["text"] as? String)
      XCTAssertTrue(warning.hasPrefix("⚠︎ Tokei data is stale"), "\(tool): missing stale warning")
      XCTAssertTrue(warning.contains("2h old"), "\(tool): the warning must state the age")
    }
  }

  func testFreshSnapshotHasNoStaleWarning() throws {
    let (server, capture) = try makeProtocolServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage"}}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let text = try toolCallText(result).text
    XCTAssertFalse(text.hasPrefix("⚠︎"), "no warning banner on a fresh read")
    XCTAssertFalse(text.contains("Tokei data is stale"))
    // The payload itself still carries the flag — that is the structured half.
    XCTAssertTrue(text.contains("\"stale\" : false"))
  }

}
