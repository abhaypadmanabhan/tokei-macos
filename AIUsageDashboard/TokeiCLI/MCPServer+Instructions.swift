import Foundation

extension MCPServer {
    /// MCP clients surface this to the model once at connect time, so the trigger and
    /// trust rules persist for the session instead of depending on per-tool descriptions.
    static let instructions = """
        Before delegating or starting a long task, call get_route; use for to check one agent. \
        Follow ranked plans; avoid 85%+ and unknown, stale or local_estimate readings. \
        accountID is stable; pass selector.env as an environment map to the process API, never shell text. \
        Before optional work call get_burn_opportunities. Never spend credits or paid overage. \
        Read-only; no network or credentials.
        """
}

extension MCPServer {
    func toolDefinitions() -> [[String: Any]] {
        let emptyInput: [String: Any] = [
            "type": "object",
            "properties": [String: Any](),
            "additionalProperties": false
        ]
        var usageInput = emptyInput
        usageInput["properties"] = [
            "provider": ["type": "string", "enum": SnapshotReader.providerIDs.sorted()],
            "detail": ["type": "string", "enum": ["summary"]]
        ]
        var routeInput = emptyInput
        routeInput["properties"] = ["for": ["type": "string", "enum": SnapshotReader.providerIDs.sorted()]]
        var definitions: [[String: Any]] = [
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
                    + "running. Set detail to summary for one short line per provider; omit it for the full schema. " + Self.accountContract + " Read-only; no network or credentials.",
                "inputSchema": usageInput
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
            ],
            [
                "name": ToolName.burnOpportunities.rawValue,
                "description": "Before optional, batch or exploratory work, find fresh flat-rate plan windows "
                    + "that reset soon with unused capacity. Spend these first, within the account's other limits. "
                    + "Never spend credits or paid overage. Returns expiring windows soonest first and plain advice.",
                "inputSchema": emptyInput
            ],
            [
                "name": ToolName.route.rawValue,
                "description": "Which plan should the next task go to. Returns ranked flat-rate plans and one advice line. "
                    + "Use for with a provider ID to check one agent. Unknown readings are withheld and nearly exhausted plans say avoid. "
                    + "Only short plain labels are returned; no account paths or selectors.",
                "inputSchema": routeInput
            ]
        ]
        for index in definitions.indices {
            let usage = index == 0
            definitions[index]["title"] = ["Usage and quota", "Route recommendation", "Use it or lose it", "Which plan next"][index]
            definitions[index]["annotations"] = ["readOnlyHint": true, "idempotentHint": true, "openWorldHint": false]
            if negotiatedVersion == Self.protocolVersion {
                if index == 3 {
                    definitions[index]["outputSchema"] = ["type": "object", "required": ["generatedAt", "stale", "status", "rows", "unknown", "advice"],
                        "properties": ["generatedAt": ["type": "string", "format": "date-time"], "stale": ["type": "boolean"],
                                       "status": ["type": "string"], "rows": ["type": "array", "items": ["type": "object"]],
                                       "unknown": ["type": "array", "items": ["type": "object"]], "advice": ["type": "string"]]]
                } else {
                    definitions[index]["outputSchema"] = index == 2
                    ? ["type": "object", "required": ["generatedAt", "stale", "expiring"],
                       "properties": ["generatedAt": ["type": "string", "format": "date-time"],
                                      "stale": ["type": "boolean"],
                                      "expiring": ["type": "array", "items": ["type": "object"]]]]
                    : outputSchema(usage: usage)
                }
            }
        }
        return definitions
    }

    private static let accountContract = "Accounts use `accountID`, an opaque provider-scoped "
        + "identity that is stable across machines for known identities; `accounts[].id` is a "
        + "legacy locator; feature-detect `accountID` and `target`. An older helper in front of "
        + "a newer app is a lossy proxy. Pass `recommendation.target.selector.env` as the "
        + "environment map to the process API; never concatenate it into a shell string. "
        + "`quota.status` is `eligible`, `expiredCredentials`, `cooldown`, `disabled`, "
        + "`requestFailed`, `noQuotaSource`, or `unknown`; only `eligible` is positive headroom."

    private func outputSchema(usage: Bool) -> [String: Any] {
        if usage {
            return ["type": "object", "required": ["schemaVersion", "generatedAt", "providers"],
                    "properties": ["schemaVersion": ["type": "integer"],
                                   "generatedAt": ["type": "string", "format": "date-time"],
                                   "providers": ["type": "array", "items": ["type": "object"]]]]
        }
        return ["type": "object", "required": ["generatedAt", "stale", "avoid", "reason"],
                "properties": ["generatedAt": ["type": "string", "format": "date-time"],
                               "stale": ["type": "boolean"], "reason": ["type": "string"],
                               "avoid": ["type": "array", "items": ["type": "string"]]]]
    }
}
