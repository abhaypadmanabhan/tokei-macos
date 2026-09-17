import XCTest
@testable import AIUsageDashboardCore

final class MCPServerErrorTests: XCTestCase {
  func testMissingSnapshotIsAToolErrorNotAProtocolError() throws {
    for tool in ["get_usage", "get_route_recommendation"] {
      let (server, capture) = try makeProtocolServer(fileURL: CLITestSupport.missingSnapshotURL())
      let request = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\","
        + "\"params\":{\"name\":\"\(tool)\"}}"
      server.handle(line: request)

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
      let (server, capture) = try makeProtocolServer(json: AgentSnapshotFixtures.malformedJSON)
      let request = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\","
        + "\"params\":{\"name\":\"\(tool)\"}}"
      server.handle(line: request)

      let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
      let (text, isError) = try toolCallText(result)
      XCTAssertTrue(isError, tool)
      XCTAssertTrue(text.contains("not valid JSON"), tool)
    }
  }

  func testA8UnknownToolWithMissingSnapshotIsInvalidParamsBeforeFileRead() throws {
    let (server, capture) = try makeProtocolServer(fileURL: CLITestSupport.missingSnapshotURL())
    let request = #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"drop_database"}}"#
    server.handle(line: request)

    let error = try rpcError(capture.onlyObject(), code: -32602)
    XCTAssertTrue((error["message"] as? String)?.contains("Unknown tool: drop_database") == true)
  }

  func testA8ToolsCallWithoutANameReturnsInvalidParams() throws {
    let (server, capture) = try makeProtocolServer()
    let request = #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"arguments":{}}}"#
    server.handle(line: request)

    let error = try rpcError(try capture.onlyObject(), code: -32602)
    XCTAssertTrue((error["message"] as? String)?.contains("Missing tool name") == true)
  }

  func testA8ToolsCallRejectsExtraOrMalformedArguments() throws {
    let suffix = #", "method":"tools/call","params":{"name":"get_usage","arguments":"#
    let invalidRequests = [
      #"{"jsonrpc":"2.0","id":12"# + suffix + #"{"unadvertised":1}}}"#,
      #"{"jsonrpc":"2.0","id":13"# + suffix + #""not-object"}}"#
    ]
    for request in invalidRequests {
      let (server, capture) = try makeProtocolServer()
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
      let (server, capture) = try makeProtocolServer()
      server.handle(line: request)
      _ = try rpcError(capture.onlyObject(), code: -32602)
    }
  }

  func testUnknownMethodReturnsMethodNotFound() throws {
    let (server, capture) = try makeProtocolServer()
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

  func testS03OneMiBUnknownNamesProduceBoundedErrors() throws {
    let longName = String(repeating: "x", count: 1024 * 1024)
    let requests = [
      (-32601, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"\(longName)\"}"),
      (
        -32602,
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\","
          + "\"params\":{\"name\":\"\(longName)\"}}"
      )
    ]
    for (code, request) in requests {
      let (server, capture) = try makeProtocolServer()
      server.handle(line: request)
      let error = try rpcError(capture.onlyObject(), code: code)
      let message = try XCTUnwrap(error["message"] as? String)
      XCTAssertLessThan(message.utf8.count, 256)
      XCTAssertTrue(message.hasSuffix(String(repeating: "x", count: 128)))
    }
  }

  func testR14_03CombiningMarksKeepDiagnosticsWithinByteCap() throws {
    let longName = "x" + String(repeating: "\u{0301}", count: 200_000)
    let requests = [
      (-32601, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"\(longName)\"}"),
      (
        -32602,
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\","
          + "\"params\":{\"name\":\"\(longName)\"}}"
      )
    ]
    for (code, request) in requests {
      let (server, capture) = try makeProtocolServer()
      server.handle(line: request)
      let error = try rpcError(capture.onlyObject(), code: code)
      let message = try XCTUnwrap(error["message"] as? String)
      XCTAssertLessThanOrEqual(message.utf8.count, 200)
    }
  }
}
