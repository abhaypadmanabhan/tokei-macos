# Review brief WP-B · Agent surface (reviewer: Claude Opus, author: Codex GPT-6.1-Sol)

Review only. Do not edit, commit, push, comment on PRs, or start subagents.

- Repo: /Users/abhayp/src/tokei-worktrees/2026-11-14-agent-surface (branch `patch/2026-11-14/agent-surface`).
- Base: `a4a8894` (contract commit on `dev`). See: `git diff a4a8894` and `git status --short`.
- Intent: MCP + CLI + one-click agent connect per `tasks/patch-bibles/2026-11-14.md` §5 WP-B (AC 1–8) and §7.
  Author's claims: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/B-agent-surface.result.md`.
  AC7's GUI proof is deferred to the orchestrator's integrated live proof; review its code anyway.
- Out of scope: Core/Game, Core/Sync, notifications, other UI.

Read surrounding code. Find bugs, broken callers, mismatch with intent. Pay special attention to: MCP backward
compatibility (existing tool names, inputs, documented output shape, schema version); that `tokei mcp install`
and the Settings buttons can never corrupt or clobber a user's real Claude/Codex/Cursor config (malformed JSON,
existing different `tokei` entry, symlinks, permissions, concurrent writes, partial failure); argv handling with no
shell; process timeouts; `tokei install` symlink safety (existing file, different target, PATH hint); that nothing
nudges toward credits or overage; that tests never touch the real HOME; main-thread blocking in the Settings section.

Rerun the covering checks yourself and report each command with its exit code. Use your own DerivedData:
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-b`, after `cd AIUsageDashboard && xcodegen generate`.
Run the test classes the result file lists (one `xcodebuild … -only-testing:` invocation), not the whole suite.
Mac app: do not launch or copy the app; list the UI checks you could not do.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug callers will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/B-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands
you ran with exit codes. Then print `TOKEI_B_REVIEW_DONE`.
