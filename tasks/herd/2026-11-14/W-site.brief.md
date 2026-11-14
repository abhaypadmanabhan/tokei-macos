# Brief WP-W · Website, cinematic redesign (Claude Opus 5.5)

cd /Users/abhayp/src/tokei-worktrees/2026-11-14-site — work ONLY in this directory (website repo, branch
`redesign/2026-11-14`). Exceptions: your result file at the absolute path below; proof media under
`~/Library/Developer/TokeiWork/proof/site/`; READ-ONLY looks at `~/src/tokei-macos/AIUsageDashboard` (the app's
real UI, colors, copy, springs) and `~/src/Voxi/landing` (the process reference). Never edit
`~/src/tokei-macos/website` (it holds uncommitted deletions that are not ours).

## Read first
1. `/Users/abhayp/src/tokei-macos/tasks/patch-bibles/2026-11-14.md` §"Abhay's answers" (answer 4 is your
   direction: bold cinematic, Higgsfield hero film, real Tokei UI rebuilt in code), §3, §5 WP-W (acceptance with checks).
2. This repo's `AGENTS.md` (Next.js 16 has breaking changes: read `node_modules/next/dist/docs/` for anything you touch).
3. `~/src/Voxi/landing/README.md` and its `scripts/check-copy.mjs`, `check-budget.mjs`, `prerender.mjs`.
4. Load skills: `stageshow` (faux UI that matches the real app), `motion-film` (hero film brief + QA).
5. The app's real UI: `~/src/tokei-macos/AIUsageDashboard/AIUsageDashboardApp/UI/**`, `PadzyTheme.swift`,
   `docs/07-padzy-theme.md`, `Core/Game/BurnSnapshot.swift` (badge titles + rules verbatim),
   `Core/Maxxer/MaxxerScorecard.swift` (tier names). Current app pictures: the existing site components
   (`components/app-window.tsx`, `tokei-gauge.tsx`, `dashboard-card.tsx`) are a starting point.

## Tools
- Paper MCP (connected): load its guide first (`get_guide({topic:"paper-mcp-instructions"})`), create the file
  "Tokei web 2026-11", design desktop 1440 + mobile 390 artboards, screenshot-review, then build.
- Mobbin via Composio CLI: `composio search "<query>"` then `composio execute MOBBIN_MCP_SEARCH_SECTIONS -d '{...}'`
  (schema in `~/.composio/tool_definitions/<SLUG>.json`).
- Higgsfield via Composio CLI: `HIGGSFIELD_GENERATE_SEEDANCE_2_5_TEXT_VIDEO` / `HIGGSFIELD_GENERATE_VIDEO_FROM_IMAGE` /
  `HIGGSFIELD_GENERATE_SOUL_V2_IMAGE` + `HIGGSFIELD_GET_REQUEST_STATUS`. Abhay approved Higgsfield for this work.
  Read each schema first; estimate credits before generating; at most 3 video generations; log credits in the result.
- Package manager: `corepack pnpm` (pnpm is not on PATH). No new runtime dependencies unless a gate needs a
  dev-only tool already in the lockfile; adding any package needs its exact name, maintainer and install scripts
  checked and noted in the result.
- Screenshots: headless Chrome/Playwright already used by the repo or `npx` tools in the lockfile; if none exist,
  use macOS `screencapture` of a Chrome window. Stop every dev server you start (check `lsof -nP -iTCP -sTCP:LISTEN`).

## Rules
- No deploy. The orchestrator deploys after review and after the 0.12.0 DMG exists.
- Commit in slices on your branch.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/W-site.result.md`:
line 1 `STATUS: READY` or `STATUS: BLOCKED`; per AC (1–8): what you did, the check, exact commands and output lines,
proof file paths; Mobbin refs with what each gave; Higgsfield jobs, prompts and credits; commits
(`git log --oneline master..HEAD`); known gaps. When complete, print exactly: `TOKEI_W_DONE`
