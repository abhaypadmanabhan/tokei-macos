# Brief WP-W · Tokei website, fresh clean rebuild (Claude Opus)

cd /Users/abhayp/wt/lane3 — work ONLY in this directory (the website repo, branch `redesign/2026-11-15`, cut from
`master`). Exceptions: your result file at the absolute path below; proof media under
`~/Library/Developer/TokeiWork/proof/site-1115/`; READ-ONLY looks at `~/src/tokei-macos` (the app) and
`~/src/Voxi/landing` (the reference site). Never edit `~/src/tokei-macos/website` (it holds uncommitted deletions
that are not ours).

## Goal
Abhay's words: the Tokei website "needs to be good and clean like Voxi", "really production worthy with actual
app visuals", "nice components, animations". He chose a fresh rebuild; last night's dark cinematic page and its
film are retired. Done means a page a stranger trusts in five seconds: what Tokei is, a real picture of it, one
Download button.

## Read first
1. `~/src/tokei-macos/tasks/patch-bibles/2026-11-15.md` "Abhay's answers", §0 (what rivals do, what 0.13.0 adds), §3.
2. Load the `product-design` skill and follow it; it replaces Padzy OS, which is retired (no PP Neue Machina, no
   Inter, no numbered or mono kickers, no hairline-everything). Read its `references/web.md`, `motion.md`,
   `copy-and-slop.md`, and the vault notes `UI-UX/Typography.md`, `AI Design Tells.md`, `Checklists.md`,
   `Herdr Site Case Study.md`. Then `frontend-design` if your skill list has it.
3. `~/src/Voxi/landing/README.md`, `src/home/`, `src/claims.ts`, `scripts/check-copy.mjs`, `check-budget.mjs`:
   the bar for calm, and the pattern for claims that wait on a release gate.
4. This repo: `AGENTS.md` (Next.js 16 has breaking changes; read `node_modules/next/dist/docs/` for what you
   touch), `package.json` (the build runs the gates), `scripts/`, `tasks/lessons.md`.
5. The app, so every word and picture is true: `~/src/tokei-macos/CHANGELOG.md` (0.12.0, 0.11.0),
   `AIUsageDashboard/AIUsageDashboardApp/UI/**`, `App/ProofRoute.swift` (Debug launch arguments that open one
   screen for an own-window capture).

## Direction (the orchestrator's call; improve it in Paper, do not swap it for another concept)
- Feeling in the first 30 seconds: "calm, exact, on my side". A light page: a tinted off-white ground (never
  `#fff`), tinted near-black ink, Tokei pink `#FF3B70` kept as the one accent and used only on the Download
  button and one live detail (check it clears 3:1 as a fill and never use it for body text on the light ground).
  The app is dark, so real app captures sit on the light page as the dark objects; allow one dark chapter at most.
- Type: Switzer for body and UI, one display face from the arsenal for H1/H2 (Apfel Grotezk first choice), DM
  Mono only inside a terminal block. Body 18px, nothing under 15. Fonts self-hosted, no silent fallback.
- Hero: one headline, one sentence, one Download button plus one quiet secondary link, and one real capture of
  the app. Headline territory: the question the app answers ("Are you using the AI plans you pay for?").
- Sections, in this order, each with a real capture or a real output and no filler:
  1. Which plan next: Tokei ranks your plans and says where to send the next task (new in 0.13.0).
  2. Pace and value: whether you will use the quota before it resets, and the dollars you got from a flat rate.
  3. For your agents: the MCP server and `tokei` command, shown as a terminal block with the real CLI output.
  4. Burn: the streak and use-it-or-lose-it game, small.
  5. Light and private: a plain fact table (measured CPU and memory with the method, download size, price free,
     where data lives, permissions asked). Numbers that are not measured yet render their fallback.
  6. Supported agents (real marks already in `public/marks`), a short FAQ, the final Download, footer.
- Components worth making well: the nav with a Download that stays reachable; a capture frame (window chrome,
  2x, lazy, fixed aspect so nothing shifts); the terminal block; the fact table; one interactive piece, a small
  "which plan next" demo built in code whose ranking uses the same rule as the app, with fictional data.
- Motion: purposeful and quiet. Section reveals, number roll on the fact table, the demo's reorder spring, hover
  and press states on every control. Transform and opacity only, 120 to 250 ms, reduced motion shows final frames.
- Conditional claims: one file (like Voxi's `claims.ts`) holds every line that waits on 0.13.0 (the route
  feature, the `tokei route` output, the measured footprint numbers). `shipped: false` renders an honest
  fallback that is true of 0.12.0. The orchestrator flips them at release. One file holds the version and
  download URL; it stays on 0.12.0 until then.

## Real app visuals
- Use real captures of the real app, not redrawn UI. A Debug build plus `-TokeiProofRoute <route>` opens one
  screen; `~/Library/Developer/TokeiWork/proof/burn-ui/captures/` has last night's set to design with.
- Privacy: this is a public site. No capture may show this Mac's real account names, emails, home paths or real
  dollar and token figures. The UI lane is adding `-TokeiProofFixture demo` (fictional data) tonight; the
  orchestrator will hand you final captures under `~/Library/Developer/TokeiWork/proof/route-ui/site-captures/`.
  Until then, design and build with capture slots of the right size and use only captures you have checked are
  sample data (`-TokeiBurnSample` is); list every image you used and why it is safe.
- You may build a Debug app from `~/src/tokei-macos` into your own DerivedData
  (`-derivedDataPath ~/Library/Developer/TokeiWork/dd-site`) to look at screens. Do not touch the installed app.

## Tools
- Paper MCP: load its guide first, make a new file "Tokei web clean 2026-11-15", write a short brief (palette,
  type scale, spacing), design desktop 1440 and mobile 390 artboards, review by screenshot, then build from the
  Paper values (`get_jsx`, `get_computed_styles`), never from screenshots.
- Mobbin MCP: find real references before inventing a component (Mac utility and developer tool marketing
  pages: hero with product capture, fact or comparison table, terminal block, FAQ, footer). Layout references
  from research: hutch.coursion.studio (interactive demo of the real UI), chirpy.pro/press (fact table,
  unframed screenshots), leewaybar.app (one question as headline). Record each reference and what it gave.
- No paid media generation of any kind (no Higgsfield). No new runtime dependency; if a gate needs a dev tool,
  check its exact name, maintainer, age and install scripts and note it. Package manager: `corepack pnpm`.
- Remove what the rebuild retires (film files, unused components) so the repo ends smaller than it started.

## Acceptance criteria (each with its check)
1. Paper file exists with desktop and mobile artboards for every section. Check: exported PNGs in the proof folder.
2. `corepack pnpm build` passes with every gate on (eyebrow, copy, budget); gates updated for the new page, not
   weakened; `corepack pnpm test:gates` passes. Check: the output lines.
3. `~/agent-kit/bin/page-check --accent '#FF3B70' <local url>` passes at 390 and 1440. Check: its output.
4. Every capture is a real app capture with safe data; every claim is true of 0.12.0 or sits behind the claims
   file. Check: a table in the result: claim or image → source (file, command or changelog line).
5. Reduced motion, keyboard path with a visible focus ring, AA contrast, no layout shift from images or fonts.
   Check: page-check plus screenshots of the reduced-motion and focus states.
6. Screenshots of the built page at 1440 and 390, full length, and a side-by-side of the hero and two other
   sections showing one system (`tasks/lessons.md`). Check: files in the proof folder.
7. The H1 is in the prerendered HTML; initial JS and first load stay inside the budget gate. Check: gate output.
8. Every dev server you started is stopped. Check: `lsof -nP -iTCP -sTCP:LISTEN` shows none of yours.

## Rules
- No deploy, no push, no merge. Commit in slices on your branch. Never `--no-verify`.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-site.result.md`: line 1 `STATUS: READY` or
`STATUS: BLOCKED`; per AC (1-8) what you did, the check, exact commands and output lines, proof file paths; the
Mobbin references; the claims file's entries and their state; commits (`git log --oneline master..HEAD`); known gaps.
When the file is complete, run: `hc send t1d "W-site result written"`
