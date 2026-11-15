# Brief WP-A · Speed: targeted refresh and a perf harness (Codex gpt-6.1-sol xhigh)

cd /Users/abhayp/wt/lane1 — work ONLY in this directory (branch `patch/2026-11-15/speed`). The single exception:
write your result file at the absolute path below.

## Read first (in this order)
1. `tasks/patch-bibles/2026-11-15.md`: "Abhay's answers", §0, §3 shared rules, §4 frozen contracts, §5 WP-A
   (your scope and acceptance criteria; each AC names its check). That file is the spec; this brief adds logistics.
2. The path you change and why it is shaped that way: `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/SyncEngine.swift`
   (periodic refresh, `refreshAll` coalescing), `Core/Utilities/FileWatcher.swift`, `App/WindowVisibilityMonitor.swift`
   (read-only, the visibility signal), `Core/Parsing/ClineMessagesParser.swift`, `Core/Parsing/ClaudeJSONLParser+Streaming.swift`
   (the incremental cache pattern to copy), `SQLiteSidecarCopy.swift`, `Core/Network/{ClaudeUsageClient,CodexRateLimitClient,AntigravityQuotaClient}.swift`.
3. `CHANGELOG.md` 0.12.0 "Changed — smoother" (how the last numbers were measured) and
   `AIUsageDashboard/scripts/{build-app.sh,verify-app.sh}`.

## Rules
- Staff-engineer loop: plan each slice with its proof, small commits, tests that fail on the old code.
- Build the harness (AC 1) FIRST and record the baseline on `dev` before changing behaviour.
- Tests: `cd AIUsageDashboard && xcodegen generate`, then
  `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS'
  -derivedDataPath ~/Library/Developer/TokeiWork/dd-speed -only-testing:AIUsageDashboardCoreTests/<Class> test`.
  Run the classes you add or touch, plus the Sync and parser test classes once at the end. Then
  `bash .claude/gates/run-all.sh fast` from the worktree root.
- The harness may launch a build of Tokei from your own DerivedData against a synthetic home only. It must not
  read this Mac's real agent logs, must not touch the installed `/Applications/Tokei.app` or its preferences
  (use a separate defaults suite or a temp `HOME` if the app allows; say which), and must quit what it starts.
- Another lane (WP-B) edits `TokeiCLI/**` and `Core/Agent/**` at the same time; stay out of them.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/A-speed.result.md`: line 1 `STATUS: READY` or
`STATUS: BLOCKED`; then per AC (1-7): what you did, the check, the exact command and its output lines; the
baseline and after tables from the harness; commits (`git log --oneline dev..HEAD`); contract additions; known gaps.
When the file is complete and your commits are final, run: `hc send t1d "A-speed result written"`
