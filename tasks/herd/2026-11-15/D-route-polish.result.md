STATUS: READY

# WP-D: Route CLI copy

Branch: `patch/2026-11-15/route-polish`
Worktree: `/Users/abhayp/wt/lane1`
Commit: `c1c2bb4093cb8743c069cd9f3e5508e63d5b22b8` — `fix(cli): make route output use plain language`

## Changed

- `AIUsageDashboard/TokeiCLI/RouteFormatting.swift`: Human output names windows and pace in plain words, omits the ready suffix, retains avoid, and renders minute/hour/day countdowns. The headline uses the current render clock and reuses the row's countdown when the deciding and expiring windows match. Different windows retain their own correct times.
- `AIUsageDashboard/Tests/CLITests/RouteCommandTests.swift`: Five regression/compatibility tests cover all window types, model labels, raw labels, countdown buckets, saved-headline drift, different deciding/expiring windows, pace states, avoid, and exact JSON bytes both in-process and through the built CLI.

No Core, snapshot, MCP, command parsing, exit-code, or JSON field changes. The render clock is explicitly excluded from encoding.

## Scope clarification

The existing MCP text content is encoded JSON, which includes machine enums. I flagged the conflict between removing enums from MCP text and the frozen JSON/MCP contracts. Orchestrator `t1d` confirmed: “CLI renderer only; MCP content and all JSON stay byte-identical; note MCP prose unchanged.” A small CLI-local countdown helper was also approved because the app's `BurnCopy` helper is not compiled into the standalone CLI. MCP prose remains unchanged.

## Acceptance checks: red then green

Red was run before changing the formatter, against base `1f452de`, with the first four added tests. Full output: `/Users/abhayp/Library/Developer/TokeiWork/d-route-red.log`.

1. Window names: `testHumanWindowNamesNeverExposeEnumNames`.

   ```text
   RED: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testHumanWindowNamesNeverExposeEnumNames]' failed (0.006 seconds).
   GREEN: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testHumanWindowNamesNeverExposeEnumNames]' passed (0.001 seconds).
   ```

2. Countdown words and headline consistency: `testHumanCountdownUsesCompactWordsAndOneCurrentValue`. Covers `1 min`, `42 min`, `1 h`, `18 h`, `47 h`, `2 d`, `12 d`, and a saved 42-minute reason read 61 seconds later. The distinct-window case additionally confirms a 42-minute expiring window does not overwrite an 18-hour deciding window.

   ```text
   RED: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testHumanCountdownUsesCompactWordsAndOneCurrentValue]' failed (0.650 seconds).
   GREEN: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testHumanCountdownUsesCompactWordsAndOneCurrentValue]' passed (0.001 seconds).
   ```

3. Pace and disposition: `testHumanPaceAndAvoidUsePlainWordsWithoutReadySuffix`.

   ```text
   RED: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testHumanPaceAndAvoidUsePlainWordsWithoutReadySuffix]' failed (0.005 seconds).
   GREEN: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testHumanPaceAndAvoidUsePlainWordsWithoutReadySuffix]' passed (0.001 seconds).
   ```

4. JSON compatibility: `testJSONBytesRemainTheOriginalRouteContract` compares an explicit original byte fixture before and after rendering; it passed on both old and new code, as required for unchanged behavior. `testProcessJSONBytesRemainTheOriginalRouteContract` additionally compares the real `route --json` process output, including its newline, against an explicit original byte fixture. Its fixture has no reset date so wall-clock drift cannot change the expected bytes.

   ```text
   BASELINE: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testJSONBytesRemainTheOriginalRouteContract]' passed (0.001 seconds).
   GREEN: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testJSONBytesRemainTheOriginalRouteContract]' passed (0.001 seconds).
   GREEN: Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testProcessJSONBytesRemainTheOriginalRouteContract]' passed (0.085 seconds).
   ```

The three changed-behavior tests produced 35 failed assertions before the fix. The byte-preservation requirement is intentionally green on old code.

## Verification command and output

Ran `xcodegen generate` in `AIUsageDashboard/` first. The red command selected `RouteCommandTests` only. Final command:

```sh
xcodebuild test \
  -project AIUsageDashboard/AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardCore \
  -destination 'platform=macOS' \
  -derivedDataPath ~/Library/Developer/TokeiWork/dd-polish \
  -only-testing:AIUsageDashboardCoreTests/RouteCommandTests \
  -only-testing:AIUsageDashboardCoreTests/RouteMCPTests \
  -only-testing:AIUsageDashboardCoreTests/StatusFormattingTests \
  -only-testing:AIUsageDashboardCoreTests/ReviewCLIFormatTests
```

Full final output: `/Users/abhayp/Library/Developer/TokeiWork/d-route-final-tests-v2.log`.

```text
RouteCommandTests: Executed 9 tests, with 0 failures (0 unexpected)
RouteMCPTests: Executed 3 tests, with 0 failures (0 unexpected)
StatusFormattingTests: Executed 16 tests, with 0 failures (0 unexpected)
ReviewCLIFormatTests: Executed 2 tests, with 0 failures (0 unexpected)
Executed 30 tests, with 0 failures (0 unexpected) in 1.802 (1.813) seconds
** TEST SUCCEEDED **
```

After committing, ran `BASE_REF=HEAD~1 bash .claude/gates/run-all.sh fast` (exit 0). Full output: `/Users/abhayp/Library/Developer/TokeiWork/d-route-fast-gates.log`.

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

The format and lint entries are optional-tool skips: `swiftformat` and `swiftlint` are not installed. `git diff --check` passed; pre-commit gates ran normally; lane worktree is clean.

## Built CLI and MCP proof

Ran the built `dd-polish/Build/Products/Debug/tokei` against a fictional snapshot through `TOKEI_SNAPSHOT_PATH`. The snapshot was deliberately generated 61 seconds earlier with a saved 42-minute reason. Actual human output:

```text
Send the next task to Codex. Use this plan before unused capacity resets in 41 min.
Codex: 62% left · 5-hour window · resets in 41 min · under pace
Cursor: 66% left · monthly window · resets in 12 d · under pace
```

```text
Built CLI --json: exit 0; valid JSON; original machine vocabulary and saved advice retained
Built MCP initialize + tools/list + get_route: exit 0; original JSON text contract retained
```

Proof files are outside git under `/Users/abhayp/Library/Developer/TokeiWork/proof/route-polish/`: `snapshot.json`, `route-human.txt`, `route.json`, `mcp.jsonl`.

## Not checked, risks, handoff

- No live personal snapshot, full app launch, or full suite; the lane proof used the real built CLI/MCP with fictional data.
- SwiftFormat and SwiftLint were unavailable. Repo-wide secscan, prove-red wrapper, cross-model review, feature-map/work-log updates, and release gates remain with the orchestrator per worker rules. Actual pre-fix red output is retained above.
- No public contract additions. Snapshot route and MCP JSON/prose remain unchanged by agreement; this intentionally leaves their existing machine enum names and saved reason intact.
- Rollback: revert `c1c2bb4093cb8743c069cd9f3e5508e63d5b22b8`.
- All five hc test/gate terminals started by this worker were removed. No dev servers were started; the built MCP process exited normally. Listener inspection found no test/CLI/MCP listener belonging to this work.
- Learned: recorded L1055 about explicitly including `schemaVersion` in hand-written AgentSnapshot JSON fixtures.
- Waits on `t1d` to rerun the checks, review, scan, and integrate the commit. No merge, push, PR, deploy, or paid call was made.
