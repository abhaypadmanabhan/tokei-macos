import XCTest
@testable import AIUsageDashboardCore

final class WP4MCPTests: XCTestCase {
    func testCLIProviderIDsMatchCoreContract() {
        XCTAssertEqual(SnapshotReader.providerIDs, Set(ProviderID.allCases.map(\.rawValue)))
    }

    func testNegotiationAnnotationsAndStructuredResultsByVersion() throws {
        for requested in ["2024-11-05", "2025-03-26", "2025-06-18", "2099-01-01"] {
            let (server, capture) = try makeProtocolServer()
            server.handle(line: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\(requested)"}}
            """)
            server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
            server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_usage"}}"#)
            let modern = requested == "2025-06-18" || requested == "2099-01-01"
            let initialize = try XCTUnwrap(capture.object(at: 0)["result"] as? [String: Any])
            XCTAssertEqual(initialize["protocolVersion"] as? String,
                           requested == "2099-01-01" ? "2025-06-18" : requested)
            let listing = try XCTUnwrap(capture.object(at: 1)["result"] as? [String: Any])
            let tools = try XCTUnwrap(listing["tools"] as? [[String: Any]])
            for tool in tools {
                XCTAssertFalse((tool["title"] as? String ?? "").isEmpty)
                let annotations = try XCTUnwrap(tool["annotations"] as? [String: Bool])
                XCTAssertEqual(annotations, ["readOnlyHint": true, "idempotentHint": true, "openWorldHint": false])
                XCTAssertEqual(tool["outputSchema"] != nil, modern)
            }
            let result = try XCTUnwrap(capture.object(at: 2)["result"] as? [String: Any])
            let content = try toolCallText(result)
            XCTAssertFalse(content.text.contains("\n"))
            XCTAssertEqual(result["structuredContent"] != nil, modern)
            if modern {
                let structured = try XCTUnwrap(result["structuredContent"] as? NSDictionary)
                let text = try JSONSerialization.jsonObject(with: Data(content.text.utf8)) as? NSDictionary
                XCTAssertEqual(structured, text)
            }
        }
    }

    func testUsageFilterAcceptsKnownProviderAndRejectsUnknown() throws {
        let (server, capture) = try makeProtocolServer()
        server.handle(line: """
        {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"codex"}}}
        """)
        let result = try XCTUnwrap(capture.object(at: 0)["result"] as? [String: Any])
        let text = try toolCallText(result).text
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.compactMap { $0["id"] as? String }, ["codex"])
        server.handle(line: """
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"unknown"}}}
        """)
        _ = try rpcError(capture.object(at: 1), code: -32602)
    }
}
