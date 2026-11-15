import XCTest
@testable import AIUsageDashboardCore

final class RouteMCPTests: XCTestCase {
    func testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter() throws {
        let now = AgentSnapshotFixtures.generatedAt
        let windows = [QuotaWindow(providerID: .codex, type: .fiveHour, used: 40, limit: 100,
                                   resetAt: now.addingTimeInterval(600), confidence: .providerReported,
                                   source: "fixture", observedAt: now)]
        let provider = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                        quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable)
        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
        let directory = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try CLITestSupport.writeSnapshot(snapshot, in: directory)
        for version in MCPServer.supportedVersions {
            let capture = FrameCapture()
            let server = MCPServer(reader: SnapshotReader(fileURL: url, now: { now }), version: mcpTestVersion, output: capture.write)
            server.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"\(version)\"}}")
            let initialization = try XCTUnwrap(try capture.object(at: 0)["result"] as? [String: Any])
            XCTAssertEqual(initialization["protocolVersion"] as? String, version)
            XCTAssertLessThan(try XCTUnwrap(initialization["instructions"] as? String).count, 400)
            let tool = try XCTUnwrap(server.toolDefinitions().first { $0["name"] as? String == "get_route" })
            XCTAssertEqual((tool["annotations"] as? [String: Bool])?["readOnlyHint"], true)
            XCTAssertEqual(tool["outputSchema"] != nil, version == MCPServer.protocolVersion)
            for (index, agent) in ["codex", "gemini"].enumerated() {
                server.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":\(index + 2),\"method\":\"tools/call\",\"params\":{\"name\":\"get_route\",\"arguments\":{\"for\":\"\(agent)\"}}}")
                let result = try XCTUnwrap(try capture.object(at: index + 1)["result"] as? [String: Any])
                let content = try toolCallText(result)
                XCTAssertFalse(content.isError)
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.text.utf8)) as? [String: Any])
                XCTAssertEqual(payload["status"] as? String, agent == "codex" ? "ready" : "unavailable")
                XCTAssertEqual(result["structuredContent"] != nil, version == MCPServer.protocolVersion)
            }
            server.handle(line: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_route","arguments":{"for":12}}}"#)
            _ = try rpcError(try capture.object(at: 3), code: -32602)
            server.handle(line: #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_route","arguments":{"unexpected":true}}}"#)
            _ = try rpcError(try capture.object(at: 4), code: -32602)
        }
    }
}
