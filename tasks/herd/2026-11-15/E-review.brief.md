# Review brief WP-E · Integration fixes (reviewer: Claude Opus, author: Codex GPT-6.1-Sol)

Review only. Do not edit, commit, push, or start subagents.
- Repo: /Users/abhayp/wt/lane1 (branch `patch/2026-11-15/integration-fix`). Base: `dev`. See `git diff dev...HEAD`.
- Intent: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-integration-fix.brief.md` (items 1, 2a-2d).
  Author's claims: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-integration-fix.result.md`.

Find bugs and mismatch with intent. Pay special attention to: the Codex individual spending cap now counted as
a binding constraint without ever recommending purchasable credits or pointing at overage, and row, policy,
chip and CLI still agreeing (RoutePlan is shared by the UI row and chips in `UI/Components/RouteCopy.swift`);
the sanitiser change not altering any existing valid label (non-Latin scripts that need combining marks: note
it if dropped marks would mangle them, as a nit with the trade-off); rebuilt reason sentences matching the
app's own sentences for the same row and no snapshot string reaching the agent unsanitised; the probe guard
change not opening any path where a Release build runs with Sparkle off or isolation half-applied; `-I` not
breaking the benchmark's imports.
Rerun the test classes the result lists (one `xcodebuild … -only-testing:` run,
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-review-fix`, after `cd AIUsageDashboard && xcodegen generate`).
Do not launch or quit the installed Tokei app.
blocker = intended case wrong. should = real bug users will hit. nit = rest. Repro lines where code can show it.
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-review-r<N>.md`, first line exactly
`VERDICT: APPROVE` or `VERDICT: CHANGES`, findings as `S1 [blocker|should|nit] <file>:<line> <claim>. Fix: …`,
then commands with exit codes. Then run: `hc send t1d "E review r<N> written"`
