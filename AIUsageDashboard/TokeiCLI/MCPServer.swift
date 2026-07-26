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
            respond(id: id, result: initializeResult())
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

    /// Always answer with the version we actually implement, never the one the client
    /// asked for. That is the whole of MCP version negotiation: if the server doesn't
    /// support the requested revision it responds with one it does, and the client
    /// decides whether to continue. Erroring instead is a hard-fail against every
    /// client on a newer spec revision — Claude Code 2.1.x requests `2025-11-25` and
    /// got `-32602: Unsupported protocol version`, so `claude mcp add tokei` registered
    /// fine and then never connected. Echoing the client's value back would be the
    /// opposite bug (claiming support we don't have); returning our own is neither.
    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": Self.protocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": Self.serverName, "version": version],
            "instructions": Self.instructions
        ]
    }

    /// Server-level instructions. MCP clients surface this to the model once, at
    /// connect time, so it persists for the whole session rather than being re-read
    /// per call. Tool descriptions alone don't get an agent to call *unprompted* —
    /// they answer "what does this do", not "when must I reach for it". This states
    /// the trigger, so an orchestrating agent checks quota before it spends it.
    static let instructions = """
        Tokei reports how much quota is left across the AI coding tools on this Mac \
        (Claude Code, Codex, Cursor, Cline, Gemini, Antigravity, Copilot, opencode).

        When to call, without being asked:
        • BEFORE spawning, delegating to, or orchestrating another coding agent or \
        subagent — check where there is room, then pick the target.
        • BEFORE starting a long, parallel, or fan-out job that will consume a \
        provider's quota.
        • When the user asks what they have left, what a plan is worth, or which \
        tool to use for a task.

        Routing work to a provider that is about to hit its limit wastes the run and \
        the user's money. Check first, then choose.

        Reading the result:
        • Treat any provider at or above 85% utilization as unavailable; prefer the \
        least-utilized one that reported real quota.
        • `confidence: official` is provider-reported. Never treat `local_estimate` \
        or `unavailable` as a hard limit — they are floors, not ceilings.
        • If a response is prefixed with a stale warning, Tokei may not be running. \
        Say so instead of presenting the numbers as current.

        Read-only. No network, no credentials, no other application's data.
        """

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
                // Trigger first, payload second: an agent decides whether to call from the
                // opening clause, so "when" has to lead. Same reason `instructions` exists.
                "description": "Call when you need the full quota picture across the user's AI "
                    + "coding tools rather than a single routing verdict — to report what they "
                    + "have left, to size a job against the current window, or to compare two "
                    + "specific providers. Returns per-provider quota windows (used %, reset "
                    + "time, confidence, source), aggregate utilization, token counts, and "
                    + "timestamps. Includes a `stale` flag when the data is old or Tokei isn't "
                    + "running. Read-only; no network or credentials.",
                "inputSchema": emptyInput
            ],
            [
                "name": "get_route_recommendation",
                "description": "Call this BEFORE you spawn, delegate to, or orchestrate another "
                    + "coding agent or subagent, and before any long, parallel, or fan-out run "
                    + "that will consume a provider's quota — routing work to a provider about "
                    + "to hit its limit wastes the run. Returns which provider to route new work "
                    + "to (least-utilized), which to avoid (at or over 85% of a limit), and the "
                    + "reason. Cheap and read-only: prefer calling it over guessing.",
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
