import XCTest
@testable import AIUsageDashboardCore

/// A7 transport/envelope exchanges reproduced from the read-only protocol audit.
final class MCPServerExchangeMatrixTests: XCTestCase {

  private func makeServer() throws -> (MCPServer, FrameCapture) {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let capture = FrameCapture()
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 60))
    return (MCPServer(reader: reader, version: "9.9.9", output: capture.write), capture)
  }

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

  func testA7MalformedJSONReturnsParseErrorWithNullID() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"#)

    let response = try capture.onlyObject()
    let error = try XCTUnwrap(response["error"] as? [String: Any])
    XCTAssertEqual(error["code"] as? Int, -32700)
    XCTAssertEqual(error["message"] as? String, "Parse error")
    XCTAssertTrue(response["id"] is NSNull, "id is unknowable on a parse error — must be null, not absent")
    XCTAssertNotNil(response["id"])
  }

  // A7 corrected the old test that called syntactically valid JSON a parse error.
  // Scalars and unsupported batches are invalid requests (-32600), never malformed JSON.
  func testA7ValidNonObjectJSONAndBatchesReturnInvalidRequest() throws {
    for request in ["1", "[]", #"[{"jsonrpc":"2.0","id":10,"method":"ping"}]"#] {
      let (server, capture) = try makeServer()
      server.handle(line: request)

      let response = try capture.onlyObject()
      _ = try rpcError(response, code: -32600)
      XCTAssertTrue(response["id"] is NSNull)
    }
  }

  func testA7InvalidEnvelopeMatrixReturnsInvalidRequest() throws {
    let requests = [
      #"{"jsonrpc":"1.0","id":8,"method":"ping"}"#,
      #"{"jsonrpc":"2.0","id":{"bad":1},"method":"ping"}"#,
      #"{"jsonrpc":"2.0","id":9}"#,
      "{}"
    ]

    for request in requests {
      let (server, capture) = try makeServer()
      server.handle(line: request)

      _ = try rpcError(capture.onlyObject(), code: -32600)
    }
  }

  func testA7NullIDIsAcceptedAndEchoed() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#)

    let response = try capture.onlyObject()
    XCTAssertTrue(response["id"] is NSNull)
    XCTAssertNotNil(response["result"])
  }

  func testA7NotificationsAreNeverAnswered() throws {
    let methods = ["notifications/initialized", "notifications/cancelled", "tools/list", "definitely/not/a/method"]
    for method in methods {
      let (server, capture) = try makeServer()
      let request = "{\"jsonrpc\":\"2.0\",\"method\":\"\(method)\"}"

      server.handle(line: request)

      XCTAssertTrue(capture.raw.isEmpty, "\(method) has no id, so it must produce no output")
    }
  }

  func testA7NotificationShapedMessageWithAnIDIsAnswered() throws {
    let (server, capture) = try makeServer()

    server.handle(line: #"{"jsonrpc":"2.0","id":14,"method":"notifications/initialized"}"#)

    let response = try capture.onlyObject()
    XCTAssertEqual(response["id"] as? Int, 14)
    XCTAssertNotNil(response["result"])
    XCTAssertNil(response["error"])
  }

  func testA7RunLoopHandlesCRLFNoFinalNewlineAndEOF() throws {
    let (server, capture) = try makeServer()
    var inbox: [String?] = [
      "\r",
      "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"ping\"}\r",
      #"{"jsonrpc":"2.0","id":17,"method":"ping"}"#,
      nil
    ]

    server.run(nextLine: { inbox.removeFirst() })

    XCTAssertEqual(capture.lines.count, 2)
    XCTAssertEqual(try capture.object(at: 0)["id"] as? Int, 16)
    XCTAssertEqual(try capture.object(at: 1)["id"] as? Int, 17)
  }

  func testA7EmptyEOFWritesNothing() throws {
    let (server, capture) = try makeServer()

    server.run(nextLine: { nil })

    XCTAssertTrue(capture.raw.isEmpty)
  }

  func testA7MalformedFrameDoesNotPoisonTheFollowingRequest() throws {
    let (server, capture) = try makeServer()
    var inbox = [
      #"{"#,
      #"{"jsonrpc":"2.0","id":18,"method":"ping"}"#
    ]

    server.run(nextLine: { inbox.isEmpty ? nil : inbox.removeFirst() })

    XCTAssertEqual(capture.lines.count, 2)
    _ = try rpcError(capture.object(at: 0), code: -32700)
    XCTAssertEqual(try capture.object(at: 1)["id"] as? Int, 18)
    XCTAssertNotNil(try capture.object(at: 1)["result"])
  }

  func testA7ContentLengthFramingIsExplicitlyRejectedWithoutPoisoningTheJSONLine() throws {
    let (server, capture) = try makeServer()
    var inbox = [
      "Content-Length: 46\r",
      "\r",
      #"{"jsonrpc":"2.0","id":19,"method":"ping"}"#
    ]

    server.run(nextLine: { inbox.isEmpty ? nil : inbox.removeFirst() })

    XCTAssertEqual(capture.lines.count, 2)
    _ = try rpcError(capture.object(at: 0), code: -32700)
    XCTAssertEqual(try capture.object(at: 1)["id"] as? Int, 19)
  }
}
