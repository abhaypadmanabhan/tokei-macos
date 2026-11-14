# Review brief WP-A · Burn engine (reviewer: Claude Opus, author: Codex GPT-6.1-Sol)

Review only. Do not edit, commit, push, comment on PRs, or start subagents.

- Repo: /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-engine (branch `patch/2026-11-14/burn-engine`).
- Base: `a4a8894` (contract commit on `dev`). See: `git diff a4a8894` and `git status --short`.
- Intent: the burn game engine and quiet nudges per `tasks/patch-bibles/2026-11-14.md` §4 contract, §5 WP-A
  (AC 1–11) and §7 "Burn eligibility" (burn counts plan providers only). Author's claims:
  `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/A-burn-engine.result.md`.
- Out of scope: UI, CLI, Core/Agent, providers/parsers, network.

Read surrounding code. Find bugs, broken callers, mismatch with intent (each AC and §7). Pay special attention to:
streak/day boundaries and time zones; first-run seeding (no moments, no nudges from seeded or saved data);
the 2-per-day cap and once-per-window rule across app restarts; that nothing nudges toward credits/overage;
persistence safety (0600, write only on change, corrupt file handling); main-actor cost; that today's USD equals
the Cost view's today for the same input; eligibility applied to every burn number.

Rerun the covering checks yourself and report each command with its exit code. Use your own DerivedData:
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-a`, after `cd AIUsageDashboard && xcodegen generate`.
Run the test classes the result file lists (one `xcodebuild … -only-testing:` invocation), not the whole suite.
Mac app: do not launch or copy the app; list the UI checks you could not do.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug callers will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/A-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands
you ran with exit codes. Then print `TOKEI_A_REVIEW_DONE`.
