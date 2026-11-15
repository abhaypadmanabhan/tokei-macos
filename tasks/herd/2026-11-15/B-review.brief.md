# Review brief WP-B · Route: ranked plan recommendation for agents (reviewer: Claude Opus, author: Codex GPT-6.1-Sol)

Review only. Do not edit, commit, push, comment on PRs, or start subagents.

- Repo: /Users/abhayp/wt/lane2 (branch `patch/2026-11-15/route`). Base: `dev`. See: `git diff dev...HEAD` and `git status --short`.
- Intent: `tasks/patch-bibles/2026-11-15.md` §3 shared rules, §4 frozen contracts, §5 WP-B (AC 1-6). Author's claims:
  `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/B-route.result.md`.

Read surrounding code. Find bugs, broken callers, mismatch with intent (each AC). Pay special attention to:
the ranking rule on edges (ties, one plan, none, all exhausted, stale or untrusted readings, several accounts on one provider, a window that resets in the next minute, percentages over 100); that the first row equals RouteTargetPolicy's answer whenever that gives one; pay-per-token agents never recommended; nothing pointing at credits or overage; what reaches an agent or terminal (account labels, emails, paths, control characters, prompt-injection text inside provider labels); existing MCP tools, inputs, shapes and CLI exit codes unchanged across all three protocol revisions; the snapshot's existing keys unchanged and older snapshots without a route block still read; exit codes documented and distinct; the CLI version really coming from MARKETING_VERSION in both Debug and Release and the gate still failing on drift.

Rerun the covering checks yourself and report each command with its exit code. Use your own DerivedData:
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-route`, after `cd AIUsageDashboard && xcodegen generate`.
Run the test classes the result file lists (one `xcodebuild … -only-testing:` invocation), not the whole suite.
Do not launch, copy or quit the installed Tokei app; list the checks you could not do.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug callers will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/B-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands
you ran with exit codes. Then run: `hc send t1d "B review r<N> written"`
