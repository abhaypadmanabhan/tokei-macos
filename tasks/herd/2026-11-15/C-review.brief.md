# Review brief WP-C · Route UI and demo data (reviewer: Codex GPT-6.1-Sol, author: Claude Opus)

Review only. Do not edit, commit, push, comment on PRs, or start subagents.

- Repo: /Users/abhayp/wt/lane2 (branch `patch/2026-11-15/route-ui`). Base: `dev`. See: `git diff dev...HEAD` and `git status --short`.
- Intent: `tasks/patch-bibles/2026-11-15.md` §3 shared rules, §4 frozen contracts, §5 WP-C (AC 1-5). Author's claims:
  `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/C-route-ui.result.md`.

Read surrounding code. Find bugs, broken callers, mismatch with intent (each AC). Pay special attention to:
the demo fixture being Debug-only and unreachable in Release (no launch argument, default or environment value
can switch a Release build to demo data, and a Debug run without the flag never writes demo data into the real
store, quota series, burn state or agent snapshot); the fixture holding nothing real; the route row and the two
chips always agreeing with `RoutePlan.recommendation` (the author removed the 15-point spread gate for the chip:
judge whether the chip now nags with one plan or near-equal plans); every state's copy (one plan, none, stale,
all nearly used up) and that none points at credits or overage; VoiceOver labels and keyboard access for "Show
the next 2"; Reduce Motion; the timer change (clocks resume correctly when the window or popover reappears,
countdowns never show a stale value, nothing ticks while hidden, no retain cycle); main-thread cost of
computing the route in view bodies; the two removed `visibleUtilizations` helpers having no remaining callers.

Rerun the covering checks yourself and report each command with its exit code. Use your own DerivedData:
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-route-ui`, after `cd AIUsageDashboard && xcodegen generate`.
Run the test classes the result file lists (one `xcodebuild … -only-testing:` invocation), not the whole suite,
and one Release build of the app scheme with `CODE_SIGNING_ALLOWED=NO`. Do not launch, copy or quit the installed
Tokei app; list the UI checks you could not do.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug users will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/C-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands
you ran with exit codes. Then run: `hc send t1d "C review r<N> written"`
