# Review brief WP-W · Website (reviewer: Codex GPT-6.1-Sol, author: Claude Opus)

Review only. Do not edit, commit, push, deploy, or start subagents.

- Repo: /Users/abhayp/wt/lane3 (website repo, branch `redesign/2026-11-15`). Base: `master`. See:
  `git diff master...HEAD` and `git status --short`.
- Intent: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-site.brief.md` (direction, AC 1-8). Author's
  claims: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-site.result.md`.
- Out of scope: the app and the CLI; visual taste (the orchestrator judges that from screenshots).

Read surrounding code. Find bugs, broken behaviour, mismatch with intent. Pay special attention to: the build gates
really failing on bad input (copy, eyebrows, budget) and not being bypassable or weakened against `master`; every
claim on the page being true of Tokei 0.12.0 (`~/src/tokei-macos/CHANGELOG.md`) or sitting behind the claims file
with a true fallback; images: any capture showing a real account name, email, home path or this Mac's real figures;
hydration errors or server/client mismatch; the interactive "which plan next" demo (keyboard use, screen reader
labels, reduced motion, no stuck state, its ranking matching the rule in the brief); section reveals that leave
content invisible when JavaScript fails or motion is reduced; focus order, contrast, alt text; the 390 px layout;
layout shift from fonts and images; font files that fail to load or fall back silently; dead files from the
retired page still shipped; the lockfile; anything that would break `vercel build --prod` and a prebuilt deploy.

Rerun the covering checks yourself and report each command with its exit code: `corepack pnpm install
--frozen-lockfile`, `corepack pnpm build` (all gates), `corepack pnpm test:gates`. You may run `corepack pnpm start`
on a free port and fetch the page with curl to check the served HTML; stop the server and confirm with
`lsof -nP -iTCP -sTCP:LISTEN` that nothing of yours listens. Do not deploy.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests or guards the intent does not need.
Other paths, rare cases, small perf, extra compat: nits.
blocker = intended case wrong. should = real bug users will hit, in intent. nit = rest.
blocker and should carry `Repro: <command> -> <output>` when code can show it; otherwise label it `reading`.

Write your reply to `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-review-r<N>.md` (N = round in the
prompt), first line exactly `VERDICT: APPROVE` or `VERDICT: CHANGES`, then findings as
`S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>` (stable ids across rounds), then the commands you
ran with exit codes. Then run: `hc send t1d "W review r<N> written"`
