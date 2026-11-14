VERDICT: CHANGES

Reviewer: Claude Opus 5.5 · round 1 · branch `patch/2026-11-14/agent-surface` @ a220eb9 vs base a4a8894.
Brief sha256 verified (f5a810c2…ad2c2). Review only: no edits, commits or comments. Repros ran only against
throwaway HOME folders in the reviewer's scratchpad. `<dd>` = `~/Library/Developer/TokeiWork/dd-review-b/Build/Products/Debug`.

## Findings

S1 [blocker] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:262 Connecting Claude Code writes the registration to a file normal Claude Code never reads, then reports success. `run()` injects `CLAUDE_CONFIG_DIR=$HOME/.claude` when the user has none set (the default for nearly everyone). With that variable set, Claude Code 2.1.325 keeps its global config at `$CLAUDE_CONFIG_DIR/.claude.json` (`~/.claude/.claude.json`) instead of `~/.claude.json`. The readback `mcp get` runs with the same injected env, so it confirms the wrong file; the Settings row will also show "Connected". Tests miss it because every test sets `CLAUDE_CONFIG_DIR` and the stub asserts it (Tests/ConnectTests/AgentConnectionTests.swift:24); the author's live proof also set it. Fix: pass the user's environment through and stop injecting `CLAUDE_CONFIG_DIR` and `CODEX_HOME` (line 263). That also removes the reason for the CODEX_HOME mkdir workaround at :109-115 (codex resolves `~/.codex` itself when the variable is unset; unverified, re-prove it). Add a test with neither variable set that asserts the child sees neither, and rerun the temp-HOME live connect with both unset.
  Repro (temp HOME, real claude symlinked into it):
  `H=$(mktemp -d); mkdir -p $H/.local/bin; ln -s "$(readlink -f ~/.local/bin/claude)" $H/.local/bin/claude`
  `env -i HOME=$H PATH=/usr/bin:/bin TMPDIR=$TMPDIR <dd>/tokei mcp install --client claude` -> `Claude Code: connected tokei (<dd>/tokei mcp).` exit 0; second run -> `Claude Code: tokei is already connected; no change.` exit 0
  `grep -rl '"tokei"' $H --include='*.json'` -> `$HOME/.claude/.claude.json` only (no `$HOME/.claude.json`)
  `env -i HOME=$H PATH=/usr/bin:/bin TMPDIR=$TMPDIR $H/.local/bin/claude mcp get tokei` -> `No MCP server named "tokei". Run \`claude mcp add\` to add one.` exit 1

S2 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:215 A symlinked `~/.cursor/mcp.json` (dotfiles managers) is clobbered: the atomic write replaces the link with a regular file, so the user's managed file never gets the change and silently diverges. The ".bak" at :209 is `copyItem`, which copies the link, not the bytes, so the "backup" is a live pointer to the target. :210 then `chmod 0600` follows that link and changes the dotfile's mode. Fix: resolve the link once and write the target atomically (temp file in the target's directory + rename), back up by writing the bytes (`Data(contentsOf:)` then write), never chmod through a link; or refuse a symlinked file with one fix line. Add a test.
  Repro: `H=$(mktemp -d); mkdir -p $H/dotfiles $H/.cursor; printf '{"mcpServers":{"other":{"command":"keep"}}}' > $H/dotfiles/mcp.json; chmod 644 $H/dotfiles/mcp.json; ln -s $H/dotfiles/mcp.json $H/.cursor/mcp.json`
  `env -i HOME=$H PATH=/usr/bin:/bin <dd>/tokei mcp install --client cursor` -> `Cursor: connected tokei in $HOME/.cursor/mcp.json.` exit 0
  `stat -f '%Sp %N%SY' .cursor/mcp.json .cursor/mcp.json.bak dotfiles/mcp.json` -> `-rw------- .cursor/mcp.json` (now a plain file) / `lrwxr-xr-x .cursor/mcp.json.bak -> …/dotfiles/mcp.json` / `-rw------- dotfiles/mcp.json` (was 644, still has no tokei)

S3 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:204 Cursor silently overwrites a different existing `tokei` entry (dropping its `env`, `type` or other keys) and prints "connected", while Claude and Codex refuse the same case. AC4 says "prints exactly what changed"; the brief lists "existing different tokei entry" as must-not-clobber. Once an earlier connect has left a `.bak`, the replaced entry is unrecoverable. Fix: when `servers["tokei"]` exists and differs, throw the same "already has a different tokei connection. Disconnect it first" error as Claude/Codex; update docs §7 ("a different Claude/Codex registration is kept") to include Cursor; add a test.
  Repro: `.cursor/mcp.json` = `{"mcpServers":{"tokei":{"command":"/Applications/Tokei.app/Contents/Helpers/tokei","args":["mcp"],"env":{"TOKEI_SNAPSHOT_PATH":"/custom/path.json"}}}}` plus an existing `mcp.json.bak`; `env -i HOME=$H PATH=/usr/bin:/bin <dd>/tokei mcp install --client cursor` -> `Cursor: connected tokei in $HOME/.cursor/mcp.json.` exit 0; `grep -c TOKEI_SNAPSHOT_PATH $H/.cursor/mcp.json` -> `0`

S4 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:116 Existing users who followed the 0.11 docs (`claude mcp add tokei -- … mcp`, no `--scope`, so local scope) from their home folder get a false "Connected" and cannot disconnect. `mcp get` is scope-agnostic, so install says "already connected; no change" though the server only loads when Claude runs in `~`. Uninstall then runs `mcp remove --scope user tokei`, which fails, and returns a generic error. Fix: in `matches` for Claude, also require the `Scope: User config` line. When `get` reports another scope, have uninstall say "tokei is registered in Claude's local config; run claude mcp remove tokei -s local" instead of attempting a user-scope remove. Add a stub case with a non-user scope.
  Repro (CLAUDE_CONFIG_DIR set so S1 does not interfere; cwd = $H): `claude mcp add tokei -- <dd>/tokei mcp` -> `Added stdio MCP server tokei … to local config`; `<dd>/tokei mcp install --client claude` -> `Claude Code: tokei is already connected; no change.` exit 0; `<dd>/tokei mcp uninstall --client claude` -> `Claude Code did not disconnect tokei. Run claude mcp --help to check your client, then retry.` exit 1; `claude mcp get tokei` -> `Scope: Local config (private to you in this project)`

S5 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:237 `isMissing` treats any output containing "not found" as "no tokei server". A client failure such as "Claude configuration file not found…" makes uninstall report "already disconnected; no change" with exit 0, and makes state show "Detected". reading. Fix: match only the clients' own phrases (`no mcp server named`, `no mcp server found`).

S6 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:260 From Settings, children inherit the GUI app's launchd PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). An npm-installed `claude`/`codex` found through the `/opt/homebrew/bin` fallback is a `#!/usr/bin/env node` script and fails, giving "Could not read the connection". Both clients on this Mac are native Mach-O, so it does not reproduce here. reading. Fix: prepend the found binary's directory and the fallback directories to the child PATH.

S7 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:214 Cursor rewrite escapes every slash in every server (`"command" : "\/Users\/…\/tokei"`) and re-sorts keys. The JSON is valid but ugly in a hand-edited file. Fix: add `.withoutEscapingSlashes`.

S8 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:160 `tokei install --force` when `~/.local/bin/tokei` is a directory replies "Run tokei install --force". Fix: separate message ("is a folder; move it, then retry").

S9 [nit] AIUsageDashboard/AIUsageDashboardApp/UI/Settings/AgentConnectSection.swift:14 Run from a quarantined download (App Translocation) or a mounted DMG, Connect and Install register a temporary helper path that later disappears. reading. Fix: refuse when the helper path contains `/AppTranslocation/` or starts with `/Volumes/`, with "Move Tokei to Applications, then retry".

S10 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:174 From Settings the PATH hint always appears, because it checks the app's launchd PATH, not the user's shell. reading. Fix: omit the hint from the Settings path, or word it as conditional.

S11 [nit] AIUsageDashboard/TokeiCLI/StatusFormatting.swift:185 `tokei burn` drops account identity, so two eligible accounts of the same provider print identical advice lines. reading. Fix: add an ordinal ("Codex account 2 …") when a provider repeats.

S12 [nit] AIUsageDashboard/TokeiCLI/main.swift:60 `tokei mcp <anything>` used to start the server and ignore extra args; it now prints usage to stdout and exits 64. That breaks any registration that passes extra args. reading. Fix: route only `install`/`uninstall` to AgentCommands.

S13 [nit] AIUsageDashboard/TokeiCLI/MCPServer.swift:356 A snapshot without a `burn` block returns `{"expiring":[],"stale":false}`, which looks the same as "nothing expiring", although the docs say a missing block means unavailable. That snapshot exists only in the window between an app update and its first refresh (the helper ships inside the app). Fix (optional): an additive `available:false`.
  Repro: v1 snapshot without `burn`, `tools/call get_burn_opportunities` -> `{"expiring":[],"generatedAt":"…","stale":false}`

S14 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Agent/AgentSnapshot.swift:520 `opportunities(asOf:)` re-checks the window-type whitelist and the used/unused arithmetic that the shared finder already guarantees at write time. The intent only needs the time filters (passed reset, reading age). Fix: keep only those.

S15 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Connect/AgentConnection.swift:196 Cursor read-modify-write takes no lock, so a Settings click and a terminal command at the same moment can drop one change. Rare. Fix: `flock` a sibling lock file around read+write.

## Checked and fine
- MCP compatibility: tool names and order unchanged (third appended), inputs additive (`detail` enum `summary`; other values, null and extra keys rejected with -32602), schemaVersion stays 1. Old snapshots without `burn` decode. Older helpers ignore the new key. The summary payload satisfies the published `get_usage` outputSchema. Default `get_usage` output is unchanged apart from the additive `burn` block.
- argv only, no shell; 12 s timeout with SIGTERM then SIGKILL; child output parsed, never shown.
- `tokei install`: lstat-based check, refuses a different file or link without `--force`, never replaces a folder, atomic sibling rename.
- No credit or overage nudge: credits/per-model/lifetime excluded; instructions, tool text, `tokei burn` and README all say never spend credits or overage.
- Tests never touch the real HOME. Connection tests use an explicit fake env with stubs and no fallbacks. Process tests pass env-only HOME, PATH and config dirs, and run dry-run or invalid options only. The only real paths read are `/Applications/Cursor.app` existence and the temp dir.
- Settings: client work runs in `Task.detached`; buttons stay disabled while checking or working, so there are no double clicks; fixed 76 pt button frame. Helper path is `Contents/Helpers/tokei`. With the helper copied into a fake `.app/Contents/Helpers/`, `runningHelper` resolved to that helper. The app has no sandbox entitlement, so spawning clients works.

## UI checks not done (app not launched, per brief)
Settings "Connect agents" in light and dark; Connect, Disconnect and Install clicks in the built app; the "Checking…"/"Updating…" states and that buttons do not move; error text wrapping in the drawer; VoiceOver labels; Reduce Motion. AC7 proof still belongs to the orchestrator; it should run after S1 is fixed, because today the Claude row would show "Connected" for the wrong file.

## Commands run (exit codes)
1. `shasum -a 256 tasks/herd/2026-11-14/B-review.brief.md` -> f5a810c2…ad2c2, matches; exit 0
2. `cd AIUsageDashboard && xcodegen generate` -> "Created project"; exit 0 (xcodeproj is gitignored)
3. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-b -only-testing:AIUsageDashboardCoreTests/{AgentBurnSnapshotTests,AgentSnapshotWriterTests,BurnMCPTests,MCPServerTests,MCPAccountContractTests,MCPServerProcessTests,AgentConnectionTests,MCPServerErrorTests,MCPServerExchangeMatrixTests,SnapshotReaderTests,AgentSnapshotStalenessTests,AgentSnapshotAccountSchemaTests,ForecastForwardCompatibilityTests,AgentCommandProcessTests} test` (one invocation, 14 classes) -> `Executed 106 tests, with 0 failures`, `** TEST SUCCEEDED **`; exit 0. Also produced `<dd>/tokei`, used for the repros.
4. `xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-b build` -> `** BUILD SUCCEEDED **`; exit 0
5. `BASE_REF=a4a8894 bash .claude/gates/run-all.sh fast` -> preflight, no-secret, no-large-artifact, no-uncommitted, cli-version-sync, format, lint PASS; `ALL GATES GREEN`; exit 0
6. S1 repro (temp HOME): `tokei mcp install --client claude` exit 0 twice; `claude mcp get tokei` exit 1. Probe: `claude mcp add --scope user probe -- /bin/echo hi` with `CLAUDE_CONFIG_DIR=$H/.claude` exit 0, written to `$H/.claude/.claude.json`; plain `claude mcp get probe` -> not found.
7. S2/S3 repro (temp HOME): `tokei mcp install --client cursor` exit 0 in both cases; `stat` and `grep` outputs as quoted above.
8. S4 repro (temp HOME, CLAUDE_CONFIG_DIR set): `claude mcp add tokei -- <dd>/tokei mcp` exit 0; `tokei mcp install --client claude` exit 0; `tokei mcp uninstall --client claude` exit 1; `claude mcp get tokei` exit 0 showing local scope.
9. S13 repro: newline JSON-RPC `initialize` + `tools/call get_burn_opportunities` to `<dd>/tokei mcp` with a burn-less fixture; exit 0.
10. `git status --short` in the worktree after all runs -> empty (clean).
Not run: full suite, secscan, separate `tokei` scheme build (step 3 built the helper), app launch.
