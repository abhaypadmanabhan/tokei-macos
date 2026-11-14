# Brief WP-B · Agent surface: MCP, one-click connect, CLI (Codex gpt-6.1-sol xhigh)

cd /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface — work ONLY in this directory (branch
`patch/2026-11-14/agent-surface`). The single exception: write your result file at the absolute path below and
proof media under `~/Library/Developer/TokeiWork/proof/agent-surface/`.

## Read first (in this order)
1. `tasks/patch-bibles/2026-11-14.md` §"Abhay's answers", §3 shared rules, §4 contract, §5 WP-B (your scope and
   acceptance; each AC names its check). That file is the spec; this brief adds logistics.
2. `TokeiCLI/*` (MCP server, framing, snapshot reader, status, guard), `AIUsageDashboardApp/Core/Agent/*`
   (snapshot schema + writer + route policy), `docs/08-agent-snapshot-schema.md`, `project.yml` (the `tokei`
   target compiles `Core/Agent/AgentSnapshot.swift` directly; add `Core/Game/ExpiringHeadroom.swift` only if the CLI
   truly needs it), `Core/Game/{ExpiringHeadroom,BurnSnapshot}.swift` (read only),
   `UI/Settings/SettingsDrawer.swift` + `SettingsSections.swift` (read; you add ONE include line in SettingsDrawer).
3. The snapshot writer's call site is in `Core/Sync/SyncEngine.swift`, which is outside your scope. If the burn
   block needs the view model's `BurnSnapshot`, add an optional parameter to the writer API and describe the one-line
   call-site change in the result file; the orchestrator wires it at integration.

## Rules
- Build/test: `cd AIUsageDashboard && xcodegen generate`, then
  `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS'
  -derivedDataPath ~/Library/Developer/TokeiWork/dd-agent-surface -only-testing:AIUsageDashboardCoreTests/<Class> test`
  for the classes you add or touch; build the `tokei` scheme and the app scheme once; then
  `bash .claude/gates/run-all.sh fast` from the worktree root (includes `cli-version-sync`).
- Tests NEVER touch real client configs: fake `HOME`, fake `CLAUDE_CONFIG_DIR`, stub `claude`/`codex` scripts on a
  fake `PATH`. Live proof on this Mac is `--dry-run` only, plus a real connect against a temp `HOME`.
  Never run `claude mcp add`, `codex mcp add` or write `~/.cursor/mcp.json` against Abhay's real home.
- Launching a built Tokei for the Settings snapshot: hold the lock (`until mkdir /tmp/tokei-live-proof.lock
  2>/dev/null; do sleep 5; done`; `rmdir` it when done), quit `/Applications/Tokei.app` first and relaunch it
  (`open -a /Applications/Tokei.app`) when done. Another lane may hold the lock; wait for it.
- Keep the MCP backward compatible: existing tools keep their names, inputs and documented output shape.
- Never `--no-verify`. No new dependencies. Do not read credentials.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/B-agent-surface.result.md`:
line 1 `STATUS: READY` or `STATUS: BLOCKED`; per AC (1–8): what you did, the check, exact commands with output
lines, proof paths; the MCP bytes before/after table; commits (`git log --oneline dev..HEAD`); the call-site change
for the orchestrator; known gaps. When complete, print exactly: `TOKEI_B_DONE`
