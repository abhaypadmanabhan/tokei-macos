STATUS: READY

# WP-W · Website, cinematic redesign: result

- Worktree `~/src/tokei-worktrees/2026-11-14-site`, branch `redesign/2026-11-14`, 4 commits on `master`. Nothing deployed.
- Proof root (not in git): `~/Library/Developer/TokeiWork/proof/site/` (`paper/`, `mobbin/`, `film/`, `final/`; earlier rounds `shots-r1..r6` show the bugs found and fixed).
- Brief sha256 verified before starting: `f860411f80814767e2a19877a542a66949aab42516e9b3b0ea505e9dde242a98`.
- Bible §7 (burn eligibility) applied: the page says "Only usage on your flat-rate plans counts. Overage, credits and API keys never score." and the agents section says "never at credits or overage". The copy gate now refuses any sentence naming overage, credits, API keys or extra usage without a negation, and any "buy/add credits" nudge.

## Commits (`git log --oneline master..HEAD`)
```
80f02b2 docs(site): what the build refuses to ship, where the page's facts come from
fda4a8b feat(site): cinematic redesign with the real Tokei UI rebuilt in code
d5d581e feat(site): the ember hero film and its player
8e4bb4d build(site): copy and budget gates for the prerendered home page
```

## AC1 · Paper first
- Paper file "Tokei web 2026-11" (https://app.paper.design/file/01M7CM343WR7QZAQHQDBSSJQTJ): 8 desktop artboards at 1440 and 8 mobile at 390, one per section (hero, menu bar, use it or lose it, streaks and badges, value tiers, agents, privacy, download). Each reviewed by screenshot and fixed before code (orphaned headline words, a dropdown floating with an empty band, a terminal and panel telling contradicting stories, a compact burn strip that wrapped).
- Check: exported PNGs, 16 files: `proof/site/paper/d1-hero-1440.png` … `d8-download-1440.png`, `m1-hero-390.png` … `m8-download-390.png`.

## AC2 · Mobbin references (7 searches via `composio execute MOBBIN_MCP_SEARCH_SECTIONS` / `_SCREENS`, 42 results; raw JSON, images and contact sheets in `proof/site/mobbin/`)
1. Perplexity Personal Computer, "Download it on any Mac" (section 9a743442): full-bleed generated plate as the hero ground, copy in the dark part, one CTA. Took the hero structure.
2. Perplexity, "Available now" (0c2e224c): the closing download over the same cinematic world, requirements as one caption line. Took the closing section returning to the film still.
3. Linear, "Built for the future. Available today." (3694f08d): two-button close (primary + secondary). Took Download + GitHub as the only pair.
4. Monologue, "Think out loud. Work faster." (8bfbd9f2): a small Mac utility sold with one short confident headline. Took the headline scale and restraint.
5. Mindvalley Achievements (iOS screen f81f0d35): recent vs locked badges, locked ones dimmed with progress. Took locked badges with a progress ring and the rule.
6. Lyft "Your badges" (iOS screen a90b544f): a just-earned badge marked new, short status line under each title. Took "Unlocked today" on the badge that unlocks.
7. How We Feel "Three days in a row!" (iOS screen 0d51df84): the streak as one huge numeral beside its sentence. Took the 88 px mono "11 / days in a row".
8. Apple Fitness Move ring (iOS screen 17983edf): a ring on dark that keeps going. Took the second, lighter lap past 1×.
9. Graphical "Download it directly, or install via shadcn" (section 1ac17256): one terminal window, one command, short status lines. Took the `tokei mcp install` moment.

## AC3 · Hero film (Higgsfield through Composio)
- Jobs (all logged with request, response and status JSON in `proof/site/film/`):
  - `HIGGSFIELD_GENERATE_SEEDANCE_2_5_TEXT_VIDEO` ×2: refused before submitting ("Seedance 2.5 pricing description changed or is invalid; no generation was submitted"), no charge. `HIGGSFIELD_GENERATE_SEEDANCE_2_TEXT_VIDEO` and `HIGGSFIELD_ESTIMATE_SOUL_V2_COST`: "not available on the instant account". So the film went still first, then image-to-video.
  - Still: `HIGGSFIELD_GENERATE_SOUL_V2_IMAGE` (request 01a1d93f-49d8-…), 1080p 16:9, prompt in `film/soul1.json` (pink-red embers rising from coals in near-darkness, dark upper left, no text/logos/people). Charged 0.006 USD.
  - Video 1 of 3: `HIGGSFIELD_GENERATE_VIDEO_FROM_IMAGE` (01a1d93f-ea05-…), same image as first and last frame for a native loop, prompt `film/vid1.json`. Came back nearly frozen (mean frame-to-frame change 0.52 of 255). Rejected. 0.125 USD.
  - Video 2 of 3: (01a1d942-7b71-…), no end frame, "steady updraft" prompt `film/vid2.json`. Real motion but builds to a full blaze behind the headline (brightness 51 to 98). Kept as fallback. 0.125 USD.
  - Video 3 of 3: (01a1d945-f036-…), "no flames, same brightness" prompt `film/vid3.json`. Still escalates, but the cleanest ember column. Used. 0.125 USD.
  - Credits: Composio instant bills in dollars; it never reported a Higgsfield credit figure and the estimator is blocked. Total charged 0.381 USD (0.006 + 3 × 0.125). Estimate given before generating (Higgsfield's own pricing post, unverified): about 128 credits for 8 s at 1080p on Seedance 2.5, which was never charged.
- Edit (ffmpeg): video 3 slowed to 0.7× with motion interpolation, last 1.25 s crossfaded into the first 1.25 s (a seamless 6.33 s loop that reads as burn, blaze, reset), highlights tamed (peak average brightness 63/255), composition shifted right so the blaze sits beside the headline, not behind it. Master `film/master-loop.mp4`, contact sheet `film/sheet3/master-contact.jpg`.
- Checks (ffprobe/ffmpeg; the motion-film `verify_film.py` could not run, numpy is not installed):
  - `hero-burn.mp4` h264 1280×720 24 fps 152 frames 6.333 s 1,316,620 B, no audio track, 0 decode errors.
  - `hero-burn.webm` vp9 1280×720 24 fps 6.334 s 1,270,088 B, no audio track, 0 decode errors.
  - Total 2.59 MB (≤ 3 MB). Poster `hero-burn-poster.webp` 33,646 B (≤ 150 KB).
  - Loop seam: brightness step across the loop point 0.61/255, below the largest ordinary frame step 0.92/255; no flashing (max frame-to-frame brightness change < 1 level).
- Player (`components/hero-film.tsx`): muted, loop, playsInline, preload none; the server renders the poster only; the film is fetched after hydration, never under Reduce Motion or Save-Data; pauses off screen; one Pause/Play button. Proof from the final pass: normal motion → `film={display: block, paused: false, currentSrc: hero-burn.webm, filmRequests: [hero-burn.webm], pauseButton: true}`; reduced motion → `film={display: none, paused: true, filmRequests: [], pauseButton: false}` (poster only, zero film bytes).

## AC4 · Real Tokei UI in code
- Sources copied, not paraphrased: badge titles and rules from `Core/Game/BurnSnapshot.swift` in `allCases` order (all 13 rendered), tier names and lines from `UI/Value/ValueView.swift`, tier bounds from `MaxxerValueEngine.tier(for:)`, sample numbers from `BurnSnapshot+Sample.swift`, agent tints from `AgentTint.swift`, the Anthropic and Cursor marks as their SVG paths and the Codex mark as its PNG from `Assets.xcassets/ProviderMarks`, colours from `PadzyTheme.swift` (`#131316/#1D1D22/#ECECF1/#FF3B70`; `#6E6E78` is kept only where it is not text, since it fails 4.5:1 for page text). `lib/burn.ts` names each source file.
- Scenes (`components/scenes/`): menu bar dropdown with the burn strip (ring past 1× as a second lighter lap, `$14.62`, 11-day streak, "Codex 5-hour · 62% left · 41 min"), quota gauges with pace ticks plus the WP-A nudge copy verbatim, burn ring + streak + records + 13 badges with "Ran it dry" unlocking (halo once, static highlight under Reduce Motion), tiers Idle → Goblin mode with the marker riding the fill (vertical gauge on phones), `tokei mcp install --client codex` and `tokei burn` typed in a terminal plus the Settings "Connect agents" row connecting Cursor with one press.
- Motion: every scene renders its final frame on the server; `components/reveal.tsx` arms it below the fold and plays it once in view. Only transform and opacity move (ring laps are half-rings rotated inside half masks; numbers roll on digit drums; fills translate). Timing uses the app's `PadzyMotion`: ease-out, 200 to 300 ms per move, sequenced with delays.
- Check: mid-play vs final frames `final/d1440-03-burn-midplay.png` (ring empty, `0.00×`) vs `final/d1440-03-burn.png` (ring 1.51×, badge unlocked); `final/d1440-05-agents-midplay.png` vs `final/d1440-05-agents.png`. Reduced motion: every scene reports `static` and shows its final frame (`final/d1440-reduced-*.png`, `final/m390-reduced-*.png`).

## AC5 · Story and copy
- H1 "You pay a flat rate. Burn all of it." Sections in order: hero film + headline + download · one click from the menu bar · use it or lose it · streaks, records and badges · from idle to goblin mode · your agents can see it too (MCP, one-click connect) · nothing leaves your Mac · stop leaving it on the table (download). The leaderboard is described only as your own agents and best days.
- Check: `check-copy: PASS (264 text nodes, 815 words of copy)`; the gate's tests reject each banned pattern (below).

## AC6 · Gates in `pnpm build`
- `package.json` build: `node scripts/check-no-eyebrows.mjs && next build && node scripts/check-copy.mjs && node scripts/check-budget.mjs`. Any failing gate fails the build (exit 1).
- Both new gates failed on the 0.11 page first (19 copy problems; initial JS 229.6 KB), so they can fail on the real artifact. During the build they also failed twice for real reasons and were fixed: the eyebrow gate caught "41 min"/"19 h" starting a text run; the budget gate caught initial JS 195.5 KB and first load 1008 KB.
- Command: `corepack pnpm install --frozen-lockfile && corepack pnpm build` (clean `.next`), output lines:
  ```
  Lockfile is up to date, resolution step is skipped
  check-no-eyebrows: 19 files, no eyebrow labels
  ┌ ○ /    ○  (Static)  prerendered as static content
  check-copy: PASS (264 text nodes, 815 words of copy)
  check-budget: initial JS 147.6 KB of 150.0 KB; first load 755.0 KB of 1000.0 KB; film 2586.7 KB of 3000.0 KB; poster 33.6 KB of 150.0 KB
  check-budget: PASS
  ```
- Gate tests: `corepack pnpm test:gates` → `check-no-eyebrows self-test: 17 fixtures ok`, `# pass 18 # fail 0` (each copy rule, attribute text, missing/hidden H1, JS/film/poster over budget, a missing asset, the noModule polyfill excluded, style-attribute images counted).

## AC7 · Proof (headless Google Chrome over CDP, `pnpm start`, script in my scratchpad; server stopped after each run, `lsof -nP -iTCP:3417 -sTCP:LISTEN` → 0)
| Pass | Console errors | Smallest sans / mono | Body | Ground | Focus ring on tab stops |
|---|---|---|---|---|---|
| 1440 | 0 | 15 / 15 px | 18 px | rgb(19,19,22) | visible on all 4 |
| 390 | 0 | 15 / 14 px | 18 px | rgb(19,19,22) | visible on all 4 |
| 1440 reduced motion | 0 | 15 / 15 px | 18 px | rgb(19,19,22) | visible on all 4 |
| 390 reduced motion | 0 | 15 / 14 px | 18 px | rgb(19,19,22) | visible on all 4 |
- No pure white ink found (`whiteInk: []`); ground is `#131316` plus film grain. Contrast (computed): ink 15.7:1, ink-2 10.7:1, ink-3 6.7:1, accent text 7.0:1, dark text on the accent button 5.4:1, "Connected" green 8.3:1.
- Files (`proof/site/final/`, 49 PNGs + 4 JSON reports): `<pass>-00-top.png`, one per section `-01-menu-bar` … `-07-download`, mid-play frames, `-focus-nav.png`, `-full.png`, `<pass>-report.json`.

## AC8 · Version and download link
- `lib/site.ts` holds `version` once; `downloadUrl` is built from it (`Tokei-${version}-arm64.dmg`). Still 0.11.0; the orchestrator bumps it to 0.12.0 at release. Body copy never names a version (the copy gate enforces it; the footer's old `v0.11.0` is gone).

## Security gate
- `SECSCAN_BASE=master ~/agent-kit/bin/secscan <worktree>` → `VERDICT: INCOMPLETE`, 3 commits scanned, no FLAG lines (no secrets).
- `GAP pnpm audit failed: no JSON from the audit (offline?)`: not offline; `pnpm` is not on PATH for secscan (only `corepack pnpm`). Ran it directly: `corepack pnpm audit` → 118 advisories (10 low, 58 moderate, 44 high, 6 critical). All pre-existing: `git diff master..HEAD -- pnpm-lock.yaml` is empty.
- Needs a decision before `vercel --prod`: the lockfile pins `next@16.2.10`, which has critical advisories (unauthenticated remote code execution in the Image Optimization API, GHSA-2xp9-vwfh-vxw4 and GHSA-2464-fhr4-w9xw; in `next/og`, GHSA-vcvr-r3jv-pc5j; in `use cache`, GHSA-673q-mjm6-r5xr), all fixed by `next >= 16.4.1`. In plain terms: someone could send a crafted request to the deployed site's image endpoint and run code on the server. This page uses none of `next/image`, `next/og` or `use cache`, but the image endpoint exists on a Next deployment regardless. The live 0.11 site has the same exposure today. Recommendation: bump `next` to 16.4.1 or later in its own commit (a dependency change outside this brief's scope, so it waits on the orchestrator/Abhay), rebuild, rerun the gates, then deploy. `proxy-addr` (critical) arrives through the `shadcn` CLI, which the page does not import.

## Known gaps
- Initial JS is 147.6 of 150 KB: Next.js 16 + React 19 alone are about 145 KB gzip, so any new client code will trip the budget. (Was 229.6 KB on 0.11: GSAP, the shader field and tailwind-merge are gone from the client path.)
- The terminal output for `tokei mcp install` and `tokei burn`, and the burn strip layout, follow the WP-B/WP-C acceptance text, not their built output (I stayed out of other lanes' worktrees). Reconcile the strings and the strip against the merged app before deploy.
- "Ran it dry" is shown unlocking today; `BurnSnapshot.sample` has it unlocked 12 days ago. Chosen so one badge visibly unlocks; titles and rules are verbatim.
- "Share a card if you want to brag" relies on WP-C AC4 (share card). Drop the line if that ships later.
- The two nudges/day and one-switch line relies on WP-A AC9 and WP-C AC5.
- Not checked: Safari and a real iPhone (headless Chrome only; Chrome picked the WebM, so the MP4 was verified with ffmpeg, not played in a browser), a screen-reader pass, Lighthouse. No screen recording of the animations (mid-play frames instead).
- The stageshow kit was not used: its cursor-driven Stage would add client JS the budget cannot take; the scenes are rebuilt from the Swift source following its framing and restraint rules.
- `app/icon.png` (223 KB, pre-existing) is the largest single item in the first load.
- Cross-model review (Codex Sol per bible §1) not done here; that is the orchestrator's round.
- Lessons recorded: L022 (Tailwind v4 layers and the `.ring` name collision), L023 (`next start` serves the stale build after a rebuild), L024 (Higgsfield via Composio instant behaviour and charges).

## Round 2a · next 16.2.10 → 16.4.3 (security, authorized by the orchestrator)
- Commit `ff79ef5 build(site): next 16.2.10 -> 16.4.3 for the remote code execution fixes` (one commit: `package.json` + `pnpm-lock.yaml`).
- Package check: `next@16.4.3` published 2026-10-23T13:40:24Z (`pnpm view next time`), maintainers vercel-release-bot / zeit-bot and two Vercel staff, no install scripts (only `start`).
- Only direct dependency that changed: compared the lockfile `importers` block before/after, 19 direct deps, one change (`next 16.2.10 → 16.4.3`). The lockfile also moves next's own sub-dependencies (its pinned `postcss 8.4.31 → 8.5.23`, optional `sharp 0.34.5 → 0.35.5`, `nanoid 3.3.20`) and re-keys `ajv-formats` peer entries.
- Docs read (`node_modules/next/dist/docs`, every `v16.3`/`v16.4` history row): nothing changed in what the site uses (next/font, metadata and viewport, icon and OG image files, static prerender, plain img/video, Tailwind through PostCSS). Three rows touch the build or tooling, none change the page:
  - 16.3 Turbopack file-system cache on by default for builds (under `.next`; I build clean).
  - 16.3 `enablePrerenderSourceMaps` default true (error traces during prerender only; generates nothing).
  - 16.3/16.4 `agentRules`: `next dev` (not build or start) creates or updates a managed "This is NOT the Next.js you know" block in `AGENTS.md` when it detects an agent. Expect an uncommitted `AGENTS.md` change after a dev session in this repo; set `agentRules: false` later if unwanted. Not changed here (one-commit version bump).
- Clean build, every gate: `rm -rf .next && corepack pnpm install --frozen-lockfile && corepack pnpm build`
  ```
  check-no-eyebrows: 19 files, no eyebrow labels
  ▲ Next.js 16.4.3 (Turbopack)
  ┌ ○ /    ○  (Static)  prerendered as static content
  check-copy: PASS (264 text nodes, 815 words of copy)
  check-budget: initial JS 137.3 KB of 150.0 KB; first load 744.8 KB of 1000.0 KB; film 2586.7 KB of 3000.0 KB; poster 33.6 KB of 150.0 KB
  check-budget: PASS
  ```
  `corepack pnpm test:gates` → `check-no-eyebrows self-test: 17 fixtures ok`, `# pass 18 # fail 0`. Initial JS fell from 147.6 to 137.3 KB.
- Headless proof (`pnpm start`, Chrome over CDP, server stopped after; `lsof` → 0 listeners), files in `proof/site/round2a/`:
  - 1440: console errors 0, smallest sans/mono 15/15 px, body 18 px, ground rgb(19,19,22), film playing (WebM), all five scenes played, focus ring on every tab stop.
  - 390: console errors 0, smallest sans/mono 15/14 px, body 18 px, film playing, all scenes played, focus visible.
  - 1440 reduced motion (extra): console errors 0, film hidden and never requested, every scene on its final frame.
  - Visual check `proof/site/round2a/sanity.png` (hero, badges, agents): unchanged from round 1.
- `corepack pnpm audit`, before → after: critical 6 → 1, high 44 → 34, moderate 58 → 49, low 10 → 9. Cleared: every `next` advisory (critical GHSA-2xp9-vwfh-vxw4, GHSA-2464-fhr4-w9xw, GHSA-vcvr-r3jv-pc5j, GHSA-673q-mjm6-r5xr, GHSA-p293-qw3h-jr36; high GHSA-6gpp-xcg3-4w24, GHSA-89xv-2m56-2m9x, GHSA-cjq9-62q9-8jv4, GHSA-m99w-x7hq-7vfj, GHSA-p3m5-59mp-jv5r, GHSA-p9j2-gv94-2wf4), plus postcss GHSA-6g55-p6wh-862q and three sharp highs. New advisories: none.
- secscan (`SECSCAN_BASE=master`, run with a `pnpm` shim on PATH from `corepack enable --install-directory <scratchpad>/bin` so the audit step runs this time): `VERDICT: FLAG`, `AUDIT pnpm: critical 1, high 34, moderate 49, low 9`, `VULN high/critical while this branch changed pnpm-lock.yaml: @modelcontextprotocol/sdk, body-parser, brace-expansion, browserslist, fast-uri, ip-address, js-yaml, nanoid, postcss, proxy-addr, source-map-js, systeminformation; confirm none came from this change`. Checked: comparing every high/critical (module, advisory, version, dependency path) before and after gives 0 that are new. The three high paths still running through `next` (source-map-js 1.2.1 via postcss; browserslist 4.28.5 via styled-jsx → @babel/core, two advisories) have the same versions and paths on `master`. The remaining critical, `proxy-addr` GHSA-jqcg-44mw-7w3h, comes through the `shadcn` CLI, which the page never imports. All inherited; none came from this change.
- Round 2b (reconcile with the merged app UI and CLI output) not started.

## Round 2b · review r1 fixes (W-fix-r1.md, W-review-r1.md)
| Id | Commit | What changed | Check |
|---|---|---|---|
| S2 should | `af67270` | `scripts/lib/html.mjs` also returns every block element's whole text read across inline descendants; `check-copy.mjs` runs its rules on those blocks, sentence by sentence. | Reviewer fixture added to `gates.test.mjs` first: `not ok … split across inline tags` (and a false positive on `Overage <strong>never</strong> scores.`) before the fix, both pass after. Reviewer command A now: `gate exit=1`, `[global leaderboard promise] text in <p>: Climb the global leaderboard.` |
| S1 should | `66e7ed4` | The burn note now reads: "Burn counts usage on your plans, the agents you pay a flat monthly price for. Pay-per-token API keys never count, and nudges never point you at paid overage. Claude's extra usage is billed inside the same logs, so Tokei can't separate it yet." The agents note ("never at credits or overage") is about where agents are pointed and stays. No other page line mentions overage, credits, API keys or extra usage (grep over app, components, lib). The gate treats can't/cannot/doesn't/won't/isn't as negations. | Test: these exact sentences pass; "Claude's extra usage counts toward your streak." still fails. Build: `check-copy: PASS (264 text nodes, 844 words of copy)`. Rendered at both widths: `proof/site/round2b/note-check.png`. |
| S3 nit | `7c8fdb5` | `check-budget.mjs` fails when a local `<video src>` or `<source src>` the page names does not exist; the film still stays out of the first-load total. | Test with the reviewer's fixture (failed first, passes after). Reviewer command B now: `missing-film-source exit=1`, `FAIL, page asks for /film/gone.webm but no file serves it; page asks for /film/gone.mp4 but no file serves it`. Real build still `check-budget: PASS`. |
| S4 nit | `b208bbb` | `hero-film.tsx`: the first switch to Reduce Motion pauses the film, disconnects the on-screen observer and blocks every play path for the rest of the visit. | Chrome check (`proof/site/round2b/s4-check.json`): start `{paused: false, button: true}` → Reduce Motion on `{paused: true, display: none, button: false}` → off again, then scrolled away and back `{paused: true, button: false}`, no errors, `verdict: PASS`. |
| Dependency hygiene | `1b9365f` | Removed `shadcn` from dependencies. Nothing imports it: no source import, `globals.css` imports only `tailwindcss`, no config uses it; `components.json` is the shadcn CLI's own settings file (left in place). Only direct-dependency change is `shadcn` → removed; 261 packages leave the lockfile, no package version is added or changed (checked by diffing the lockfile package sets). | `corepack pnpm audit` before → after: critical 1 → 0, high 34 → 6, moderate 49 → 2, low 9 → 0, no new advisories. The last critical, `proxy-addr` GHSA-jqcg-44mw-7w3h, is gone. |

Checks on HEAD `1b9365f`:
- `rm -rf .next && corepack pnpm install --frozen-lockfile && corepack pnpm build`: `check-no-eyebrows: 19 files, no eyebrow labels`, `▲ Next.js 16.4.3`, `○ (Static) prerendered as static content`, `check-copy: PASS (264 text nodes, 844 words of copy)`, `check-budget: initial JS 137.3 KB of 150.0 KB; first load 745.0 KB of 1000.0 KB; film 2586.7 KB of 3000.0 KB; poster 33.6 KB of 150.0 KB`, `check-budget: PASS`.
- `corepack pnpm test:gates`: `check-no-eyebrows self-test: 17 fixtures ok`, `# pass 22 # fail 0`.
- Headless proof (`proof/site/round2b/`): 1440 console errors 0, smallest sans/mono 15/15 px, film playing, all scenes played, focus visible; 390 console errors 0, 15/14 px, film playing, all scenes played, focus visible. Servers stopped (`lsof -nP -iTCP:3417 -sTCP:LISTEN` → 0).
- secscan (`SECSCAN_BASE=master`, `pnpm` shim on PATH): `VERDICT: FLAG`, `AUDIT pnpm: critical 0, high 6, moderate 2, low 0`, `VULN high/critical while this branch changed pnpm-lock.yaml: browserslist,nanoid,postcss,source-map-js; confirm none came from this change`. Checked against the master-lockfile audit: all 8 high (advisory, version, path) combinations are on `master` unchanged, 0 new. They sit in build tooling (Tailwind's PostCSS chain, Next's postcss and styled-jsx Babel), not in the shipped static page.
- Not in this round's list, left as found: the trailing blank line at `app/globals.css:210` the reviewer noted as formatting only; other unused dependencies (`gsap`, `@gsap/react`, `shaders`, `@base-ui/react`, `lucide-react`, `clsx`, `tailwind-merge`, `class-variance-authority`, `tw-animate-css`) are no longer imported by the page.
- Round 2c (reconcile strings and visuals with the merged app and CLI) not started.

## Round 2c · match the page to the real app and CLI (W-round-2c.md)
Sources read (read only): the captures in `proof/burn-ui/captures/` (`dropdown-sample-dark.png`, refreshed with live data mid-round; `burn-sample-dark-bottom.png`, `share-card.png`, `settings-burn-nudges-light.png`) and `captures-real/real-burn-dark-*.png`; the Burn UI source on `patch/2026-11-14/burn-ui` read through git objects (`UI/Burn/BurnCopy.swift`, `BurnSections.swift`, `BurnStrip.swift`, `BurnRing.swift`; that lane's worktree untouched); on `dev`: `TokeiCLI/StatusFormatting.swift` (`BurnFormatting`), `TokeiCLI/AgentCommands.swift`, `Core/Connect/AgentConnection.swift`, `Core/Agent/AgentSnapshot.swift` (`advice`, `windowName`), `Core/Notifications/BurnNudges.swift`, `UI/Settings/AgentConnectSection.swift`, `UI/Components/PaceCopy.swift`, README "Agents".

| Item | Commit | What changed | Check |
|---|---|---|---|
| Gate prerequisite | `a0c8e0d` | The copy gate's buy-nudge rule skips a buy directly negated by never/don't/do not, so the CLI's own "Never buy credits or overage to burn it." can appear verbatim. | Test first (failed, then passed): that line passes; "Never stop: buy more credits to score." still fails. |
| 1 Burn strip | `c025be4` | Dropdown rebuilt line for line from the capture: ring + "1.5×" "of today's goal", "$14.62" "on your plans today", filled flame + "11-day streak" "goal hit today", hourglass + "Codex 5-hour · 62% left · 42 min", "8.07M" "tokens today · incl. cache", Plan value "2.3× Maxxing", Tightest quota "61%" with "Claude Code · weekly window" and "↘ 28 pts of room · Lasts to reset" (PaceCopy format), Tokens/Quota switch, Claude Code / OpenAI Codex / Cursor, accent "Open Tokei", "Quit ⌘Q". Ring drawn like `BurnRing.swift`: completed lap at 40% accent, current lap full accent with round caps over a surface gap. | `proof/site/round2c/compare-dropdown.png` (site panel at 2x beside the app capture). Numbers stay the app's sample; the capture now shows live values (714M, 1.6×), the wording and order match. |
| 1 Burn section | `c025be4` | The site's Burn scene is now the app's Burn tab in the app's order: ring "1.5×" "of today's goal", "$14.62", "burned on your plans today, of a $9.68 goal", flame "11-day streak" "Goal hit today", "Share my week", "Your goal is break-even pace: your plans' monthly cost spread over this month's days.", "This week's agents" (rank, mark, name, $, tokens; plan products only per §7, so no Gemini row), "Records" 2×2 with dates (Nov 8, Nov 7, Oct 31, Nov 14). The burn note is the app's `eligibilityFinePrint` plus the nudge line. | `proof/site/round2c-final/burn-scene-1440.png`, `burn-scene-390.png`. |
| 1 Badges | `c025be4` | Badge cells follow `BadgeCell`: glyph, title, lock glyph while locked, the rule, then a thin progress bar with "72% there" or "Unlocked Nov 10" (dates from the sample relative to Nov 14). Glyphs are drawn look-alikes of the app's SF Symbols (flame, dollar circle, trend, crown, bolt, bolt circle, drop, calendar, 3/7/30 circles, stack, gauge); SF Symbols are licensed for Apple-platform apps only. The unlocking badge ("Ran it dry", Unlocked Nov 14) gets the app's celebration look: an accent outline that stays, plus one halo. | Same captures; numerals in the 3/7/30 glyphs are strokes, not text (the type-floor check flagged them as 9 to 10.5 px text first). |
| 2 Terminal | `c025be4` | Verbatim output: `Codex: connected tokei (/Applications/Tokei.app/Contents/Helpers/tokei mcp).` then `tokei burn`: "Use it or lose it", "OpenAI Codex 5-hour window has 62% left and resets in 41 min: run optional or batch work there first", "Claude Code weekly window has 39% left and resets in 19 h: run optional or batch work there first", "Streak: 11 days · today's goal hit", "Today: $14.62 API-equivalent value · goal $9.68 · 151%", "Use capacity already in your plan. Never buy credits or overage to burn it." No invented flags. Lines wrap like a terminal. (CLI says "41 min": `advice` floors minutes; the strip says "42 min": `BurnCopy.countdown` rounds up. Both are the real formatters at the same moment.) | `proof/site/round2c-final/agents-scene-1440.png`, `agents-scene-390.png`, `d1440-05-agents.png`. |
| 3 Connect agents | `c025be4` | "Connect agents", "Let your agents read usage and use plan capacity before it resets.", rows with name and status line (Claude Code / Codex "Connected" with plain "Disconnect"; Cursor "Detected" + "Connect", which presses and becomes "Connected" + "Disconnect"), "Install the tokei command". | Same captures; Reduce Motion shows the final frame (all connected). |
| 4 Share my week | `c025be4` | Shown as the app's outlined button in the Burn scene; the privacy row now says "Share my week makes a card you can copy or save." Nothing else promises sharing. | Copy gate PASS. |
| Phone fixes found in proof | `c025be4` | (a) The unbreakable helper path widened the agents grid cell past a 390 px screen, cutting the lead paragraph: `overflow-wrap:anywhere` on the terminal and `min-w-0` on grid children. (b) The badge halo ended held at 1.9× (fill-mode both), invisibly widening the page to 518 px so the fixed nav's Download button slid off-screen: the halo now settles back (fill backwards), smaller, clipped to its cell. | Added two checks to my proof script and ran them against the broken build first: "headline or paragraph past the screen edge" (3 hits) and "page wider than the screen after every scene played" (`page is 518 px wide on a 390 px screen`). Both 0 after the fix. Lessons L029, L030. |
| 5 Dependencies | `9d778e6` | Removed gsap, @gsap/react, shaders, @base-ui/react, lucide-react, clsx, tailwind-merge, class-variance-authority, tw-animate-css. Python scan of 37 source/CSS/config/script files: no import, require, `@import` or `@plugin` of any of them (only prose in `tasks/lessons.md` and a helper-name string in the eyebrow gate). 21 packages leave the lockfile, none added. Dependencies are now next, react, react-dom. | `pnpm audit` before → after: critical 0 → 0, high 6 → 6, moderate 2 → 2, low 0 → 0, no new or cleared advisories (the remainder is Tailwind's and Next's build tooling). |

Checks on HEAD `9d778e6`:
- `rm -rf .next node_modules && corepack pnpm install --frozen-lockfile && corepack pnpm build`: `check-no-eyebrows: 20 files, no eyebrow labels`, `▲ Next.js 16.4.3`, `○ (Static) prerendered as static content`, `check-copy: PASS (302 text nodes, 1056 words of copy)`, `check-budget: initial JS 137.3 KB of 150.0 KB; first load 749.4 KB of 1000.0 KB; film 2586.7 KB of 3000.0 KB; poster 33.6 KB of 150.0 KB`, `check-budget: PASS`.
- `corepack pnpm test:gates`: `check-no-eyebrows self-test: 17 fixtures ok`, `# pass 23 # fail 0`.
- Headless proof (`proof/site/round2c-head/`): 1440, 390, 1440 reduced, 390 reduced: console errors 0 in all four, smallest sans/mono 15/15 px (desktop) and 15/14 px (phone), no text or page wider than the screen, film playing (normal) or hidden and never requested (reduced), every scene played (normal) or on its final frame (reduced), focus ring visible. Servers stopped (`lsof -nP -iTCP:3417 -sTCP:LISTEN` → 0).
- secscan (`SECSCAN_BASE=master`, `pnpm` shim on PATH): `VERDICT: FLAG`, `AUDIT pnpm: critical 0, high 6, moderate 2, low 0`, `VULN high/critical while this branch changed pnpm-lock.yaml: browserslist,nanoid,postcss,source-map-js; confirm none came from this change`. Same 8 (advisory, version, path) combinations already shown to be on `master` in round 2b; this round's audit diff is empty.
- Not verified: the share card itself is not pictured on the page (only its button and one sentence); badges were never captured from the app (all real captures stop above them), so cells follow the source, not a screenshot; Safari and a real phone still unchecked.
- A proof-folder cleanup (`rm -f $F/*`) was blocked by the safety check for an unguarded variable; nothing was deleted, the final run went to a fresh folder, and older round folders are left as they were.
