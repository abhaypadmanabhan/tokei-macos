# Review brief WP-C · Burn UI + Mac smoothness (reviewer: Codex GPT-6.1-Sol, author: Claude Opus 5.5)

Review only. Do not edit, commit, push, or start subagents. Do not launch, quit or copy any Tokei app: the author
is running a timed measurement session with the real app right now; launching or quitting Tokei would corrupt it.

- Repo: /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-ui (branch `patch/2026-11-14/burn-ui`).
- Base: `dev` (`git merge-base HEAD dev`; the branch already merged dev at 8dedb49 = WP-A engine). See:
  `git diff $(git merge-base HEAD dev)` and `git status --short`.
- Intent: `tasks/patch-bibles/2026-11-14.md` §5 WP-C (AC 1–8) and §7 (plan-only burn; today's USD is plan burn,
  not the Cost view number). The author's result file may still be in progress:
  `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/C-burn-ui.result.md` (read it if present).
- Out of scope: Core/** (WP-A, merged), TokeiCLI, `UI/Settings/AgentConnectSection.swift` (WP-B).

Read surrounding code. Find bugs, broken callers, mismatch with intent. Pay special attention to: SwiftUI
invalidation and main-thread cost (anything heavy in `body`, timers or animations left running when the window or
menu is closed, idle CPU); the performance changes (do they keep behaviour identical? observation correctness after
any ObservableObject → narrower observation change: stale UI that never updates is a blocker); the menu bar dropdown
open path; celebrations (one-shot, Reduce Motion, never steal focus, never move controls under the pointer, no
repeats on every refresh); the share card (no account labels, emails, paths or project names can reach it); empty
and saved → live states; eyebrow labels, mono numbers, one accent per view, contrast; Debug-only proof routes and
launch flags that must not ship active in Release builds; keyboard shortcuts renumbered consistently; accessibility
labels on rings, badges and the leaderboard.

Rerun the covering checks yourself and report each command with exit code. Use your own DerivedData:
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-c`, after `cd AIUsageDashboard && xcodegen generate`.
Run the UI/Charts/Burn test classes the branch adds or touches in one `-only-testing:` invocation, plus a Release
configuration build of the `AIUsageDashboardApp` scheme. Not the whole suite.
Mac app: do not launch; list the UI checks you could not do.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug users will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/C-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands you
ran with exit codes. Then print `TOKEI_C_REVIEW_DONE`.
