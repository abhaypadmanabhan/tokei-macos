# Review brief WP-A · Speed: targeted refresh and perf harness (reviewer: Claude Opus, author: Codex GPT-6.1-Sol)

Review only. Do not edit, commit, push, comment on PRs, or start subagents.

- Repo: /Users/abhayp/wt/lane1 (branch `patch/2026-11-15/speed`). Base: `dev`. See: `git diff dev...HEAD` and `git status --short`.
- Intent: `tasks/patch-bibles/2026-11-15.md` §3 shared rules, §4 frozen contracts, §5 WP-A (AC 1-7). Author's claims:
  `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/A-speed.result.md`.

Read surrounding code. Find bugs, broken callers, mismatch with intent (each AC). Pay special attention to:
stale numbers: any path where a provider's data changes but its refresh never fires (file events under shared parent folders, renamed or rotated logs, a new session folder created after launch, a provider with no watchable folder that relied on someone else's event); the periodic 300 s refresh still covering everything; the 15 s hidden-window throttle catching up at once when the popover or window opens and never dropping the final event of a burst; caches keyed by size and modification time missing a same-size rewrite or a truncation; the SQLite skip ignoring the -wal file; coalescing and actor isolation (data races, a refresh lost while one is in flight); the harness never reading real logs, never touching the installed app or its preferences, quitting what it starts, and its budget not tuned to pass; whether the claimed CPU numbers follow from the two harness outputs.

Rerun the covering checks yourself and report each command with its exit code. Use your own DerivedData:
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-speed`, after `cd AIUsageDashboard && xcodegen generate`.
Run the test classes the result file lists (one `xcodebuild … -only-testing:` invocation), not the whole suite.
Do not launch, copy or quit the installed Tokei app; list the checks you could not do.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug callers will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/A-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands
you ran with exit codes. Then run: `hc send t1d "A review r<N> written"`
