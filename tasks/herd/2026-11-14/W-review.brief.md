# Review brief WP-W · Website (reviewer: Codex GPT-6.1-Sol, author: Claude Opus 5.5)

Review only. Do not edit, commit, push, deploy, or start subagents.

- Repo: /Users/abhayp/src/tokei-worktrees/2026-11-14-site (website repo, branch `redesign/2026-11-14`).
- Base: `master` (`git merge-base HEAD master`). See: `git diff master...HEAD` and `git status --short`.
- Intent: the cinematic redesign per `/Users/abhayp/src/tokei-macos/tasks/patch-bibles/2026-11-14.md`
  §"Abhay's answers" 4, §5 WP-W (AC 1–8) and §7 (burn counts plan usage only). Author's claims:
  `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/W-site.result.md` (round 1 and round 2a: next 16.4.3).
- Out of scope: the app, the CLI; a later round 2b will reconcile strings with the merged app.

Read surrounding code. Find bugs, broken behaviour, mismatch with intent. Pay special attention to: the build gates
actually failing on bad input (copy, eyebrows, budget) and not being bypassable; the hero film player (Reduce Motion
and Save-Data never fetch the film, pause control, offscreen pause, no layout shift, poster LCP); hydration errors or
server/client mismatch in the prerendered page; scroll-triggered scenes (final frame without JS, reduced motion,
no stuck invisible content if JS fails); accessibility (focus order, contrast, alt text, labels for the faux UI so
screen readers do not read garbage); mobile 390 layout; copy that overclaims (global leaderboard, rewarding overage,
facts the app does not do); the `next` bump's lockfile change; anything that would break `vercel --prod` (static
export, headers, missing assets).

Rerun the covering checks yourself and report each command with its exit code: `corepack pnpm install
--frozen-lockfile`, `corepack pnpm build` (all gates), `corepack pnpm test:gates`. You may run `corepack pnpm start`
on a free port and fetch the page with curl to check the served HTML; stop the server and confirm with
`lsof -nP -iTCP -sTCP:LISTEN` that nothing of yours listens. Do not deploy.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug users will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/W-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands you
ran with exit codes. Then print `TOKEI_W_REVIEW_DONE`.
