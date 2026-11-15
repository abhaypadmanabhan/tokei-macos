VERDICT: CHANGES

Reviewer: Claude Opus 5.5, round 1. Read-only: no edits to the worktree. Repros ran in a throwaway copy of HEAD
(`git archive HEAD` into the session scratchpad, plus one probe test file) with its own DerivedData
`~/Library/Developer/TokeiWork/dd-review-route-probe`.

## Findings

S1 [blocker] AIUsageDashboard/AIUsageDashboardApp/Core/Utilization/RoutePlan.swift:81 The "room relative to pace" key mixes two units. A window with a pace scores `elapsed - used`. A window with no pace scores `100 - used`. Cursor's monthly window never has a pace, because Cursor reports no window duration (`CursorUsageParsing.swift:222`). So a nearly used-up Cursor plan outranks an empty Claude plan, on both RoutePlan and `RouteTargetPolicy.agent`. That changes the shipped `get_route_recommendation` answer too: on dev, the least-used rule picked Claude in this case (reading of the removed `trusted.min` line). Repro: probe P1, Cursor monthly 80% used (resets in 20 days) vs Claude weekly 0% used (reset 7 days minus 1 hour) -> `rows=["cursor 20% left ready ...", "claude_code 100% left ready ..."] rec=cursor agent.routeTo=cursor`. Fix: score every row in one unit. For example, when pace is unknown, assume no time has elapsed (score `-used`, the cautious reading of "no data is not headroom"). Add P1 as a table case in RoutePlanTests. It fails today.

S2 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Utilization/RoutePlan.swift:79 "Expiring" headroom is computed one window at a time, with nothing checking the account's other limits. A session window that resets soon puts the plan at the top even when the weekly limit leaves almost nothing to spend. The session's capacity is not really "going unused", because the weekly limit binds first. The only guard is the 85% avoid line. Repro: probe P2, Claude session 0% used (resets in 30 minutes) plus weekly 80% used, vs Codex weekly 0% -> `rows=["claude_code 20% left ready 'Use this plan before unused capacity resets in 30m.'", "codex 100% left ..."] rec=claude_code agent.routeTo=claude_code`. An agent spends Claude's last weekly 20% while Codex is empty. Fix: count expiring capacity only when the tightest plan window still has at least the finder's minimum unused share (25%) left. Equivalently, cap it at `min(remaining)` across the account's plan windows. Add P2 as a test.

S3 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Agent/RouteTargetPolicy.swift:153 / RoutePlan.swift:94 The two tools still disagree whenever a per-model window is the tightest. RoutePlan ranks only plan window types. The policy's peaks include Claude's per-model weekly windows (ClaudeUsageClient.swift:474). Repro: probe P3, Claude weekly 10% plus per-model "Opus" 95% vs Codex weekly 50% -> `get_route` rec=claude_code ("room to spare") while `RouteTargetPolicy.agent` gives `routeTo=nil avoid=["claude_code"]`. An agent calling both tools gets "send to Claude" and "avoid Claude". The AC1 table only compares results when the policy names a target, so this passes. Fix: make one rule own the per-model case. Either rank on the same window set, or mark the row with the per-model limit (avoid, or say so in the reason). Then extend the invariant test so it also checks that `policy.avoid` and `avoid` rows match.

S4 [should] AIUsageDashboard/TokeiCLI/MCPServer+Instructions.swift:6 AC3 asks the instructions to say when to call get_route, in under 400 characters. 0.12.0's precedent (patch bible 2026-11-14, line 158) was "instructions gain one paragraph". Instead, about 2,000 characters of existing trust rules were deleted for every client:
- the `stale` vs per-window `observedAt` distinction
- "a low number you do not trust is NOT free capacity"
- the full `quota.status` meaning
- "if stale, say so instead of presenting numbers as current"
- the triggers for get_usage

The existing test still passes only because the new text keeps its five keywords. This is outside the smallest change, and it changes what every connected agent is told. Reading (no runtime repro; `git diff dev...HEAD -- AIUsageDashboard/TokeiCLI/MCPServer+Instructions.swift`). Fix: restore the 0.12.0 text, add one get_route paragraph under 400 characters, and test that paragraph's length rather than the whole block's.

S5 [nit] AIUsageDashboard/TokeiCLI/RouteFormatting.swift:66 `get_route` with `for` set to an agent that has no flat-rate plan (cline, gemini, opencode) answers "No fresh plan recommendation is available. Refresh Tokei before routing work." Refreshing will never change that answer. Fix: when the snapshot is fresh and the provider has no route row and no unknown row, say the agent has no flat-rate plan to route to.

S6 [nit] .claude/gates/cli-version-sync.sh:20 The check on the real built binary runs only when TOKEI_CLI_BINARY is set, and nothing sets it: run-all, the release script and CI all skip it. The static checks do fail on a hardcoded string or a literal plist value (verified). Fix: have release.sh, or the Release build gate, set TOKEI_CLI_BINARY to the product it just built.

S7 [nit] AIUsageDashboard/TokeiCLI/main.swift:16 If a build ever lacks the embedded plist, `preconditionFailure` crashes `tokei version` and the MCP `serverInfo`. Today the gate guards this through project.yml. A fallback such as "unknown" would degrade more gently. That said, the brief wanted no second version string, so this is optional.

S8 [nit] AIUsageDashboard/TokeiCLI/RouteFormatting.swift:51 The helper passes any plain-text `reason` from the snapshot file (up to 160 characters) straight to the agent. Labels are limited to 48 plain characters, so short plain-word injection text in a window or account label can still reach an agent. This matches the spec ("same sanitising as window labels") and the burn tool's existing exposure. Optional: rebuild the reason from the row's fields, or from a fixed set of sentences, instead of echoing it.

S9 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Agent/AccountQuotaDecision.swift:95 The headline account is ranked over the raw `account.quotaWindows`. RoutePlan.make ranks over windows after its Codex-only filter (RoutePlan.swift:104), which drops non-weekly windows with no percentage. `priority` scores such a window as 100% used. So for a Codex account carrying one, the headline and RoutePlan's first Codex row can differ. Reading. Fix: give both callers the same filtered window list.

## Approved scope addition: optional `Utilization.windowDuration`

Approve. The field is optional with a nil default, so existing initializers compile unchanged. Synthesized Codable decodes older `utilization-cache.json` entries that lack the key, and the author's test proves both the decode and a write/reload round trip. The field reaches the policy through UtilizationEngine, AgentSnapshotWriter and AccountQuotaDecision. It is needed: the policy only receives `[Utilization]` and must rebuild windows to share RoutePlan's comparator. Without the field, a monthly window with a reported duration ranks differently on the two paths (the author's red test shows this). The `Equatable` change it brings has no caller-visible effect that I found. It does not fix S1: Cursor still reports no duration.

## What holds (checked)

- Snapshot: `route` is optional and additive. Existing keys and schema version are unchanged. Old snapshots without `route` decode (AgentRouteSnapshotTests). Expiry copies keep `route`.
- MCP: the existing three tools keep their names, input schemas, descriptions and output schemas. The tools/list in the author's transcript matches dev except for the fourth tool. `get_route` is tested across all three protocol revisions, with outputSchema and structuredContent only on 2025-06-18. Bad `for` and unknown arguments return -32602. The missing-snapshot error contains no path.
- CLI: exit codes 0/1/69/64 are distinct, documented in help, and match `tokei guard`. A stale or older-app snapshot gives 69. Duplicate or unknown arguments give 64.
- Labels: emails, slashes, control characters and anything over 48 characters fall back to "account N" or "account". Row IDs carry no account IDs or paths. Provider names come from a fixed table.
- Pay-per-token and credit balances: no plan window means no row (credits, per-model and lifetime are excluded). Nothing points at credits or overage.
- Readings over 100% are clamped by `UtilizationEngine.usedPercent` and show as avoid. A window resetting in 20 seconds ranks first with "<1m" and its row expires at the reset (probe P4). That is harmless.
- Version: Debug and Release `tokei version` both print `tokei 0.12.0` from MARKETING_VERSION. The gate fails on a literal plist value. With TOKEI_CLI_BINARY set, it fails on a drifted binary.

## Commands run (exit codes)

1. `cd AIUsageDashboard && xcodegen generate` -> 0
2. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-route -only-testing:AIUsageDashboardCoreTests/{RoutePlanTests,RouteTargetPolicyTests,AccountQuotaDecisionTests,AgentRouteSnapshotTests,AgentSnapshotWriterTests,AgentSnapshotAccountSchemaTests,RouteCommandTests,RouteMCPTests,MCPServerTests,MCPServerExchangeMatrixTests,CLIVersionProcessTests,MCPAccountContractTests,MCPServerProcessTests,BurnMCPTests,UtilizationCacheTests,UtilizationEngineTests,SnapshotReaderTests,AgentSnapshotStalenessTests} test` (one invocation, each class passed with its own `-only-testing:` flag) -> 0. `Executed 158 tests, with 0 failures`, `** TEST SUCCEEDED **`
3. Probe (scratch copy of HEAD plus `ReviewProbeTests.swift`): `xcodegen generate && xcodebuild … -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-route-probe -only-testing:AIUsageDashboardCoreTests/ReviewProbeTests test` -> 0 (the probe prints results without asserting). Output lines P1-P4 are quoted above.
4. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme tokei -configuration Release -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-route build` -> 0. `…/Release/tokei version` -> `tokei 0.12.0`, exit 0. `…/Debug/tokei version` -> `tokei 0.12.0`, exit 0.
5. `bash .claude/gates/cli-version-sync.sh` -> 0 (PASS). The same with `TOKEI_CLI_BINARY=<Release tokei>` -> 0.
6. In the scratch copy with MARKETING_VERSION set to 0.13.0: the gate with TOKEI_CLI_BINARY set -> 1 (`built helper reports tokei 0.12.0; expected tokei 0.13.0`). The gate without it -> 0. With the plist key set to the literal "0.12.0" -> 1 (`helper version must use MARKETING_VERSION`).

## Not checked

- The live snapshot run (AC6). I did not rerun it; the author's transcript was read, not reproduced. I did not launch, copy or quit the installed app.
- The full suite, `run-all.sh fast`, secscan and prove-red belong to the orchestrator.
- Whether the app's bundled copy of the helper (the copy step inside Tokei.app) carries the embedded plist. Only the standalone tool products were built.
