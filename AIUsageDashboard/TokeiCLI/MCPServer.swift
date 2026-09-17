import Foundation
import CoreFoundation

// The `tokei` target compiles Core/Agent/AgentSnapshot.swift directly and does NOT link
// the Core framework (it must stay standalone). The AIUsageDashboardCoreTests bundle
// compiles this file too, but gets the same shapes from the framework — so the import is
// gated on a flag set only on that bundle's copy (see project.yml `sources`). Do not
// switch this to `canImport`: the framework is on the tool target's implicit search path
// whenever it happens to have been built, which would make the tool link Core sometimes.
#if TOKEI_CLI_TESTS
import AIUsageDashboardCore
#endif

/// Bounded newline framing for the stdio transport. Once a frame exceeds the cap,
/// bytes are discarded directly from the input until the next delimiter instead of
/// being accumulated in memory.
struct MCPFrameReader {
    static let maximumFrameBytes = 1024 * 1024
    private static let readChunkBytes = 64 * 1024

    enum Frame: Equatable {
        case data(Data)
        case oversized
    }

    private let readChunk: (Int) -> Data?
    private var buffer = Data()
    private var discardingOversizedFrame = false
    private(set) var peakBufferedByteCount = 0

    init(readChunk: @escaping (Int) -> Data?) {
        self.readChunk = readChunk
    }

    init(fileHandle: FileHandle) {
        self.init { requestedBytes in
            guard let data = try? fileHandle.read(upToCount: requestedBytes),
                  !data.isEmpty
            else {
                return nil
            }
            return data
        }
    }

    mutating func nextFrame() -> Frame? {
        while true {
            if discardingOversizedFrame {
                guard let chunk = readChunk(Self.readChunkBytes), !chunk.isEmpty else {
                    discardingOversizedFrame = false
                    return nil
                }
                guard let delimiter = chunk.firstIndex(of: 0x0A) else { continue }

                discardingOversizedFrame = false
                let suffixStart = chunk.index(after: delimiter)
                if suffixStart < chunk.endIndex {
                    buffer.append(contentsOf: chunk[suffixStart...])
                    recordPeak()
                }
                continue
            }

            if let delimiter = buffer.firstIndex(of: 0x0A) {
                let frameByteCount = buffer.distance(from: buffer.startIndex, to: delimiter)
                let frame = Data(buffer[..<delimiter])
                buffer.removeSubrange(buffer.startIndex...delimiter)
                return frameByteCount <= Self.maximumFrameBytes ? .data(frame) : .oversized
            }

            if buffer.count > Self.maximumFrameBytes {
                buffer.removeAll(keepingCapacity: false)
                discardingOversizedFrame = true
                return .oversized
            }

            let remainingCapacity = Self.maximumFrameBytes + 1 - buffer.count
            let requestedBytes = min(Self.readChunkBytes, remainingCapacity)
            guard let chunk = readChunk(requestedBytes), !chunk.isEmpty else {
                guard !buffer.isEmpty else { return nil }
                let frame = buffer
                buffer.removeAll(keepingCapacity: false)
                return .data(frame)
            }
            buffer.append(chunk)
            recordPeak()
        }
    }

    private mutating func recordPeak() {
        peakBufferedByteCount = max(peakBufferedByteCount, buffer.count)
    }
}

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
    static let oversizedFrameMessage = "Invalid Request: frame exceeds 1048576 bytes."
    private static let maximumDiagnosticNameCharacters = 128

    private enum ToolName: String {
        case usage = "get_usage"
        case routeRecommendation = "get_route_recommendation"
    }

    let reader: SnapshotReader
    let version: String
    /// Every protocol frame is written here. Defaults to stdout; tests inject a capture
    /// so the *framing* (JSON-RPC envelope + the newline delimiter) is asserted rather
    /// than re-implemented. `version` has no default because `TokeiCLI.version` lives in
    /// main.swift, which is deliberately excluded from the test bundle.
    let output: (Data) -> Void

    init(
        reader: SnapshotReader = SnapshotReader(),
        version: String,
        output: @escaping (Data) -> Void = { FileHandle.standardOutput.write($0) }
    ) {
        self.reader = reader
        self.version = version
        self.output = output
    }

    /// Runs the bounded production transport over stdin.
    func run() {
        var frameReader = MCPFrameReader(fileHandle: .standardInput)
        run(frameReader: &frameReader)
    }

    /// Injected line transport retained for focused protocol-loop tests.
    func run(nextLine: () -> String?) {
        while let line = nextLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            handle(line: trimmed)
        }
    }

    func run(frameReader: inout MCPFrameReader) {
        while let frame = frameReader.nextFrame() {
            switch frame {
            case let .data(data):
                guard let line = String(data: data, encoding: .utf8) else {
                    send(errorResponse(id: nil, code: -32700, message: "Parse error"))
                    continue
                }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { handle(line: trimmed) }
            case .oversized:
                send(errorResponse(id: nil, code: -32600, message: Self.oversizedFrameMessage))
            }
        }
    }

    // MARK: - Dispatch

    func handle(line: String) {
        switch parseRequest(line) {
        case let .valid(request):
            dispatch(request)
        case let .invalid(id, code, message):
            send(errorResponse(id: id, code: code, message: message))
        }
    }

    private struct Request {
        let object: [String: Any]
        let id: Any?
        let method: String
        let isNotification: Bool
    }

    private enum RequestParsing {
        case valid(Request)
        case invalid(id: Any?, code: Int, message: String)
    }

    private func parseRequest(_ line: String) -> RequestParsing {
        guard let data = line.data(using: .utf8) else {
            return .invalid(id: nil, code: -32700, message: "Parse error")
        }

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .invalid(id: nil, code: -32700, message: "Parse error")
        }

        // Syntax and envelope validity are separate JSON-RPC layers. A scalar, array,
        // or malformed request object is valid JSON, so it is -32600 rather than -32700.
        guard let object = value as? [String: Any] else {
            return .invalid(id: nil, code: -32600, message: "Invalid Request")
        }

        let hasID = object.keys.contains("id")
        let candidateID = object["id"]
        let validID = !hasID || Self.isValidID(candidateID)
        let responseID = hasID && validID ? candidateID : nil

        guard object["jsonrpc"] as? String == "2.0",
              validID,
              let method = object["method"] as? String
        else {
            return .invalid(id: responseID, code: -32600, message: "Invalid Request")
        }

        // A valid message without an `id` is a notification: process it but never reply.
        return .valid(Request(
            object: object,
            id: responseID,
            method: method,
            isNotification: !hasID
        ))
    }

    private func dispatch(_ request: Request) {
        switch request.method {
        case "initialize":
            respond(id: request.id, result: initializeResult())
        case "notifications/initialized", "notifications/cancelled":
            respond(id: request.id, result: [:])
        case "ping":
            respond(id: request.id, result: [:])
        case "tools/list":
            respond(id: request.id, result: ["tools": toolDefinitions()])
        case "tools/call":
            switch validateToolCall(params: request.object["params"]) {
            case let .valid(name):
                respond(id: request.id, result: toolCallResult(name: name))
            case let .invalid(message):
                if !request.isNotification {
                    send(errorResponse(id: request.id, code: -32602, message: message))
                }
            }
        default:
            if !request.isNotification {
                send(errorResponse(
                    id: request.id,
                    code: -32601,
                    message: "Method not found: \(Self.boundedDiagnosticName(request.method))"
                ))
            }
        }
    }

    private static func boundedDiagnosticName(_ name: String) -> String {
        String(name.prefix(maximumDiagnosticNameCharacters))
    }

    private static func isValidID(_ value: Any?) -> Bool {
        guard let value else { return false }
        if value is NSNull || value is String { return true }
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
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
        • A low number you do not trust is NOT free capacity. A stale or estimated 0% \
        means "no reading", not "wide open" — absence of data is not headroom.
        • `observedAt` on a window is when that reading was taken. The top-level \
        `stale` flag is a different thing: it only says how long ago Tokei wrote the \
        file, so `stale: false` can still contain hour-old numbers. Judge freshness \
        per window.
        • `accounts[].accountID` is the opaque, provider-scoped identity. For known \
        identities it is stable across machines. `accounts[].id` is only a legacy \
        local locator; never join accounts on it.
        • To act on `recommendation.target.selector.env`, pass that map as the \
        environment argument to the process API. Never concatenate selector values \
        into a shell string.
        • Feature-detect `accountID` and `target`. An older helper in front of a newer \
        app is a lossy proxy even though both snapshots use schema version 1.
        • `quota.status` is `eligible`, `expiredCredentials`, `cooldown`, `disabled`, \
        `requestFailed`, `noQuotaSource`, or `unknown`. Only `eligible` publishes \
        positive headroom and a bounded `validUntil` decision.
        • If `stale` is true, Tokei may not be running or the recommendation expired. \
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
                "name": ToolName.usage.rawValue,
                // Trigger first, payload second: an agent decides whether to call from the
                // opening clause, so "when" has to lead. Same reason `instructions` exists.
                "description": "Call when you need the full quota picture across the user's AI "
                    + "coding tools rather than a single routing verdict — to report what they "
                    + "have left, to size a job against the current window, or to compare two "
                    + "specific providers. Returns per-provider quota windows (used %, reset "
                    + "time, confidence, source), aggregate utilization, token counts, and "
                    + "timestamps. Includes a `stale` flag when the data is old or Tokei isn't "
                    + "running. " + Self.accountContract + " Read-only; no network or credentials.",
                "inputSchema": emptyInput
            ],
            [
                "name": ToolName.routeRecommendation.rawValue,
                "description": "Call this BEFORE you spawn, delegate to, or orchestrate another "
                    + "coding agent or subagent, and before any long, parallel, or fan-out run "
                    + "that will consume a provider's quota — routing work to a provider about "
                    + "to hit its limit wastes the run. Returns which provider to route new work "
                    + "to (least-utilized), which to avoid (at or over 85% of a limit), and the "
                    + "reason, with generatedAt, ageSeconds, validUntil, and stale metadata. "
                    + Self.accountContract + " Cheap and read-only: prefer calling it over guessing.",
                "inputSchema": emptyInput
            ]
        ]
    }

    private static let accountContract = "Accounts use `accountID`, an opaque provider-scoped "
        + "identity that is stable across machines for known identities; `accounts[].id` is a "
        + "legacy locator; feature-detect `accountID` and `target`. An older helper in front of "
        + "a newer app is a lossy proxy. Pass `recommendation.target.selector.env` as the "
        + "environment map to the process API; never concatenate it into a shell string. "
        + "`quota.status` is `eligible`, `expiredCredentials`, `cooldown`, `disabled`, "
        + "`requestFailed`, `noQuotaSource`, or `unknown`; only `eligible` is positive headroom."

    // MARK: - tools/call

    private enum ToolCallValidation {
        case valid(ToolName)
        case invalid(String)
    }

    private func validateToolCall(params: Any?) -> ToolCallValidation {
        guard let params = params as? [String: Any] else {
            return .invalid("Invalid tools/call params: expected an object.")
        }
        guard let name = params["name"] as? String else {
            return .invalid("Missing tool name.")
        }
        guard let tool = ToolName(rawValue: name) else {
            return .invalid("Unknown tool: \(Self.boundedDiagnosticName(name))")
        }
        if let value = params["arguments"] {
            guard let arguments = value as? [String: Any], arguments.isEmpty else {
                return .invalid(
                    "Invalid arguments for \(Self.boundedDiagnosticName(name)): expected an empty object."
                )
            }
        }
        return .valid(tool)
    }

    private func toolCallResult(name: ToolName) -> [String: Any] {
        do {
            let snapshot = try reader.read()
            switch name {
            case .usage:
                return textContent(try encode(snapshot), warning: staleWarning(snapshot))
            case .routeRecommendation:
                return textContent(try recommendationText(snapshot), warning: staleWarning(snapshot))
            }
        } catch let error as SnapshotReadError {
            return textContent(error.message, isError: true)
        } catch {
            return textContent("tokei: \(error.localizedDescription)", isError: true)
        }
    }

}

// MARK: - Tool output

private extension MCPServer {
    struct RoutePayload: Encodable {
        let generatedAt: Date
        let ageSeconds: Int?
        let stale: Bool
        let routeTo: String?
        let avoid: [String]
        let reason: String
        let target: AgentRecommendationTarget?
        let avoidAccounts: [AgentAccountReference]?
        let validUntil: Date?
    }

    /// Keep content[0] machine-parseable JSON; the optional second block is for models.
    func staleWarning(_ snapshot: AgentSnapshot) -> String? {
        guard snapshot.stale == true else { return nil }
        let age = snapshot.ageSeconds.map(StatusFormatting.humanAge(seconds:)) ?? "unknown age"
        return "⚠︎ Tokei data is stale (\(age) old); the app may not be running. Values may be outdated."
    }

    func recommendationText(_ snapshot: AgentSnapshot) throws -> String {
        let recommendation = snapshot.recommendation
        let decisionExpired = recommendation?.validUntil.map { reader.now() > $0 } ?? false
        return try encode(RoutePayload(
            generatedAt: snapshot.generatedAt,
            ageSeconds: snapshot.ageSeconds,
            stale: snapshot.stale == true || decisionExpired,
            routeTo: recommendation?.routeTo,
            avoid: recommendation?.avoid ?? [],
            reason: recommendation?.reason
                ?? "No routing recommendation available (not enough providers reported live quota).",
            target: recommendation?.target,
            avoidAccounts: recommendation?.avoidAccounts,
            validUntil: recommendation?.validUntil
        ))
    }

    func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try AgentSnapshot.makeEncoder().encode(value)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Encoded data is not valid UTF-8")
            )
        }
        return text
    }

    func textContent(
        _ text: String,
        isError: Bool = false,
        warning: String? = nil
    ) -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": text]]
        if let warning {
            content.append(["type": "text", "text": warning])
        }
        return [
            "content": content,
            "isError": isError
        ]
    }
}

// MARK: - JSON-RPC framing

private extension MCPServer {
    func respond(id: Any?, result: [String: Any]) {
        guard let id else { return } // notification — no reply
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        var line = data
        line.append(0x0A) // newline-delimited transport
        output(line)
    }
}
