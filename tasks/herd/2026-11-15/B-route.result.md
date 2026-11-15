STATUS: READY

## RoutePlan public API (frozen in first commit e33390e)

```swift
public struct RoutePlan: Sendable, Equatable {
    public enum Disposition: String, Sendable, Equatable { case ready, avoid }
    public let generatedAt: Date
    public let rows: [Row]
    public let unknown: [Unknown]
    public var recommendation: Row? { get }
    public static func make(snapshots: [ProviderSnapshot], now: Date) -> RoutePlan

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: String
        public let providerID: ProviderID
        public let providerName: String
        public let accountLabel: String?
        public let windowType: QuotaWindowType
        public let windowLabel: String?
        public let remainingPercent: Double
        public let resetAt: Date?
        public let secondsToReset: TimeInterval?
        public let paceState: QuotaPace.State?
        public let disposition: Disposition
        public let reason: String
        public let validUntil: Date
        public let expiringAt: Date?
    }
    public struct Unknown: Sendable, Equatable, Identifiable {
        public let id: String
        public let providerID: ProviderID
        public let accountLabel: String?
        public let reason: String
    }
}
```

No public RoutePlan shape changed after that commit. There are no public row initializers; UI callers construct the plan from snapshots. Account labels are present only for multiple accounts, and unsafe labels become generic account labels. Row IDs contain only a provider and ordinal, never account IDs or profile paths.

## AC 1: one ranking rule

Implemented `Core/Utilization/RoutePlan.swift`. ExpiringHeadroomFinder supplies expiry priority; the account's tightest plan window still bounds its available capacity, so an expiring session cannot hide an exhausted weekly limit. Remaining plans rank by room relative to pace, using reported durations when supplied. At or above 85% used is avoid. Unknown readings are separate. Credit, lifetime and per-model-only balances never become plan recommendations. The old human spread/ceiling and minimum-provider presentation gates remain, but a policy target uses the same comparator. One plan can be recommended by RoutePlan even when the older chip has nothing to say.

`Core/Agent/AccountQuotaDecision.swift` uses the same ordering to choose the provider's headline account; its eligibility boundary remains in place. Provider-level readings retain the existing policy's compatibility rule that a missing observation timestamp is not by itself proof of staleness; account-level eligibility still requires complete fresh coverage.

Table cases cover no plans, one plan, ties, exhausted/near-exhausted, stale/untrusted/future/expired data, expiring capacity, competing account limits, label sanitization, and custom monthly durations. Initial exact command (working directory `AIUsageDashboard/`; `xcodegen generate` ran before the first test build):

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/RoutePlanTests -only-testing:AIUsageDashboardCoreTests/RouteTargetPolicyTests -only-testing:AIUsageDashboardCoreTests/AccountQuotaDecisionTests test
```

Initial output: `Executed 38 tests, with 0 failures`; `** TEST SUCCEEDED **`.
Final output from the expanded command below:

```text
Test Suite 'RoutePlanTests' passed at 2026-11-15 02:16:17.783.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.006 (0.008) seconds
Test Suite 'RouteTargetPolicyTests' passed at 2026-11-15 02:16:17.800.
	 Executed 20 tests, with 0 failures (0 unexpected) in 0.013 (0.017) seconds
Test Suite 'AccountQuotaDecisionTests' passed at 2026-11-15 02:16:12.305.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.010 (0.014) seconds
```

Before implementation, this command failed on the old rule:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/RouteTargetPolicyTests/testExpiringCapacityWinsOverAnEmptierPlan test
```

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/AgentTests/RouteTargetPolicyTests.swift:20: error: -[AIUsageDashboardCoreTests.RouteTargetPolicyTests testExpiringCapacityWinsOverAnEmptierPlan] : XCTAssertEqual failed: ("Optional(AIUsageDashboardCore.ProviderID.claudeCode)") is not equal to ("Optional(AIUsageDashboardCore.ProviderID.codex)")
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/AgentTests/RouteTargetPolicyTests.swift:21: error: -[AIUsageDashboardCoreTests.RouteTargetPolicyTests testExpiringCapacityWinsOverAnEmptierPlan] : XCTAssertEqual failed: ("Optional(AIUsageDashboardCore.ProviderID.claudeCode)") is not equal to ("Optional(AIUsageDashboardCore.ProviderID.codex)")
** TEST FAILED **
```

A second reproduction exposed the dropped custom duration before its fix:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/RoutePlanTests/testReportedMonthlyDurationRanksByActualPaceOnBothPaths test
```

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:100: error: -[AIUsageDashboardCoreTests.RoutePlanTests testReportedMonthlyDurationRanksByActualPaceOnBothPaths] : XCTAssertEqual failed: ("Optional(AIUsageDashboardCore.ProviderID.claudeCode)") is not equal to ("Optional(AIUsageDashboardCore.ProviderID.codex)")
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:101: error: -[AIUsageDashboardCoreTests.RoutePlanTests testReportedMonthlyDurationRanksByActualPaceOnBothPaths] : XCTAssertEqual failed: ("Optional(AIUsageDashboardCore.ProviderID.claudeCode)") is not equal to ("Optional(AIUsageDashboardCore.ProviderID.codex)")
** TEST FAILED **
```

## AC 2: additive agent snapshot route block

`Core/Agent/AgentSnapshot.swift` gains optional `route`; `AgentRoute.swift` holds the Foundation-only Codable projection; `RoutePlan+Agent.swift` maps it. `AgentSnapshotWriter.swift` writes the block. Existing snapshot fields and schema version remain. Old snapshots without route decode, and recommendation-expiry copies preserve route. Existing snapshot tests were not edited.

Exact initial command:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/AgentRouteSnapshotTests -only-testing:AIUsageDashboardCoreTests/RouteCommandTests -only-testing:AIUsageDashboardCoreTests/RouteMCPTests test
```

Initial output: `Executed 5 tests, with 0 failures`; `** TEST SUCCEEDED **`.
Final output:

```text
Test Suite 'AgentRouteSnapshotTests' passed at 2026-11-15 02:16:13.618.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'AgentSnapshotWriterTests' passed at 2026-11-15 02:16:13.659.
	 Executed 12 tests, with 0 failures (0 unexpected) in 0.015 (0.018) seconds
Test Suite 'AgentSnapshotAccountSchemaTests' passed at 2026-11-15 02:16:13.637.
	 Executed 13 tests, with 0 failures (0 unexpected) in 0.015 (0.019) seconds
```

## AC 3: MCP get_route

Added the closed, read-only `get_route` tool, optional `for` provider ID, ranked rows plus one advice line. All three protocol revisions negotiate and return the same payload; only 2025-06-18 adds structuredContent/outputSchema, matching the existing compatibility rule. The initialize instructions are 389 characters. Existing tool input/output contracts and descriptions remain; legacy tool-count assertions now include the additive fourth tool. Unsafe labels, account emails/paths, control sequences and arbitrary provider names cannot enter the new route output. A missing snapshot error has no local path.

Exact initial command was the AC 2 command above. Final command is the expanded command below. Output:

```text
Test Suite 'RouteMCPTests' passed at 2026-11-15 02:16:17.775.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.005 (0.005) seconds
Test Suite 'MCPServerTests' passed at 2026-11-15 02:16:16.026.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.426 (0.429) seconds
Test Suite 'MCPServerExchangeMatrixTests' passed at 2026-11-15 02:16:14.888.
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.020 (0.023) seconds
```

## AC 4: tokei route

`RouteCommand.swift` adds `route [--json] [--for <provider ID>]`; `RouteFormatting.swift` supplies both CLI and MCP responses. Exit 0 means a recommendation, 1 exhausted/near-exhausted plans, 69 unavailable/stale/expired readings, 64 invalid arguments. Human output is capped to one screen; JSON retains all rows. Help documents the codes. The reader checks saved decision expiry and timestamps and never silently rebuilds a recommendation from a legacy snapshot.

Exact initial command was the AC 2 command above. Formatting/process tests exercise the actual built helper, JSON validity, all exit states, provider selection, missing/duplicate/unknown arguments and help. Final output:

```text
Test Suite 'RouteCommandTests' passed at 2026-11-15 02:16:17.770.
	 Executed 3 tests, with 0 failures (0 unexpected) in 1.132 (1.133) seconds
```

Before this change, the built old helper returned exit 64 and `tokei: unknown command 'route'` for `/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei route`.

## AC 5: build-derived helper version

The tool embeds its generated Info.plist in the executable, with CFBundleShortVersionString from MARKETING_VERSION. `main.swift` reads that embedded value. No second version string or fallback remains. `cli-version-sync.sh` verifies the build/source relationship and can check a real binary via TOKEI_CLI_BINARY.

Exact test command:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/CLIVersionProcessTests -only-testing:AIUsageDashboardCoreTests/RouteCommandTests test
```

Final output:

```text
Test Suite 'CLIVersionProcessTests' passed at 2026-11-15 02:16:13.761.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.088 (0.088) seconds
```

Actual version override proof (then restored the default build):

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme tokei -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route MARKETING_VERSION=9.8.7 build
/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei version
# tokei 9.8.7
xcodebuild -project AIUsageDashboard.xcodeproj -scheme tokei -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route build
/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei version
# tokei 0.12.0
TOKEI_CLI_BINARY=/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei bash .claude/gates/cli-version-sync.sh
# [cli-version-sync] PASS helper version derives from MARKETING_VERSION (0.12.0)
```

Both builds printed `** BUILD SUCCEEDED **`. Current branch version remains 0.12.0; the orchestrator owns the release bump.

## AC 6: real read-only snapshot proof

Ran the built helper without TOKEI_SNAPSHOT_PATH against this Mac's live agent snapshot. Did not install it, register clients, launch or quit the installed app. The current installed app writes the old snapshot without the new route block, so the honest answer is 69/unavailable rather than a fabricated recommendation. JSON parsed successfully. MCP initialize, initialized notification, tools/list and tools/call get_route completed over the real stdio transport. This proves the older-app failure state; a positive live recommendation still needs the new app at integration.

Exact CLI paths:

```sh
/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei route
/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei route --json
/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Debug/tokei mcp
```

MCP stdin frames:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_route","arguments":{}}}
```

Redacted actual transcript (also saved at `~/Library/Developer/TokeiWork/proof/route/live-agent-proof.txt`):

```text
COMMAND: tokei route
EXIT: 69
No fresh plan recommendation is available. Refresh Tokei before routing work.
COMMAND: tokei route --json
EXIT: 69
{"advice": "No fresh plan recommendation is available. Refresh Tokei before routing work.", "generatedAt": "2026-11-15T10:09:51Z", "rows": [], "stale": false, "status": "unavailable", "unknown": []}
COMMAND: tokei mcp (initialize, notifications/initialized, tools/list, tools/call get_route)
EXIT: 0
{"id": 1, "jsonrpc": "2.0", "result": {"capabilities": {"tools": {}}, "instructions": "Before delegating or starting a long task, call get_route; use for to check one agent. Follow ranked plans; avoid 85%+ and unknown, stale or local_estimate readings. accountID is stable; pass selector.env as an environment map to the process API, never shell text. Before optional work call get_burn_opportunities. Never spend credits or paid overage. Read-only; no network or credentials.", "protocolVersion": "2025-06-18", "serverInfo": {"name": "tokei", "version": "0.12.0"}}}
{"id": 2, "jsonrpc": "2.0", "result": {"tools": [{"annotations": {"idempotentHint": true, "openWorldHint": false, "readOnlyHint": true}, "description": "Call when you need the full quota picture across the user's AI coding tools rather than a single routing verdict \u2014 to report what they have left, to size a job against the current window, or to compare two specific providers. Returns per-provider quota windows (used %, reset time, confidence, source), aggregate utilization, token counts, and timestamps. Includes a `stale` flag when the data is old or Tokei isn't running. Set detail to summary for one short line per provider; omit it for the full schema. Accounts use `accountID`, an opaque provider-scoped identity that is stable across machines for known identities; `accounts[].id` is a legacy locator; feature-detect `accountID` and `target`. An older helper in front of a newer app is a lossy proxy. Pass `recommendation.target.selector.env` as the environment map to the process API; never concatenate it into a shell string. `quota.status` is `eligible`, `expiredCredentials`, `cooldown`, `disabled`, `requestFailed`, `noQuotaSource`, or `unknown`; only `eligible` is positive headroom. Read-only; no network or credentials.", "inputSchema": {"additionalProperties": false, "properties": {"detail": {"enum": ["summary"], "type": "string"}, "provider": {"enum": ["antigravity", "claude_code", "cline", "codex", "copilot", "cursor", "gemini", "opencode"], "type": "string"}}, "type": "object"}, "name": "get_usage", "outputSchema": {"properties": {"generatedAt": {"format": "date-time", "type": "string"}, "providers": {"items": {"type": "object"}, "type": "array"}, "schemaVersion": {"type": "integer"}}, "required": ["schemaVersion", "generatedAt", "providers"], "type": "object"}, "title": "Usage and quota"}, {"annotations": {"idempotentHint": true, "openWorldHint": false, "readOnlyHint": true}, "description": "Call this BEFORE you spawn, delegate to, or orchestrate another coding agent or subagent, and before any long, parallel, or fan-out run that will consume a provider's quota \u2014 routing work to a provider about to hit its limit wastes the run. Returns which provider to route new work to (least-utilized), which to avoid (at or over 85% of a limit), and the reason, with generatedAt, ageSeconds, validUntil, and stale metadata. Accounts use `accountID`, an opaque provider-scoped identity that is stable across machines for known identities; `accounts[].id` is a legacy locator; feature-detect `accountID` and `target`. An older helper in front of a newer app is a lossy proxy. Pass `recommendation.target.selector.env` as the environment map to the process API; never concatenate it into a shell string. `quota.status` is `eligible`, `expiredCredentials`, `cooldown`, `disabled`, `requestFailed`, `noQuotaSource`, or `unknown`; only `eligible` is positive headroom. Cheap and read-only: prefer calling it over guessing.", "inputSchema": {"additionalProperties": false, "properties": {}, "type": "object"}, "name": "get_route_recommendation", "outputSchema": {"properties": {"avoid": {"items": {"type": "string"}, "type": "array"}, "generatedAt": {"format": "date-time", "type": "string"}, "reason": {"type": "string"}, "stale": {"type": "boolean"}}, "required": ["generatedAt", "stale", "avoid", "reason"], "type": "object"}, "title": "Route recommendation"}, {"annotations": {"idempotentHint": true, "openWorldHint": false, "readOnlyHint": true}, "description": "Before optional, batch or exploratory work, find fresh flat-rate plan windows that reset soon with unused capacity. Spend these first, within the account's other limits. Never spend credits or paid overage. Returns expiring windows soonest first and plain advice.", "inputSchema": {"additionalProperties": false, "properties": {}, "type": "object"}, "name": "get_burn_opportunities", "outputSchema": {"properties": {"expiring": {"items": {"type": "object"}, "type": "array"}, "generatedAt": {"format": "date-time", "type": "string"}, "stale": {"type": "boolean"}}, "required": ["generatedAt", "stale", "expiring"], "type": "object"}, "title": "Use it or lose it"}, {"annotations": {"idempotentHint": true, "openWorldHint": false, "readOnlyHint": true}, "description": "Which plan should the next task go to. Returns ranked flat-rate plans and one advice line. Use for with a provider ID to check one agent. Unknown readings are withheld and nearly exhausted plans say avoid. Only short plain labels are returned; no account paths or selectors.", "inputSchema": {"additionalProperties": false, "properties": {"for": {"enum": ["antigravity", "claude_code", "cline", "codex", "copilot", "cursor", "gemini", "opencode"], "type": "string"}}, "type": "object"}, "name": "get_route", "outputSchema": {"properties": {"advice": {"type": "string"}, "generatedAt": {"format": "date-time", "type": "string"}, "rows": {"items": {"type": "object"}, "type": "array"}, "stale": {"type": "boolean"}, "status": {"type": "string"}, "unknown": {"items": {"type": "object"}, "type": "array"}}, "required": ["generatedAt", "stale", "status", "rows", "unknown", "advice"], "type": "object"}, "title": "Which plan next"}]}}
{"id": 3, "jsonrpc": "2.0", "result": {"content": [{"text": "{\"advice\": \"No fresh plan recommendation is available. Refresh Tokei before routing work.\", \"generatedAt\": \"2026-11-15T10:09:51Z\", \"rows\": [], \"stale\": false, \"status\": \"unavailable\", \"unknown\": []}", "type": "text"}], "isError": false, "structuredContent": {"advice": "No fresh plan recommendation is available. Refresh Tokei before routing work.", "generatedAt": "2026-11-15T10:09:51Z", "rows": [], "stale": false, "status": "unavailable", "unknown": []}}}
```

## Final compatibility verification

Working directory `/Users/abhayp/wt/lane2/AIUsageDashboard`. `xcodegen generate` was run before building. Ran all existing AgentTests and CLITests plus UtilizationTests and MaxxerMathTests, targeted by class; did not run the whole repo suite.

Exact final command:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/AccountQuotaDecisionTests -only-testing:AIUsageDashboardCoreTests/AgentBurnSnapshotTests -only-testing:AIUsageDashboardCoreTests/AgentCommandProcessTests -only-testing:AIUsageDashboardCoreTests/AgentRecommendationAccountTests -only-testing:AIUsageDashboardCoreTests/AgentRecommendationEngineTests -only-testing:AIUsageDashboardCoreTests/AgentRecommendationReasonTests -only-testing:AIUsageDashboardCoreTests/AgentRouteSnapshotTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotAccountSchemaTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotStalenessTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotWriterTests -only-testing:AIUsageDashboardCoreTests/BurnMCPTests -only-testing:AIUsageDashboardCoreTests/CLIVersionProcessTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/ExtraUsageRoutingTests -only-testing:AIUsageDashboardCoreTests/ForecastForwardCompatibilityTests -only-testing:AIUsageDashboardCoreTests/GuardProcessTests -only-testing:AIUsageDashboardCoreTests/InformationalCreditsTests -only-testing:AIUsageDashboardCoreTests/MCPAccountContractTests -only-testing:AIUsageDashboardCoreTests/MCPServerErrorTests -only-testing:AIUsageDashboardCoreTests/MCPServerExchangeMatrixTests -only-testing:AIUsageDashboardCoreTests/MCPServerMemoryTests -only-testing:AIUsageDashboardCoreTests/MCPServerProcessTests -only-testing:AIUsageDashboardCoreTests/MCPServerTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/ReviewCLIFormatTests -only-testing:AIUsageDashboardCoreTests/ReviewSingleProviderGuardTests -only-testing:AIUsageDashboardCoreTests/RouteCommandTests -only-testing:AIUsageDashboardCoreTests/RouteMCPTests -only-testing:AIUsageDashboardCoreTests/RoutePlanTests -only-testing:AIUsageDashboardCoreTests/RouteTargetPolicyTests -only-testing:AIUsageDashboardCoreTests/SnapshotForecastTests -only-testing:AIUsageDashboardCoreTests/SnapshotReaderTests -only-testing:AIUsageDashboardCoreTests/StatusFormattingTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/WP4MCPTests test
```

```text
Executed 289 tests, with 0 failures (0 unexpected) in 5.542 (5.622) seconds
** TEST SUCCEEDED **
```

Then, from the worktree root:

```sh
bash .claude/gates/run-all.sh fast
```

```text
══════ SUMMARY (fast) ══════
PASS  preflight
PASS  no-secret
PASS  no-large-artifact
PASS  no-uncommitted
PASS  cli-version-sync
PASS  format
PASS  lint
[run-all] ALL GATES GREEN
```

Format and lint entries are optional-tool SKIP: swiftformat and swiftlint are not installed. The fast gate reports them as PASS in its summary; no formatting/lint execution is claimed. Pre-commit hooks ran on all three commits. Worktree is clean.

## Commits

`git log --oneline dev..HEAD`:

```text
4c3960f fix(route): preserve reported window durations for pace ranking
045d7c6 feat(agents): expose ranked plan routing through CLI and MCP
e33390e feat(route): add the shared ranked plan contract
```

## Contract additions and approved scope extension

- `RoutePlan` public API above, stable since e33390e.
- Optional `AgentSnapshot.route: AgentRoute?`, with generatedAt, rows and unknown; Foundation-only AgentRouteRow and AgentRouteUnknown types. Existing root keys retain their types and schema version stays 1.
- MCP get_route, optional for with a canonical provider ID; payload generatedAt/stale/status/rows/unknown/advice. Existing tools remain additive-compatible.
- CLI route plus documented exit codes; helper version derives from MARKETING_VERSION.
- AgentBurnWindow exposes the existing plain-label predicate and its shared plain-text variant so new output uses the same allowlist.
- Orchestrator t1d explicitly approved optional `Utilization.windowDuration: TimeInterval? = nil` and propagation through UtilizationEngine and the Core/Agent projections. Existing initializers remain compatible. Utilization IS persisted by UtilizationCache as Codable values in its local utilization-cache.json sidecar, not a UsageStore database migration. A test proves absence of the optional key decodes and that the value survives a cache write/reload. Existing Utilization/Cache tests pass untouched. The default provider-implied duration still applies when the reported duration is absent.

## Not checked, risks and integration handoff

- Positive routing on fresh real data: the live installed app's older snapshot lacks route. Verified positive paths through the actual built helper with synthetic snapshots; orchestrator must launch the new app for positive live proof. No installed-app lifecycle changes were made.
- UI, full app build/UI launch, Release signing/notarization, and the full suite belong to integration. No new dependency or product network call was added.
- Repo finish gates secscan, prove-red, cross-model review and work-log are the orchestrator's responsibility under worker.md; not run here. Both regression failures before fixes are captured above with real output.
- Human route policy intentionally retains its display gates and can give no chip even when RoutePlan recommends the sole healthy plan. Consumers should use RoutePlan.recommendation for the new feature.
- Historical route rows expire at the earliest reading/reset bound. The helper excludes expired decisions instead of silently re-ranking them.
- Rollback: revert the lane merge, `git revert -m 1 <merge sha>`.
- All hc test/build terminals started by this worker are stopped/removed before reporting. No dev server or watcher was started; listener inspection found no worker-started service.

Proof files: `~/Library/Developer/TokeiWork/proof/route/{expiry-before.log,duration-before.log,tests-final.log,fast-gates.log,version-override.log,live-agent-proof.txt}`. Synthetic build/test logs remain in the worktree's ignored `.scratch/` as well.


## Fix round 1

STATUS: READY. All accepted findings S1-S6 and S9 are addressed in three commits. S7 and S8 remain declined as instructed. RoutePlan's public API remains unchanged.

Each requested finding was reproduced red on 4c3960f before production edits. The initial focused command exited 65 with `Executed 18 tests, with 30 failures`; `** TEST FAILED **`. The same focused classes then passed, followed by the wider compatibility run. All commands below ran in `/Users/abhayp/wt/lane2/AIUsageDashboard` unless the worktree root is named.

Exact red/initial green command (`xcodegen generate` ran first):

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/RoutePlanTests -only-testing:AIUsageDashboardCoreTests/RouteMCPTests -only-testing:AIUsageDashboardCoreTests/RouteCommandTests -only-testing:AIUsageDashboardCoreTests/CLIVersionProcessTests test
```

### S1: comparable pace score

Commit: `a4f41fc`. Unknown pace now contributes zero elapsed percentage points, so every score is elapsed minus used. The reviewer P1 case again selects the empty Claude plan on the new planner and the shipped recommendation.

Test: `RoutePlanTests testS1LegacyRecommendationStillSelectsTheEmptyPlanWhenMonthlyPaceIsUnknown`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:76: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS1LegacyRecommendationStillSelectsTheEmptyPlanWhenMonthlyPaceIsUnknown] : XCTAssertEqual failed: ("Optional("cursor")") is not equal to ("Optional("claude_code")")
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:77: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS1LegacyRecommendationStillSelectsTheEmptyPlanWhenMonthlyPaceIsUnknown] : XCTAssertEqual failed: ("Optional("cursor")") is not equal to ("Optional("claude_code")")
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testS1LegacyRecommendationStillSelectsTheEmptyPlanWhenMonthlyPaceIsUnknown]' passed (0.001 seconds).
```

### S2: spendable expiry headroom

Commit: `a4f41fc`. Expiry priority requires at least the finder's 25% minimum remaining across every binding limit. Boundary cases 24%, 25% and 26% verify that a roomy expiring session cannot hide a tight weekly pool.

Test: `RoutePlanTests testS2ExpiryPriorityIsBoundedByEveryOtherLimitAtTheFinderFloor`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:87: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS2ExpiryPriorityIsBoundedByEveryOtherLimitAtTheFinderFloor] : XCTAssertEqual failed: ("true") is not equal to ("false") - remaining 24.0
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testS2ExpiryPriorityIsBoundedByEveryOtherLimitAtTheFinderFloor]' passed (0.001 seconds).
```

### S3: shared eligibility and per-model limits

Commit: `a4f41fc; protocol proof in 1bff7ff`. RoutePlan owns the binding window filter, stable binding-window choice and numeric/trust/expiry check. The planner, policy and account decision consume them. Per-model ceilings constrain a plan and can be its deciding window. Model-only balances still cannot create a flat-rate recommendation. The AC1 table compares avoid rows and also checks nil target cases; stale unknowns retain the legacy pressure warning rather than becoming a recommendation.

Test: `RoutePlanTests testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:97: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown] : XCTAssertEqual failed: ("[AIUsageDashboardCore.ProviderID.claudeCode, AIUsageDashboardCore.ProviderID.codex]") is not equal to ("[AIUsageDashboardCore.ProviderID.codex]")
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:98: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown] : XCTAssertEqual failed: ("[]") is not equal to ("[AIUsageDashboardCore.ProviderID.claudeCode]")
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:100: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown] : XCTAssertNil failed: "Utilization(providerID: AIUsageDashboardCore.ProviderID.claudeCode, window: AIUsageDashboardCore.QuotaWindowType.weekly, usedPercent: 30.0, resetAt: Optional(2023-11-16 22:13:20 +0000), plan: nil, confidence: AIUsageDashboardCore.MetricConfidence.providerReported, coverage: AIUsageDashboardCore.UtilizationCoverage.complete, observedAt: Optional(2023-11-14 22:13:20 +0000), windowDuration: nil)"
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:101: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown] : XCTAssertEqual failed: ("[]") is not equal to ("[AIUsageDashboardCore.ProviderID.claudeCode]")
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testS3AnUntrustedNonPeakModelWindowMakesBothRoutesUnknown]' passed (0.001 seconds).
```

### S9: identical account filtering

Commit: `a4f41fc`. The same binding-window filter is applied inside priority, account eligibility and row construction. A Codex non-weekly shell with no percentage cannot count as 100% used while choosing the headline. The headline, public snapshot and first account row agree.

Test: `RoutePlanTests testS9CodexHeadlineAndRowsIgnoreTheSameUncomputableSessionShell`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:117: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS9CodexHeadlineAndRowsIgnoreTheSameUncomputableSessionShell] : XCTAssertEqual failed: ("Optional("codex:b")") is not equal to ("Optional("codex:a")")
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/UtilizationTests/RoutePlanTests.swift:118: error: -[AIUsageDashboardCoreTests.RoutePlanTests testS9CodexHeadlineAndRowsIgnoreTheSameUncomputableSessionShell] : XCTAssertEqual failed: ("Optional("codex:b")") is not equal to ("Optional("codex:a")")
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testS9CodexHeadlineAndRowsIgnoreTheSameUncomputableSessionShell]' passed (0.001 seconds).
```

### S4: restore the shipped MCP guidance

Commit: `1bff7ff`. Restored the complete instructions from dev byte for byte as the existing prefix and appended one get_route paragraph, 330 characters. A static Swift fixture taken from dev checks the complete legacy prefix across all three protocol revisions. The earlier AC3 statement that the whole instructions block is 389 characters is superseded: only the new paragraph must be under 400 characters.

Test: `RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteMCPTests.swift:35: error: -[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter] : XCTAssertTrue failed
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteMCPTests.swift:38: error: -[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter] : XCTAssertTrue failed
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteMCPTests.swift:35: error: -[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter] : XCTAssertTrue failed
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteMCPTests.swift:38: error: -[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter] : XCTAssertTrue failed
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteMCPTests.swift:35: error: -[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter] : XCTAssertTrue failed
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteMCPTests.swift:38: error: -[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter] : XCTAssertTrue failed
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.RouteMCPTests testProtocolRevisionsExposeTheSameRouteAndOptionalAgentFilter]' passed (0.013 seconds).
```

### S5: explain an agent without a flat-rate plan

Commit: `a4f41fc; MCP assertion in 1bff7ff`. A fresh route block with no rows or unknowns for the selected provider now says that provider has no flat-rate plan to route to. Legacy snapshots without route, and stale/unknown data, still explain the missing or stale reading. Exit codes are unchanged.

Test: `RouteCommandTests testS5AgentWithoutAFlatRatePlanExplainsThatRefreshingWillNotHelp`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteCommandTests.swift:56: error: -[AIUsageDashboardCoreTests.RouteCommandTests testS5AgentWithoutAFlatRatePlanExplainsThatRefreshingWillNotHelp] : XCTAssertTrue failed
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/RouteCommandTests.swift:57: error: -[AIUsageDashboardCoreTests.RouteCommandTests testS5AgentWithoutAFlatRatePlanExplainsThatRefreshingWillNotHelp] : XCTAssertFalse failed
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testS5AgentWithoutAFlatRatePlanExplainsThatRefreshingWillNotHelp]' passed (0.175 seconds).
```

### S6: run the real helper check on the Release path

Commit: `46bb33c`. verify-app.sh is called by build-app.sh on the staged Release bundle before notarization. It now sets TOKEI_CLI_BINARY to that bundle's Contents/Helpers/tokei and runs the version gate before signing or GUI checks. The process regression supplies a drifted fixture helper and proves the real verifier rejects it before launch, even with launch skipped. The real Release helper was also built and passed the explicit binary gate.

Test: `CLIVersionProcessTests testS6AppVerificationRunsTheBundledHelperGateBeforeAnyLaunch`.

Red before the fix:

```text
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/CLIVersionProcessTests.swift:35: error: -[AIUsageDashboardCoreTests.CLIVersionProcessTests testS6AppVerificationRunsTheBundledHelperGateBeforeAnyLaunch] : XCTAssertTrue failed - verify-app: app TeamIdentifier=not set hardened_runtime=NO timestamp=NO
/Users/abhayp/wt/lane2/AIUsageDashboard/Tests/CLITests/CLIVersionProcessTests.swift:36: error: -[AIUsageDashboardCoreTests.CLIVersionProcessTests testS6AppVerificationRunsTheBundledHelperGateBeforeAnyLaunch] : XCTAssertFalse failed - version drift must stop before signing or launch checks
```

Green in the expanded compatibility run:

```text
Test Case '-[AIUsageDashboardCoreTests.CLIVersionProcessTests testS6AppVerificationRunsTheBundledHelperGateBeforeAnyLaunch]' passed (0.588 seconds).
```

### Real helper proof for P1 and P3

`RouteMCPTests.testS1AndS3BothToolsReturnTheSameTargetAndModelLimit` now writes snapshots built by the real writer and launches the actual built tokei executable through MCPProcessHarness. It calls both get_route and get_route_recommendation over stdio, asserts the literal expected targets and avoid lists, and verifies the per-model deciding window is retained in the new tool's payload. No installed app was launched or changed.

After changing that test from an in-process server to the real helper, reran the complete touched MCP class:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/RouteMCPTests test
```

Actual output:

```text
Route review real helper: target=claude_code, avoid=[]
Route review real helper: target=codex, avoid=["claude_code"]
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.181 (0.182) seconds
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.181 (0.182) seconds
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.181 (0.183) seconds
** TEST SUCCEEDED **
```

### Compatibility verification and gates

Exact expanded command (all existing Agent, CLI, snapshot, route and utilization classes; not the whole suite):

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/AccountQuotaDecisionTests -only-testing:AIUsageDashboardCoreTests/AgentBurnSnapshotTests -only-testing:AIUsageDashboardCoreTests/AgentCommandProcessTests -only-testing:AIUsageDashboardCoreTests/AgentRecommendationAccountTests -only-testing:AIUsageDashboardCoreTests/AgentRecommendationEngineTests -only-testing:AIUsageDashboardCoreTests/AgentRecommendationReasonTests -only-testing:AIUsageDashboardCoreTests/AgentRouteSnapshotTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotAccountSchemaTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotStalenessTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotWriterTests -only-testing:AIUsageDashboardCoreTests/BurnMCPTests -only-testing:AIUsageDashboardCoreTests/CLIVersionProcessTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/ExtraUsageRoutingTests -only-testing:AIUsageDashboardCoreTests/ForecastForwardCompatibilityTests -only-testing:AIUsageDashboardCoreTests/GuardProcessTests -only-testing:AIUsageDashboardCoreTests/InformationalCreditsTests -only-testing:AIUsageDashboardCoreTests/MCPAccountContractTests -only-testing:AIUsageDashboardCoreTests/MCPServerErrorTests -only-testing:AIUsageDashboardCoreTests/MCPServerExchangeMatrixTests -only-testing:AIUsageDashboardCoreTests/MCPServerMemoryTests -only-testing:AIUsageDashboardCoreTests/MCPServerProcessTests -only-testing:AIUsageDashboardCoreTests/MCPServerTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/ReviewCLIFormatTests -only-testing:AIUsageDashboardCoreTests/ReviewSingleProviderGuardTests -only-testing:AIUsageDashboardCoreTests/RouteCommandTests -only-testing:AIUsageDashboardCoreTests/RouteMCPTests -only-testing:AIUsageDashboardCoreTests/RoutePlanTests -only-testing:AIUsageDashboardCoreTests/RouteTargetPolicyTests -only-testing:AIUsageDashboardCoreTests/SnapshotForecastTests -only-testing:AIUsageDashboardCoreTests/SnapshotReaderTests -only-testing:AIUsageDashboardCoreTests/StatusFormattingTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/WP4MCPTests test
```

```text
Executed 296 tests, with 0 failures (0 unexpected) in 5.956 (6.041) seconds
** TEST SUCCEEDED **
Test Suite 'RoutePlanTests' passed at 2026-11-15 02:36:25.215.
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.014 (0.017) seconds
Test Suite 'RouteCommandTests' passed at 2026-11-15 02:36:25.177.
	 Executed 4 tests, with 0 failures (0 unexpected) in 1.383 (1.385) seconds
Test Suite 'RouteMCPTests' passed at 2026-11-15 02:36:25.198.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.020 (0.021) seconds
Test Suite 'CLIVersionProcessTests' passed at 2026-11-15 02:36:20.905.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.672 (0.672) seconds
```

Release helper and shell validation:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme tokei -configuration Release -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-route build
/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Release/tokei version
# ** BUILD SUCCEEDED **
# tokei 0.12.0
cd /Users/abhayp/wt/lane2
TOKEI_CLI_BINARY=/Users/abhayp/Library/Developer/TokeiWork/dd-route/Build/Products/Release/tokei bash .claude/gates/cli-version-sync.sh
# [cli-version-sync] PASS helper version derives from MARKETING_VERSION (0.12.0)
bash -n AIUsageDashboard/scripts/verify-app.sh
# exit 0
bash .claude/gates/run-all.sh fast
```

Actual fast-gate summary:

```text
PASS  preflight
PASS  no-secret
PASS  no-large-artifact
PASS  no-uncommitted
PASS  cli-version-sync
PASS  format
PASS  lint
[run-all] ALL GATES GREEN
```

Format/lint remain optional-tool SKIP, not executed. Pre-commit hooks passed on all three commits. The worktree is clean. All test/build hc terminals started for this round were removed; no server or watcher was started.

Commits:

```text
46bb33c fix(release): check the bundled helper version before launch
1bff7ff fix(mcp): retain shipped guidance and prove route agreement
a4f41fc fix(route): share constraints and rank spendable capacity
```

### Scope, remaining checks and proof files

- Accepted S6 scope addition touches only `AIUsageDashboard/scripts/verify-app.sh` in the existing Release path and its process regression. The script now normalizes the app path before changing working directory for the gate.
- No new public RoutePlan field or initializer. Existing schema keys/tool inputs remain unchanged. The route deciding-window string may now be perModel when a model ceiling binds an otherwise flat-rate plan. Credits and lifetime balances still do not create recommendations.
- The full app build, positive version check on a newly staged real app bundle, notarization, UI and fresh real-app routing proof remain with integration. The S6 test is deliberately a drifted-helper fixture, and only the standalone Release helper was built here. The release script and notarization service were not run.
- Secscan, prove-red, final cross-model review and work-log remain the orchestrator's gates under worker.md. The failing-before output is retained; no gate was bypassed.
- Retained pressure behavior: a stale/untrusted high reading may still appear in the legacy avoid list, while the new planner reports it unknown. Neither path sends work there. Human spread/ceiling/minimum-provider display gates remain.
- Proof: `~/Library/Developer/TokeiWork/proof/route/r1-{red,green,compat,process,release,fast}.log`. These contain synthetic fixtures and build/test output, no live account usage.
