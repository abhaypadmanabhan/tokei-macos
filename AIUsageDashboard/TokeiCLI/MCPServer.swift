import Foundation

/// Minimal stdio MCP server (issue #57). Speaks newline-delimited JSON-RPC 2.0 over
/// stdin/stdout — the stdio transport every major client supports without caveats.
///
/// Deliberately dependency-free: read-only and no network, so pulling in the MCP
/// Swift SDK (and a build-time package fetch) buys nothing. Exactly two tools, to keep
/// an agent's context cost low:
///   • `get_usage`                → full snapshot
///   • `get_route_recommendation` → recommendation object only
///
/// Protocol messages are line-delimited JSON; logs/diagnostics go to stderr so they
/// never corrupt the protocol stream on stdout.
struct MCPServer {
    static let protocolVersion = "2024-11-05"
    static let serverName = "tokei"

    let reader: SnapshotReader
    let version: String

    init(reader: SnapshotReader = SnapshotReader(), version: String = TokeiCLI.version) {
        self.reader = reader
        self.version = version
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            handle(line: trimmed)
        }
    }

    // MARK: - Dispatch

    private func handle(line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            send(errorResponse(id: nil, code: -32700, message: "Parse error"))
            return
        }

        let method = object["method"] as? String
        // A message without an `id` is a notification: never reply (per JSON-RPC).
        let id = object["id"]
        let isNotification = id == nil

        switch method {
        case "initialize":
            respond(id: id, result: initializeResult(from: object))
        case "notifications/initialized", "notifications/cancelled":
            break // notifications — no response
        case "ping":
            respond(id: id, result: [:])
        case "tools/list":
            respond(id: id, result: ["tools": toolDefinitions()])
        case "tools/call":
            respond(id: id, result: toolCallResult(params: object["params"] as? [String: Any]))
        default:
            if !isNotification {
                send(errorResponse(id: id, code: -32601, message: "Method not found: \(method ?? "nil")"))
            }
        }
    }

    // MARK: - initialize

    private func initializeResult(from request: [String: Any]) -> [String: Any] {
        // Echo the client's protocol version when it sent one; otherwise our default.
        let clientVersion = (request["params"] as? [String: Any])?["protocolVersion"] as? String
        return [
            "protocolVersion": clientVersion ?? Self.protocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": Self.serverName, "version": version]
        ]
    }

    // MARK: - tools/list

    private func toolDefinitions() -> [[String: Any]] {
        let emptyInput: [String: Any] = [
            "type": "object",
            "properties": [String: Any](),
            "additionalProperties": false
        ]
        return [
            [
                "name": "get_usage",
                "description": "Return Tokei's full cross-tool quota snapshot: per-provider "
                    + "quota windows (used %, reset time, confidence, source), aggregate "
                    + "utilization, token counts, and timestamps. Includes a `stale` flag when "
                    + "the data is old or Tokei isn't running.",
                "inputSchema": emptyInput
            ],
            [
                "name": "get_route_recommendation",
                "description": "Return only Tokei's routing recommendation: which provider to "
                    + "route new work to (least-utilized) and which to avoid (near their limit), "
                    + "with a human-readable reason. Use before delegating to another coding agent.",
                "inputSchema": emptyInput
            ]
        ]
    }

    // MARK: - tools/call

    private func toolCallResult(params: [String: Any]?) -> [String: Any] {
        guard let name = params?["name"] as? String else {
            return textContent("Missing tool name.", isError: true)
        }
        do {
            let snapshot = try reader.read()
            switch name {
            case "get_usage":
                return textContent(prefixWarning(snapshot) + (try encode(snapshot)))
            case "get_route_recommendation":
                return textContent(prefixWarning(snapshot) + (try recommendationText(snapshot)))
            default:
                return textContent("Unknown tool: \(name)", isError: true)
            }
        } catch let error as SnapshotReadError {
            return textContent(error.message, isError: true)
        } catch {
            return textContent("tokei: \(error.localizedDescription)", isError: true)
        }
    }

    /// Never serve stale data silently — prefix a warning the agent will see (issue §4).
    private func prefixWarning(_ snapshot: AgentSnapshot) -> String {
        guard snapshot.stale == true else { return "" }
        let age = snapshot.ageSeconds.map(StatusFormatting.humanAge(seconds:)) ?? "unknown age"
        return "⚠︎ Tokei data is stale (\(age) old); the app may not be running. Values below may be outdated.\n\n"
    }

    private func recommendationText(_ snapshot: AgentSnapshot) throws -> String {
        guard let recommendation = snapshot.recommendation else {
            return "No routing recommendation available (not enough providers reported live quota)."
        }
        return try encode(recommendation)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try AgentSnapshot.makeEncoder().encode(value)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Encoded data is not valid UTF-8")
            )
        }
        return text
    }

    private func textContent(_ text: String, isError: Bool = false) -> [String: Any] {
        [
            "content": [["type": "text", "text": text]],
            "isError": isError
        ]
    }

    // MARK: - JSON-RPC framing

    private func respond(id: Any?, result: [String: Any]) {
        guard let id else { return } // notification — no reply
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        var line = data
        line.append(0x0A) // newline-delimited transport
        FileHandle.standardOutput.write(line)
    }
}
