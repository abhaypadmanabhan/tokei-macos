VERDICT: APPROVE

Reviewer: Claude Opus 5.5 · round 2 · branch `patch/2026-11-14/agent-surface` @ 05ee62d (new: 502b80a, 05ee62d; reviewed `git diff a220eb9..HEAD`).
Brief sha256 verified (f5a810c2…ad2c2). Review only. All repros ran against the rebuilt helper in throwaway HOME folders,
with `CLAUDE_CONFIG_DIR` and `CODEX_HOME` never set, using the real `claude` 2.1.325 and `codex` 0.169.0.
`<dd>` = `~/Library/Developer/TokeiWork/dd-review-b/Build/Products/Debug`.

## Round 1 ids

S1 [blocker] resolved. `run()` no longer injects CLAUDE_CONFIG_DIR, CODEX_HOME or HOME. It only puts the found client's folder and the fallback folders ahead of the inherited PATH. The CODEX_HOME mkdir workaround and the Codex state shortcut are gone. Tests cover both variables absent and both passed through unchanged.
  Repro (Claude): `tokei mcp install --client claude` -> `Claude Code: connected tokei (<dd>/tokei mcp).` exit 0; again -> `already connected; no change.` exit 0; plain `claude mcp get tokei` -> `Scope: User config (available in all your projects)` … `Command: <dd>/tokei` exit 0; file holding it: `$HOME/.claude.json`. Uninstall -> `disconnected tokei.` exit 0; again -> `already disconnected; no change.` exit 0; `claude mcp get tokei` -> `No MCP server named "tokei"` exit 1.
  Repro (Codex, no `~/.codex`): install -> `Codex: connected tokei (<dd>/tokei mcp).` exit 0; again -> `already connected; no change.` exit 0; `codex mcp get tokei --json` -> `"transport": {"command": "<dd>/tokei", "args": ["mcp"]…}` exit 0; uninstall exit 0 twice (`disconnected`, then `already disconnected`).

S2 [should] resolved. A symlinked `mcp.json` stays a link, and the change lands in the target. The backup is an independent regular file holding the original bytes. Writes use O_EXCL|O_NOFOLLOW (:230), so nothing chmods through a link. Slashes are no longer escaped.
  Repro: `.cursor/mcp.json -> ../dotfiles/mcp.json` (644); install exit 0 -> `lrwxr-xr-x .cursor/mcp.json -> ../dotfiles/mcp.json`, `-rw------- .cursor/mcp.json.bak` (bytes equal the original), dotfiles has tokei; uninstall exit 0 -> link kept, tokei gone, backup still the original. The target ends up 0600: that is the owner-only mode used for every Cursor write, not a chmod through the link. Harmless; noted, not reopened.

S3 [should] resolved. Cursor now refuses a different `tokei` entry (:204), and docs §7 say this for all three clients.
  Repro: entry with `env` plus an earlier `.bak`; install -> `Cursor already has a different tokei connection. Disconnect it first, then connect again.` exit 1; env kept (grep 1).

S4 [should] resolved. A Claude match now requires `Scope: User config`; a local or project entry produces a precise fix. In Settings that row shows "Needs attention" with the fix text.
  Repro (0.11 docs command run from `~`): `claude mcp add tokei -- <dd>/tokei mcp` -> `… to local config` exit 0; `tokei mcp install --client claude` -> `Claude Code already has a different tokei connection. Disconnect it first, then connect again.` exit 1; `tokei mcp uninstall --client claude` -> `tokei is registered in Claude's local config. Run claude mcp remove tokei -s local, then retry.` exit 1; following that fix, `claude mcp remove tokei -s local` exit 0, then `tokei mcp install --client claude` -> `connected tokei` exit 0, `Scope: User config`.

S5 [nit] resolved. Only the clients' own "no MCP server" phrases count as missing. The real Codex and Claude not-found outputs still read as "already disconnected" (S1 repros). There is a test for "configuration file not found" as an error.
S6 [nit] resolved. Child PATH = found client's folder + fallback folders + inherited PATH (test asserts the exact order).
S7 [nit] resolved. `.withoutEscapingSlashes` (S2 repro: 0 escaped slashes).
S8 [nit] declined by the author; no action needed.
S9 [nit] resolved. Repro: helper copied under `…/AppTranslocation/x/Tokei.app/Contents/Helpers/`; `mcp install --client cursor` and `install` -> `Move Tokei to Applications, then retry.` exit 1. Uninstall is still allowed (correct).
S10 [nit] resolved. Settings passes `includePATHHint: false`; the terminal keeps the hint (test).
S11 [nit] declined by the author; no action needed.
S12 [nit] resolved. Repro: `tokei mcp --legacy x` answered `ping` and `tools/call` over stdio, exit 0. `install`/`uninstall` still route to setup.
S13 [nit] resolved. Repro: burn-less snapshot -> `{"available":false,"expiring":[],…,"stale":false}`. The field is additive; outputSchema `required` is unchanged.
S14 [nit] declined by the author; no action needed.
S15 [nit] declined by the author; no action needed.

## New in the changed code (nits, non-blocking)

S16 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:195 A dangling `~/.cursor/mcp.json` link (dotfiles repo not checked out) is replaced by a regular file. `resolvingSymlinksInPath` cannot resolve a missing target, so the rename lands on the link itself. Rare. Fix: when `lstat` shows a link whose target is missing, refuse with "Cursor's mcp.json points to a missing file. Restore it, then retry."
  Repro: `.cursor/mcp.json -> ../dotfiles/mcp.json` with no `dotfiles/`; install -> `Cursor: connected tokei …` exit 0; `stat` -> `-rw------- .cursor/mcp.json` (link gone).

S17 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:114 For a local-scope Claude entry, `tokei mcp install` says "different tokei connection. Disconnect it first". The exact `-s local` fix only appears after the user tries uninstall (Settings shows it directly). Fix: on install, return `claudeScopeFix(existing.output)` when it is non-nil, before the generic message.

## Checked in the changed code
The fix tests use only a fake HOME and PATH with no fallback folders. The process tests still pass fake config dirs and run only dry-run, invalid or `ping` paths. No real HOME is touched. Settings work stays in `Task.detached`. The install-location guard runs before any client or file action, including dry-run install. A failed Cursor rename is reported through the generic writable-folder message, and the staged temp file is removed by `defer`. Docs §7 and the tool table match the behaviour.

## UI checks not done (app not launched, per brief)
Settings "Connect agents" in light and dark; Connect, Disconnect and Install clicks; the "Needs attention" row with the local-scope fix text; button positions while busy. These stay with the orchestrator's AC7 proof. S1 is fixed, so that proof can now run.

## Commands run (exit codes)
1. `shasum -a 256 tasks/herd/2026-11-14/B-review.brief.md` -> f5a810c2…ad2c2, matches; exit 0
2. `cd AIUsageDashboard && xcodegen generate` -> exit 0 (picks up the new AgentConnectionReviewTests)
3. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-b -only-testing:AIUsageDashboardCoreTests/{AgentBurnSnapshotTests,AgentSnapshotWriterTests,BurnMCPTests,MCPServerTests,MCPAccountContractTests,MCPServerProcessTests,AgentConnectionTests,AgentConnectionReviewTests,MCPServerErrorTests,MCPServerExchangeMatrixTests,SnapshotReaderTests,AgentSnapshotStalenessTests,AgentSnapshotAccountSchemaTests,ForecastForwardCompatibilityTests,AgentCommandProcessTests} test` (one invocation, 15 classes) -> `Executed 118 tests, with 0 failures`, `** TEST SUCCEEDED **`; exit 0. This also rebuilt `<dd>/tokei` for the repros.
4. Repro script (temp HOMEs, `env -i HOME=$H PATH=/usr/bin:/bin TMPDIR=$TMPDIR`): S1 Claude 4× tokei exit 0, `claude mcp get` exit 0 then 1; S1 Codex 4× tokei exit 0, `codex mcp get --json` exit 0; S4 tokei install 1, uninstall 1, `claude mcp remove -s local` 0, tokei install 0; S2 install 0, uninstall 0; S16 install 0; S3 install 1; S12/S13 stdio exit 0; S9 2× exit 1. Outputs as quoted above.
5. `xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-b build` (covers the changed AgentConnectSection line) -> `** BUILD SUCCEEDED **`; exit 0
6. `git status --short` in the worktree -> empty. Temp homes removed; no leftover processes or listeners.
Not rerun this round: fast gates, full suite, secscan (the orchestrator's integration run).
