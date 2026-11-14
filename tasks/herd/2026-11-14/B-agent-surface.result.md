STATUS: READY

Review r1 fixes are complete in 502b80a and 05ee62d. All 11 accepted findings are fixed; the requested 14 reviewed test classes plus the new review class passed in one final invocation (118 tests). The real default-environment Claude/Codex connect/readback/removal proof passes. AC7 GUI proof remains owned by the orchestrator per B-fix-r1.md and is not a lane blocker; no UI proof is claimed here. Ready for the next review/integration step, not a claim of release completion.

Brief integrity: `shasum -a 256 /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/B-agent-surface.brief.md` returned `337b6e4ce3524f28d48a0ff30d034f9fd42e8db3cf9f03ca4bd3b67f9b35a014`, matching the request before the brief was read. Scope: WP-B and the schema document's registration §7. No edits to Core/Game, Core/Sync, notifications, or other UI files; SettingsDrawer has exactly one added include line. README was updated as explicitly required by AC8. No dependencies, credentials, real client configuration writes, push, merge, or release.

Worktree: `/Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface`
Branch: `patch/2026-11-14/agent-surface`
Proof directory: `/Users/abhayp/Library/Developer/TokeiWork/proof/agent-surface/`

## Review r1 fixes

Source: `B-fix-r1.md` and `B-review-r1.md` in the main run directory. Fixed only S1, S2, S3, S4 and accepted nits S5, S6, S7, S9, S10, S12, S13. Declined S8, S11, S14 and S15 remain untouched. No new dependencies, app launch, client config changes in Abhay's real home, or edits to other lanes.

Commits:

```text
502b80a fix(agents): preserve client configuration and registration scope
05ee62d fix(mcp): preserve legacy arguments and report burn availability
```

ID → commit → regression check (all paths below are under AIUsageDashboard/Tests):

| ID | Fix and commit | Check |
| --- | --- | --- |
| S1 | 502b80a: preserve the supplied environment; remove injected profile variables and the Codex-directory workaround | `AgentConnectionReviewTests.testS1AbsentProfileVariablesStayAbsentInChildren`; explicit-profile control; `AgentConnectionTests.testClientOwnsExplicitCodexDirectoryCreation`; real temp-HOME default-environment proof below |
| S2 | 502b80a: resolve Cursor's configuration link once, stage beside the target, rename the target, preserve the link, back up original bytes in a regular owner-only file; exclusive no-follow file creation replaces chmod-through-link behavior | `AgentConnectionReviewTests.testS2CursorSymlinkAndIndependentByteBackupSurvive` checks a relative link, target update, regular independent backup and later uninstall |
| S3 | 502b80a: refuse any different existing Cursor tokei entry, preserving its bytes and prior backup; 05ee62d updates schema doc §7 | `AgentConnectionReviewTests.testS3DifferentCursorRegistrationAndExistingBackupAreKept` |
| S4 | 502b80a: Claude matches only user scope; local/project registrations are not called user-connected and uninstall gives the matching scoped removal command without attempting a user removal | `AgentConnectionReviewTests.testS4ClaudeLocalScopeIsNotUserConnectedOrRemoved` checks the local removal instruction, unchanged registration and no remove subprocess |
| S5 | 502b80a: only the two client-specific no-MCP-server phrases mean missing; a generic configuration-file-not-found error stays an error | `AgentConnectionReviewTests.testS5ConfigNotFoundIsAnErrorRatherThanDisconnected` |
| S6 | 502b80a: child PATH begins with the found binary directory and fallback directories, followed by the inherited PATH | `AgentConnectionReviewTests.testS6FoundBinaryAndFallbackDirectoriesLeadChildPATH` with a fake local-bin client and GUI-like inherited PATH |
| S7 | 502b80a: Cursor serialization uses `.withoutEscapingSlashes` | `AgentConnectionReviewTests.testS7CursorJSONKeepsReadableSlashes` |
| S9 | 502b80a: shared Connect/command-install path refuses `/Volumes/` and `/AppTranslocation/` helper paths with the requested Applications recovery sentence | `AgentConnectionReviewTests.testS9TemporaryAppLocationsCannotConnectOrInstall` checks both paths and both actions; no configuration is written |
| S10 | 502b80a: Settings passes `includePATHHint: false`; terminal installs retain their conditional PATH hint | `AgentConnectionReviewTests.testS10SettingsInstallOmitsShellPATHHint`; app build compiles the Settings caller; GUI click proof remains orchestrator-owned |
| S12 | 05ee62d: only install/uninstall select MCP configuration mode; other extra arguments retain the old stdio server behavior | `AgentCommandProcessTests.testS12LegacyExtraMCPArgumentsStillRunTheServer`; real stdio extra-argument exchange below |
| S13 | 05ee62d: additive `available` is false for a missing burn block, true when present | `BurnMCPTests.testS13MissingBurnBlockIsUnavailableRatherThanEmptyCapacity`; real absent-block response below |

Failing-first proof: added the review tests and ran only the new review class plus the new S12 and S13 methods before applying the behavior fixes. All 11 accepted IDs had a failing test; the explicit-profile pass-through control already passed. `includePATHHint`'s call signature was introduced for this first test with its old hint behavior, then implemented with the fix. The red log records 12 executed tests, 31 failed assertions (including a missing-file assertion after the old local-scope uninstall deleted the stub registration), and `** TEST FAILED **`. It is retained at `r1/failing-first.log`. No failing test was skipped. The old Codex-directory-creation test was replaced because the requested S1 fix removes that wrong-directory workaround.

The sole final targeted rerun was:

```sh
cd /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface -only-testing:AIUsageDashboardCoreTests/AgentBurnSnapshotTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotWriterTests -only-testing:AIUsageDashboardCoreTests/BurnMCPTests -only-testing:AIUsageDashboardCoreTests/MCPServerTests -only-testing:AIUsageDashboardCoreTests/MCPAccountContractTests -only-testing:AIUsageDashboardCoreTests/MCPServerProcessTests -only-testing:AIUsageDashboardCoreTests/AgentConnectionTests -only-testing:AIUsageDashboardCoreTests/MCPServerErrorTests -only-testing:AIUsageDashboardCoreTests/MCPServerExchangeMatrixTests -only-testing:AIUsageDashboardCoreTests/SnapshotReaderTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotStalenessTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotAccountSchemaTests -only-testing:AIUsageDashboardCoreTests/ForecastForwardCompatibilityTests -only-testing:AIUsageDashboardCoreTests/AgentCommandProcessTests -only-testing:AIUsageDashboardCoreTests/AgentConnectionReviewTests test
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface build
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme tokei -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface build
BASE_REF=a4a8894 bash .claude/gates/run-all.sh fast
/Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface
```

Output (current evidence under `/Users/abhayp/Library/Developer/TokeiWork/proof/agent-surface/r1/`):

```text
targeted-tests.log: Executed 118 tests, with 0 failures (0 unexpected)
targeted-tests.log: ** TEST SUCCEEDED **
app-build.log: ** BUILD SUCCEEDED **
cli-build.log: ** BUILD SUCCEEDED **
[no-secret] PASS no secrets detected
[no-uncommitted] PASS no uncommitted changes in /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface
[cli-version-sync] PASS TokeiCLI.version matches MARKETING_VERSION (0.11.0)
[format] SKIP swiftformat not installed (brew install swiftformat)
[lint] SKIP swiftlint not installed (brew install swiftlint)
[run-all] ALL GATES GREEN
VERDICT: PASS
```

Current security scan: VERDICT PASS; FLAG lines: none; GAP lines: none. Both fix commits ran the normal pre-commit hook without bypasses. Formatting/lint tools were not installed, so those gates explicitly skipped. No whole-suite rerun was performed.

Real client proof (S1): `python3 .scratch/agent-surface/r1/prove-default-home.py`, also copied to `r1/prove-default-home.py`. It creates an isolated HOME, symlinks only the installed client executables into its `.local/bin`, and executes every command through `env -i` with only HOME, PATH, TMPDIR and a synthetic TOKEI_SNAPSHOT_PATH. **Neither CLAUDE_CONFIG_DIR nor CODEX_HOME is set.** It installs each client, repeats installation, queries the client directly with that same normal HOME, uninstalls, and confirms a subsequent client query reports no server. No real configuration was read directly or modified. The script verifies only existence of the temporary default Claude configuration file, not its contents.

Exact commands and complete outputs, including all environment values, are in `r1/temp-home-default-environment.txt`. Key output:

```text
Claude Code: connected tokei (/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp).
Claude Code: tokei is already connected; no change.
  Scope: User config (available in all your projects)
  Status: ✔ Connected
  Command: /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei
  Args: mcp
Claude Code: disconnected tokei.
No MCP server named "tokei". Run `claude mcp add` to add one.
Codex: connected tokei (/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp).
Codex: tokei is already connected; no change.
Codex: disconnected tokei.
Error: No MCP server named 'tokei' found.
PASS: both real clients install, repeat, default-environment get and uninstall.
```

The direct successful `claude mcp get tokei` ran from the isolated HOME with both profile variables unset. Its normal `~/.claude.json` exists and `~/.claude/.claude.json` does not. Codex's direct `mcp get tokei --json` confirmed the exact helper command and `["mcp"]` arguments, with enabled true and no custom environment. This supersedes the initial proof below, which used explicit profile variables and did not catch S1.

Manual MCP proof (S12/S13): newline JSON-RPC ping and burn calls to `.../Debug/tokei mcp --legacy-extra ignored`, using `r1/mcp-compat-fixture.json`. Output is retained in `r1/mcp-compat-exchange.jsonl` and `r1/mcp-compat-summary.txt`:

```text
Legacy extra arguments: ping returned id 42, result {}.
Absent burn block: {"available":false,"expiring":[],"generatedAt":"2026-11-14T10:10:58Z","stale":false}
Text bytes: 84
```

The initial byte table below is historical. S13 adds the availability field; the current minimal fresh absent-block burn payload is 84 text bytes rather than the initial 66. Full usage and route output schemas are unchanged by this round; schemaVersion remains 1.

Cleanup: both temporary registrations were removed. No app was launched and no proof lock was taken in this round. No server/watcher was started. `pgrep` for this lane's built helper returned no process; `lsof -nP -iTCP -sTCP:LISTEN` is recorded in `r1/listeners.txt`. The temporary HOME and proof artifacts are retained for review. Roll back r1 with `git revert 05ee62d` then `git revert 502b80a`; no real-home client changes need rollback.

AC7 screenshots/actions, game call-site wiring and the next cross-family review remain with the orchestrator. STATUS is READY as directed by the r1 fix ledger, not a claim that those integration responsibilities are complete.

## Initial delivery evidence (historical, before review r1)

The following original checks and measurements are retained for traceability. The r1 section above supersedes their default-environment registration proof, Codex-directory workaround, and missing-burn response. Original GUI attempts are historical only; no retry was made in this round.

## Check commands and output

Commands ran from the worktree root except XcodeGen's first invocation, which ran in `AIUsageDashboard/`. These are the exact targeted build/test invocations (output redirected to the named logs):

```sh
cd /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface/AIUsageDashboard
xcodegen generate
cd /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface -only-testing:AIUsageDashboardCoreTests/AgentBurnSnapshotTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotWriterTests -only-testing:AIUsageDashboardCoreTests/BurnMCPTests -only-testing:AIUsageDashboardCoreTests/MCPServerTests -only-testing:AIUsageDashboardCoreTests/MCPAccountContractTests -only-testing:AIUsageDashboardCoreTests/MCPServerProcessTests -only-testing:AIUsageDashboardCoreTests/AgentConnectionTests -only-testing:AIUsageDashboardCoreTests/MCPServerErrorTests -only-testing:AIUsageDashboardCoreTests/MCPServerExchangeMatrixTests -only-testing:AIUsageDashboardCoreTests/SnapshotReaderTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotStalenessTests -only-testing:AIUsageDashboardCoreTests/AgentSnapshotAccountSchemaTests -only-testing:AIUsageDashboardCoreTests/ForecastForwardCompatibilityTests test
xcodegen generate --spec AIUsageDashboard/project.yml
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface -only-testing:AIUsageDashboardCoreTests/AgentConnectionTests -only-testing:AIUsageDashboardCoreTests/AgentCommandProcessTests test
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme tokei -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface build
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface build
bash .claude/gates/run-all.sh fast
BASE_REF=dev bash .claude/gates/run-all.sh fast
/Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface
git diff --check
```

Output:

```text
targeted-tests.log: Executed 103 tests, with 0 failures (0 unexpected)
targeted-tests.log: ** TEST SUCCEEDED **
connect-tests.log: Executed 11 tests, with 0 failures (0 unexpected)
connect-tests.log: ** TEST SUCCEEDED **
cli-build.log: ** BUILD SUCCEEDED **
app-build.log: ** BUILD SUCCEEDED **
[no-secret] PASS no secrets detected
[no-uncommitted] PASS no uncommitted changes in /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface
[cli-version-sync] PASS TokeiCLI.version matches MARKETING_VERSION (0.11.0)
[format] SKIP swiftformat not installed (brew install swiftformat)
[lint] SKIP swiftlint not installed (brew install swiftlint)
[run-all] ALL GATES GREEN
VERDICT: PASS
```

Security scan: VERDICT PASS; no FLAG lines; no GAP lines. Both commits ran the real pre-commit hook without bypasses. The branch-wide fast pass used `BASE_REF=dev`, so the no-secret gate examined the change rather than an empty staged diff. Compiler warnings in untouched provider/parser/chart sources remain outside this lane; no claim of a warning-free repository or a Swift 6 migration. The full suite and release build were not run; the orchestrator owns integration verification.

## AC1 — Additive burn snapshot: PASS

Added Foundation-only `AgentBurn`, window, streak, today and goal shapes in the shared schema source; schema version remains 1. Writer APIs accept optional `burn: BurnSnapshot? = nil`. Expiring windows always come from the shared finder over the provider snapshots, not a potentially old game snapshot. Game totals are only present when passed. Recommendation expiry and provider filtering preserve the appropriate burn data.

Check: `AgentBurnSnapshotTests` (4 tests), `AgentSnapshotWriterTests` (12 tests), plus old-snapshot/account/forecast compatibility classes in the 103-test command above. Output includes `Executed 4 tests, with 0 failures` and `Executed 12 tests, with 0 failures`. Tests cover old JSON without burn, per-account order without headline duplication, excluded credits/stale/ineligible accounts, optional game data persisted to disk, and preservation across recommendation expiry. Proof: `targeted-tests.log`.

## AC2 — get_burn_opportunities: PASS

Added the third tool, title `Use it or lose it`, with read-only/idempotent/closed-world annotations. Output contains `generatedAt`, `stale`, and soonest-first `expiring` rows with plain advice. The helper suppresses passed resets, old/future readings, unsupported paid window types and stale snapshots. Instructions say to check before optional/batch/exploratory work and never spend credits or paid overage.

Check: `BurnMCPTests` (5 tests) and `MCPServerProcessTests` (2 tests) in the targeted command. A real stdio helper process lists 3 tools and reads a fixture. Manual built-helper stdin exchange also passed; proof `cli-smoke.txt`:

```text
stdio tools/list: 3 tools
Codex 5-hour window has 62% left and resets in 41 min: run optional or batch work there first
```

The manual exchange sent newline-delimited `tools/list` and `tools/call` JSON-RPC requests to `/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp`, with `TOKEI_SNAPSHOT_PATH=/Users/abhayp/Library/Developer/TokeiWork/proof/agent-surface/burn-cli-fixture.json`. The fixture is synthetic, not a claim about this Mac's current headroom.

## AC3 — Efficient payloads and compatibility: PASS

Added optional `detail: "summary"` to get_usage, yielding metadata plus `{id, summary}` provider rows. With detail absent, the existing full shape remains intact. Existing encoding already omitted nil values; required empty arrays remain rather than breaking consumers. Filtered usage omits cross-provider game totals. Summary is reporting information, not executable account routing.

Measured both binaries against the same captured live Mac snapshot. The baseline binary was compiled before edits with:

```sh
swiftc AIUsageDashboard/TokeiCLI/*.swift AIUsageDashboard/AIUsageDashboardApp/Core/Agent/AgentSnapshot.swift -o .scratch/agent-surface/tokei-before
```

Both helpers received identical newline tools/call requests and `TOKEI_SNAPSHOT_PATH=/Users/abhayp/Library/Developer/TokeiWork/proof/agent-surface/live-snapshot.json`. Measurement used UTF-8 byte lengths for the first text block, compact-JSON result object, and exact emitted JSON-RPC line including its newline. Proof: `mcp-bytes.json`; captured input is owner-only `live-snapshot.json`.

| Tool | Text before | Text after | Result before | Result after | Wire before | Wire after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| get_usage, default | 4051 | 4051 | 8664 | 8664 | 8759 | 8759 |
| get_usage, summary | unsupported | 742 | unsupported | 1636 | unsupported | 1671 |
| get_route_recommendation | 381 | 381 | 880 | 880 | 921 | 921 |
| get_burn_opportunities | unsupported | 66 | unsupported | 216 | unsupported | 251 |

Summary cuts usage text by 81.7% on this input. The captured live input came from the existing app and has no burn block; the new burn tool therefore returned an empty list in this size comparison. A refreshed new-writer snapshot adds its optional burn data; this table does not claim that data is free. The nonempty synthetic stdio exchange is separately proven under AC2. Check: absent-detail decode and smaller summary assertions in `BurnMCPTests`, existing MCP compatibility/error/matrix tests, and updated schema docs.

## AC4 — MCP install/uninstall: PASS

Shared `Core/Connect/AgentConnection.swift` is compiled directly into the helper and into Core. Claude uses `mcp add --scope user tokei -- <absolute-helper> mcp`; Codex uses `mcp add tokei -- <absolute-helper> mcp`; both read back the result. Literal argv handles spaces/quotes without a shell. Matching registrations are no-ops; different Claude/Codex registrations are preserved and require explicit disconnect. Cursor merges other keys/servers, refuses malformed JSON, backs up once, and writes atomically with owner-only permissions. Client processes have a timeout and diagnostic output is not exposed.

Before implementation, this Mac's `codex mcp --help`, `codex mcp add --help`, and `codex mcp get --help` confirmed `add NAME -- COMMAND...` and `get NAME --json`. No real registration was made during that inspection.

Tests: fake HOME, fake CLAUDE_CONFIG_DIR/CODEX_HOME, stub clients on fake PATH; 9 `AgentConnectionTests` plus 2 `AgentCommandProcessTests`, all passing in the 11-test command. Test assertions verify exact argv, repeated install/uninstall, other-server preservation, invalid JSON retained byte-for-byte, backup retained, permissions, and dry-run executing no client.

Live real-home command (dry-run only):

```sh
/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp install --client all --dry-run
```

Output (`live-dry-run.txt`):

```text
Would run: /Users/abhayp/.local/bin/claude mcp add --scope user tokei -- /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp
Would run: /opt/homebrew/bin/codex mcp add tokei -- /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp
Would register tokei in /Users/abhayp/.cursor/mcp.json: /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp.
```

Real writes used only this isolated environment, with PATH inherited solely to locate installed client binaries:

```sh
proof_home=/Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface/.scratch/agent-surface/real-client-home
helper=/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei
# Each following command ran with HOME and CFFIXED_USER_HOME set to proof_home,
# CLAUDE_CONFIG_DIR=proof_home/fake-claude, CODEX_HOME=proof_home/fake-codex,
# XDG_CONFIG_HOME=proof_home/.config, and a synthetic TOKEI_SNAPSHOT_PATH.
"$helper" mcp install --client claude
"$helper" mcp install --client claude
"$helper" mcp uninstall --client claude
"$helper" mcp install --client codex
"$helper" mcp install --client codex
"$helper" mcp uninstall --client codex
"$helper" mcp install --client cursor
"$helper" mcp uninstall --client cursor
```

Successful output lines (`temp-home-connect.txt`, `temp-home-connect-fixed.txt`):

```text
$ tokei mcp install --client claude
Claude Code: connected tokei (/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp).
exit 0

$ tokei mcp install --client claude
Claude Code: tokei is already connected; no change.
exit 0

$ tokei mcp uninstall --client claude
Claude Code: disconnected tokei.
exit 0

$ tokei mcp install --client codex
Codex: connected tokei (/Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei mcp).
exit 0

$ tokei mcp install --client codex
Codex: tokei is already connected; no change.
exit 0

$ tokei mcp uninstall --client codex
Codex: disconnected tokei.
exit 0

$ tokei mcp install --client cursor
Cursor: connected tokei in /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface/.scratch/agent-surface/real-client-home/.cursor/mcp.json.
exit 0

$ tokei mcp uninstall --client cursor
Cursor: disconnected tokei in /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface/.scratch/agent-surface/real-client-home/.cursor/mcp.json.
exit 0
```

The first Codex attempt reproduced `Error: failed to resolve CODEX_HOME` because the temporary directory was absent. Fixed the code to create the empty Codex configuration directory with mode 0700 only for explicit install. Detection, uninstall of an absent config, and dry-run do not create it. `testFreshCodexHomeIsPreparedOnlyOnInstall` locks this in; the next real Codex attempt passed. The original failure log is retained rather than hidden. No real home client config was modified.

## AC5 — tokei install: PASS

Creates ~/.local/bin and an absolute helper symlink; matching link is unchanged. Different file/link requires --force; a directory is never replaced. The replacement is a sibling symlink renamed atomically. PATH hint is printed when needed.

Check: `testInstallCommandRefusesOtherTargetsAndForceReplacesOnlyFile` in the 9-test connection class. Real command in the same isolated environment: `"$helper" install`, repeated. Proof `temp-home-connect-fixed.txt`:

```text
$ tokei install
Installed /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface/.scratch/agent-surface/real-client-home/.local/bin/tokei → /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei.
Add ~/.local/bin to PATH in your shell settings: export PATH="$HOME/.local/bin:$PATH"
exit 0

$ tokei install
tokei command is already installed; no change.
Add ~/.local/bin to PATH in your shell settings: export PATH="$HOME/.local/bin:$PATH"
exit 0
```

## AC6 — tokei burn: PASS

Prints up to 8 expiring rows with a count of further rows, optional streak/today/goal/progress, a stale-data recovery message, and the flat-rate-only rule. Old snapshots remain readable and do not invent capacity.

Check: formatting assertions in `BurnMCPTests`. Actual built-helper command:

```sh
TOKEI_SNAPSHOT_PATH=/Users/abhayp/Library/Developer/TokeiWork/proof/agent-surface/burn-cli-fixture.json /Users/abhayp/Library/Developer/TokeiWork/dd-agent-surface/Build/Products/Debug/tokei burn
```

Output (`cli-smoke.txt`):

```text
Use it or lose it
Codex 5-hour window has 62% left and resets in 41 min: run optional or batch work there first
Streak: 7 days · today's goal hit
Today: $12.50 API-equivalent value · goal $10.00 · 125%
Use capacity already in your plan. Never buy credits or overage to burn it.
```

## AC7 — Settings Connect agents: ORCHESTRATOR-OWNED

Implemented the self-contained AgentConnectSection and exactly one include line at the top of SettingsDrawer. Each client has detected/connected state and Connect/Disconnect; Install the tokei command uses the same Core service. Work runs away from the main thread. Error text includes a recovery step; long feedback sits below the controls, keeping buttons in place while a client responds. Existing Padzy tokens are used; no added animation, so Reduce Motion needs no new animated path. The one care detail is stable row/button positions through asynchronous checks and actions.

The app scheme builds. The real registration implementation is proven against the temporary home under AC4/5. The Settings screen and its buttons are **not** live-verified by this lane. The r1 fix ledger assigns that proof to the orchestrator; it does not block this lane's READY status.

Proof attempt held `/tmp/tokei-live-proof.lock` acquired with the brief's mkdir loop; `/Applications/Tokei.app` was asked to quit first. Built app ran with a separate `ui-home`, fake Claude/Codex directories, and `-TokeiProofRoute settings -AppleInterfaceStyle Light -ApplePersistenceIgnoreState YES -SUEnableAutomaticChecks NO`. After waking the display, the own-window capture showed Overview rather than Settings. The computer-use app lookup timed out; targeted native accessibility inspection did not expose the Settings button. Stopped further GUI attempts under the global two-failure rule. No dark Settings screenshot and no Settings action proof are claimed.

Diagnostic only: `overview-light-diagnostic.png`; description: `snapshots.md`; app output: `ui-light.log`. These do not satisfy AC7. The built proof process was terminated, the restore command `open -a /Applications/Tokei.app` was issued, and the lock was released. Another lane subsequently ran its own Tokei proof app; it was left alone.

## AC8 — Help and docs: PASS

`tokei help`, README Agents, and schema docs including §7 now describe setup/removal, command install, dry run, burn opportunities, summary mode, safety boundaries, compatibility and errors. CLI version stays 0.11.0 for the orchestrator's release bump.

Check: `AgentCommandProcessTests.testInvalidOptionsFailBeforeAnyClientCanRun` asserts help terms and invalid-option exit 64; all passed. The real helper's `help` output is captured in `cli-smoke.txt`; `cli-version-sync` passes as quoted above. No unsupported two-tool claim remains in the current Agents section or schema transport section (historical changelog entries were retained).

## Orchestrator wiring required

The writer's additive API is ready; pass the just-evaluated game snapshot:

```swift
await AgentSnapshotWriter.shared.write(from: snapshots, burn: viewModel.burn)
```

This is the requested one-line writer call when `viewModel` is available; use `burn: burn` inside the view model itself. **Do not paste `viewModel.burn` into SyncEngine.swift:89.** That actor owns no view model or BurnSnapshot, so there is no compile-safe one-line change at the existing call site. Integration should place the write immediately after the WP-A burn evaluation in the view-model live-apply path, and remove/replace the earlier nil-only engine write to avoid a race that drops streak/today. Preserve injected-writer testability when choosing the final ownership. I did not edit Core/Sync or WP-A files. Until wired, expiring windows work and streak/today are intentionally absent from live snapshots. No contract declaration was changed.

## Commits

`git log --oneline dev..HEAD`:

```text
05ee62d fix(mcp): preserve legacy arguments and report burn availability
502b80a fix(agents): preserve client configuration and registration scope
a220eb9 feat(agents): connect local clients and install the bundled command
2c9800c feat(agents): expose expiring plan capacity and compact usage summaries
```

## Remaining work, cleanup and rollback

- Required: orchestrator finishes Settings light/dark/action proof, wires the game argument after WP-A, and runs the planned Claude cross-family review and integrated suite/release checks. No review or release is claimed here.
- Formatting/lint tools were absent and their gates explicitly skipped; no dependencies were installed. The build used the repository's existing language settings, not a whole-repository Swift 6 migration.
- `lsof -nP -iTCP -sTCP:LISTEN` was captured as `listeners.txt`. No server, watcher, or network listener was started by this lane. The proof app, command processes and lock-wait command are stopped. No real client registration was installed, so there is no real config rollback to do. Temporary client files remain under the ignored .scratch proof home for review.
- Roll back the initial delivery by reverting a220eb9 then 2c9800c after reverting the r1 commits; no migration or external resource change is involved. Do not remove another lane's proof lock/process.

Waits on: the orchestrator for AC7 proof, game wiring and review round 2; nothing waits on Abhay.
