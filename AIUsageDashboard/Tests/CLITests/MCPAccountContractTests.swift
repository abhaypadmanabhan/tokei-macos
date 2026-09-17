import XCTest
@testable import AIUsageDashboardCore

final class MCPAccountContractTests: XCTestCase {
  private func makeServer(
    fileURL: URL,
    secondsAfterGeneration: TimeInterval = 60
  ) -> (MCPServer, FrameCapture) {
    let capture = FrameCapture()
    let reader = SnapshotReader(fileURL: fileURL, now: snapshotClock(plus: secondsAfterGeneration))
    return (MCPServer(reader: reader, version: "9.9.9", output: capture.write), capture)
  }

  private func routePayload(from result: [String: Any]) throws -> [String: Any] {
    let content = try XCTUnwrap(result["content"] as? [[String: Any]])
    let text = try XCTUnwrap(content.first?["text"] as? String)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }

  func testWP6ToolDescriptionsPublishTheAccountContract() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let (server, capture) = makeServer(fileURL: url)

    server.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
    XCTAssertEqual(tools.count, 2)
    for tool in tools {
      let description = try XCTUnwrap(tool["description"] as? String)
      for phrase in [
        "accountID", "provider-scoped", "stable across machines", "selector.env",
        "process API", "accounts[].id", "legacy locator", "feature-detect", "lossy proxy"
      ] {
        XCTAssertTrue(description.contains(phrase), "missing \(phrase)")
      }
      XCTAssertFalse(description.contains("export CLAUDE_CONFIG_DIR"))
    }
    let combined = tools.compactMap { $0["description"] as? String }.joined(separator: " ")
    for status in [
      "eligible", "expiredCredentials", "cooldown", "disabled",
      "requestFailed", "noQuotaSource", "unknown"
    ] {
      XCTAssertTrue(combined.contains(status), "missing quota.status code \(status)")
    }
  }

  func testWP6RouteRecommendationCarriesFreshnessAndLiteralSelector() throws {
    let fixture = try CLITestSupport.accountAwareFixture(validFor: 120)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let (server, capture) = makeServer(fileURL: fixture.snapshotURL)

    server.handle(line: """
      {"jsonrpc":"2.0","id":3,"method":"tools/call",\
      "params":{"name":"get_route_recommendation","arguments":{}}}
      """)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let recommendation = try routePayload(from: result)
    XCTAssertEqual(recommendation["routeTo"] as? String, "codex")
    XCTAssertEqual(recommendation["generatedAt"] as? String, "2026-07-27T12:00:00Z")
    XCTAssertEqual(recommendation["ageSeconds"] as? Int, 60)
    XCTAssertEqual(recommendation["stale"] as? Bool, false)
    XCTAssertEqual(recommendation["validUntil"] as? String, "2026-07-27T12:02:00Z")
    let target = try XCTUnwrap(recommendation["target"] as? [String: Any])
    let selector = try XCTUnwrap(target["selector"] as? [String: Any])
    let env = try XCTUnwrap(selector["env"] as? [String: String])
    XCTAssertEqual(env["CODEX_HOME"], fixture.selectorDirectory.path)
    let text = try XCTUnwrap(result["content"] as? [[String: Any]])[0]["text"] as? String
    XCTAssertTrue(text?.contains("$(literal)") == true)
    XCTAssertFalse(text?.contains("export ") == true)
    XCTAssertFalse(text?.contains("\"providers\"") == true)
  }

  /// No recommendation is a first-class answer, not an error: refusing to route is
  /// exactly what `f725bac` made the engine do when nothing is trustworthy.
  func testGetRouteRecommendationExplainsAbsenceWithoutErroring() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.minimal)
    trackForCleanup(url)
    let (server, capture) = makeServer(fileURL: url)

    server.handle(line: """
      {"jsonrpc":"2.0","id":3,"method":"tools/call",\
      "params":{"name":"get_route_recommendation"}}
      """)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    XCTAssertEqual(result["isError"] as? Bool, false)
    let payload = try routePayload(from: result)
    XCTAssertTrue((payload["reason"] as? String)?.contains("No routing recommendation available") == true)
    XCTAssertEqual(payload["generatedAt"] as? String, "2026-07-27T12:00:00Z")
    XCTAssertEqual(payload["ageSeconds"] as? Int, 60)
    XCTAssertEqual(payload["stale"] as? Bool, false)
    XCTAssertNil(payload["routeTo"])
  }

  func testA4ExpiredRecommendationRoutePayloadIsStaleAndNonExecutable() throws {
    let fixture = try CLITestSupport.accountAwareFixture(validFor: 120)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let (server, capture) = makeServer(fileURL: fixture.snapshotURL, secondsAfterGeneration: 121)

    server.handle(line: """
      {"jsonrpc":"2.0","id":4,"method":"tools/call",\
      "params":{"name":"get_route_recommendation","arguments":{}}}
      """)

    let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
    let payload = try routePayload(from: result)
    XCTAssertEqual(payload["stale"] as? Bool, true)
    XCTAssertEqual(payload["ageSeconds"] as? Int, 121)
    XCTAssertEqual(payload["validUntil"] as? String, "2026-07-27T12:02:00Z")
    XCTAssertNil(payload["routeTo"])
    XCTAssertNil(payload["target"])
    XCTAssertTrue((payload["reason"] as? String)?.contains("recommendation expired") == true)
  }
}
