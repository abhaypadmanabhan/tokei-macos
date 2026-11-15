# Brief WP-B · Route: a ranked plan recommendation agents can ask for (Codex gpt-6.1-sol xhigh)

cd /Users/abhayp/wt/lane2 — work ONLY in this directory (branch `patch/2026-11-15/route`). The single exception:
write your result file at the absolute path below.

## Read first (in this order)
1. `tasks/patch-bibles/2026-11-15.md`: "Abhay's answers", §0, §3 shared rules, §4 frozen contracts, §5 WP-B
   (your scope and acceptance criteria; each AC names its check). That file is the spec; this brief adds logistics.
2. What you build on, under `AIUsageDashboard/AIUsageDashboardApp/`: `Core/Utilization/QuotaPace.swift`, the
   existing `RouteTargetPolicy` (find it with `grep -rn RouteTargetPolicy`), `UI/MenuBar/MaxxerMath.swift`
   (`routeTarget`, read-only), `Core/Game/ExpiringHeadroom.swift`, `Core/Agent/AgentSnapshotWriter.swift`.
3. The agent surface, under `AIUsageDashboard/TokeiCLI/`: `MCPServer.swift`, `MCPServer+Instructions.swift`,
   `AgentCommands.swift` (`guard`, `burn`), `StatusCommand.swift`, `SnapshotReader.swift`, `main.swift`, and how
   0.12.0 added `get_burn_opportunities` (`git log --oneline -8 -- AIUsageDashboard/TokeiCLI`).

## Rules
- Staff-engineer loop: plan each slice with its proof, small commits, tests that fail on the old code.
- Land `RoutePlan` (AC 1) as your FIRST commit and keep its public shape stable after that; the UI lane builds
  on it. List the type's public API at the top of your result file.
- Tests: `cd AIUsageDashboard && xcodegen generate`, then
  `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS'
  -derivedDataPath ~/Library/Developer/TokeiWork/dd-route -only-testing:AIUsageDashboardCoreTests/<Class> test`
  (find the CLI's test target and scheme in `project.yml`). Run the classes you add or touch, plus the existing
  MCP, CLI and agent snapshot classes once at the end. Then `bash .claude/gates/run-all.sh fast` from the worktree root.
- AC 6 reads the live agent snapshot file read-only through your built `tokei`; do not install it to
  `~/.local/bin`, do not register it with any client, do not launch or quit the installed Tokei app.
- Another lane (WP-A) edits `Core/{Sync,Utilities,Parsing,Providers,Network}/**` at the same time; stay out of them.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/B-route.result.md`: line 1 `STATUS: READY` or
`STATUS: BLOCKED`; then the `RoutePlan` public API; per AC (1-6): what you did, the check, the exact command and
its output lines; commits (`git log --oneline dev..HEAD`); contract additions; known gaps.
When the file is complete and your commits are final, run: `hc send t1d "B-route result written"`
