import XCTest
@testable import AIUsageDashboardCore

final class RouteMCPTests: XCTestCase {
    func testS1AndS3BothToolsReturnTheSameTargetAndModelLimit() throws {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        func window(_ provider: ProviderID, _ type: QuotaWindowType, _ used: Double, reset: TimeInterval) -> QuotaWindow {
            QuotaWindow(providerID: provider, type: type, used: used, limit: 100,
                         resetAt: now.addingTimeInterval(reset), confidence: .providerReported,
                         source: "fixture", label: type == .perModel ? "Opus" : nil, observedAt: now)
        }
        func provider(_ id: ProviderID, _ windows: [QuotaWindow]) -> ProviderSnapshot {
            ProviderSnapshot(providerID: id, displayName: id.rawValue, authStatus: .authenticated,
                             quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable)
        }
        let cases: [([ProviderSnapshot], String, [String])] = [
            ([provider(.cursor, [window(.cursor, .monthly, 80, reset: 20 * 86_400)]),
              provider(.claudeCode, [window(.claudeCode, .weekly, 0, reset: 7 * 86_400 - 3_600)])], "claude_code", []),
            ([provider(.claudeCode, [window(.claudeCode, .weekly, 10, reset: 172_800),
                                     window(.claudeCode, .perModel, 95, reset: 172_800)]),
              provider(.codex, [window(.codex, .weekly, 50, reset: 172_800)])], "codex", ["claude_code"])
        ]
        for (providers, target, avoided) in cases {
            let directory = try CLITestSupport.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let snapshot = AgentSnapshotWriter.buildSnapshot(from: providers, generatedAt: now)
            let url = try CLITestSupport.writeSnapshot(snapshot, in: directory)
            let helper = try MCPProcessHarness(snapshotURL: url)
            defer { helper.stop() }
            var payloads: [[String: Any]] = []
            for (index, tool) in ["get_route", "get_route_recommendation"].enumerated() {
                try helper.write("{\"jsonrpc\":\"2.0\",\"id\":\(index),\"method\":\"tools/call\",\"params\":{\"name\":\"\(tool)\"}}\n")
                let response = try helper.response(id: index, timeout: 2)
                XCTAssertEqual(response["id"] as? Int, index)
                let result = try XCTUnwrap(response["result"] as? [String: Any])
                let text = try toolCallText(result)
                XCTAssertFalse(text.isError)
                payloads.append(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.text.utf8)) as? [String: Any]))
            }
            let rows = try XCTUnwrap(payloads[0]["rows"] as? [[String: Any]])
            XCTAssertEqual(rows.first?["provider"] as? String, target)
            XCTAssertEqual(payloads[1]["routeTo"] as? String, target)
            XCTAssertEqual(Set(rows.filter { $0["disposition"] as? String == "avoid" }.compactMap { $0["provider"] as? String }), Set(avoided))
            XCTAssertEqual(Set(payloads[1]["avoid"] as? [String] ?? []), Set(avoided))
            print("Route review real helper: target=\(target), avoid=\(avoided)")
            if !avoided.isEmpty {
                let model = try XCTUnwrap(rows.first { $0["provider"] as? String == "claude_code" })
                XCTAssertEqual(model["windowType"] as? String, "perModel")
                XCTAssertEqual(model["windowLabel"] as? String, "Opus")
                XCTAssertEqual(model["remainingPercent"] as? Double, 5)
            }
        }
    }

    func testMissingSnapshotExplainsAbsenceWithoutExposingItsPath() throws {
        let capture = FrameCapture()
        let server = MCPServer(reader: SnapshotReader(fileURL: CLITestSupport.missingSnapshotURL()),
                               version: mcpTestVersion, output: capture.write)
        server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_route"}}"#)
        let result = try XCTUnwrap(try capture.onlyObject()["result"] as? [String: Any])
        let content = try toolCallText(result)
        XCTAssertTrue(content.isError)
        XCTAssertEqual(content.text, "No usage snapshot is available. Launch Tokei and retry.")
        XCTAssertFalse(content.text.contains("/"))
    }

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
            let instructions = try XCTUnwrap(initialization["instructions"] as? String)
            XCTAssertTrue(instructions.hasPrefix(MCPInstructionsFixtures.legacy + "\n\n"))
            let addition = instructions.dropFirst(MCPInstructionsFixtures.legacy.count + 2)
            XCTAssertLessThan(addition.count, 400)
            XCTAssertTrue(addition.contains("get_route"))
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
                if agent == "gemini" {
                    XCTAssertEqual(payload["advice"] as? String, "Gemini has no flat-rate plan to route to.")
                }
                XCTAssertEqual(result["structuredContent"] != nil, version == MCPServer.protocolVersion)
            }
            server.handle(line: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_route","arguments":{"for":12}}}"#)
            _ = try rpcError(try capture.object(at: 3), code: -32602)
            server.handle(line: #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_route","arguments":{"unexpected":true}}}"#)
            _ = try rpcError(try capture.object(at: 4), code: -32602)
        }
    }
}
