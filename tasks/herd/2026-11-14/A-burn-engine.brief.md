# Brief WP-A · Burn engine + nudges (Codex gpt-6.1-sol xhigh)

cd /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-engine — work ONLY in this directory (branch
`patch/2026-11-14/burn-engine`). The single exception: write your result file at the absolute path below.

## Read first (in this order)
1. `tasks/patch-bibles/2026-11-14.md` §"Abhay's answers", §3 shared rules, §4 contract, §5 WP-A (your scope and
   acceptance criteria; each AC names its check). That file is the spec; this brief only adds logistics.
2. The contract you build on: `AIUsageDashboard/AIUsageDashboardApp/Core/Game/{BurnSnapshot,ExpiringHeadroom,BurnSnapshot+Sample}.swift`,
   `Core/Sync/DashboardViewModel.swift` (`burn` property), `Tests/GameTests/ExpiringHeadroomTests.swift`.
3. Code you extend: `Core/Maxxer/MaxxerValueEngine.swift`, `Core/Analytics/UsageAnalytics*.swift`,
   `Core/Storage/{QuotaSeriesStore,SecureFileWriter,UsageStore}.swift`, `Core/Notifications/*`,
   `Core/Utilization/QuotaPace.swift`, `Core/Maxxer/MaxxerPlanCostStore.swift`.

## Rules
- Follow the staff-engineer loop: plan each slice with its proof, small commits, tests that can fail.
- Build/test: `cd AIUsageDashboard && xcodegen generate`, then
  `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS'
  -derivedDataPath ~/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/<Class> test`.
  Run only the classes you add or touch, plus `NotificationTests`, `SyncTests`, `UtilizationTests`, `MaxxerTests`
  once at the end. Then `bash .claude/gates/run-all.sh fast` from the worktree root.
- Do not launch the Tokei app; WP-A is proven by tests (the orchestrator does the live notification).
- Additive contract changes only; list each one in the result file.
- Never `--no-verify`. No new dependencies. Do not read credentials or real provider logs.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/A-burn-engine.result.md`:
line 1 `STATUS: READY` or `STATUS: BLOCKED`; then per AC (1–11): what you did, the check, and the exact command
with its pass/fail output lines; commits (`git log --oneline dev..HEAD`); contract additions; known gaps.
When the file is complete and committed work is final, print exactly: `TOKEI_A_DONE`
