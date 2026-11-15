STATUS: READY

# WP-W result: Tokei website, fresh clean rebuild

Worktree `/Users/abhayp/wt/lane3`, branch `redesign/2026-11-15`. Brief sha256 checked: 003558c9... (match).
Proof folder: `~/Library/Developer/TokeiWork/proof/site-1115/`.

## Waiting on a yes (guard-bash)

`guard-bash [large-delete]` blocked committing three deletions the brief asks for, and asks for Abhay's
approval of the exact command. Not overridden. They are deleted in the worktree, uncommitted:
`public/film/hero-burn.mp4` (1.3 MB), `public/film/hero-burn.webm` (1.3 MB) (the retired film) and
`public/tokei-mark.png` (223 KB, referenced nowhere). Nothing references any of them (`grep` of app,
components, lib). To finish: `git add public/film public/tokei-mark.png && git commit -m "build(site): drop the retired film"  # agent-ok:large-delete`
once Abhay says yes.

## Acceptance criteria

1. **Paper file** "Tokei web clean 2026-11-15" (https://app.paper.design/file/01M7FA6YVV8H95XB0J70MRP08R),
   artboards Desktop 1440 and Mobile 390, every section on both (hero, which plan, pace and value, agents
   chapter, burn, facts, supported, FAQ, close, footer). About 19 Paper calls used (budget note followed;
   no allowance error). Capture slots are dark placeholders at the captures' aspect.
   Exports: `paper/paper-desktop-1440.png`, `paper/paper-mobile-390@2x.png`. Built from `get_computed_styles`
   values (80/80 and 52/55 Apfel Grotezk -0.02em, 44/46 and 36/39 mobile, body 18/29, lead 22/32, stat 28,
   terminal 15/24, button 16x28 radius 8, chapter radius 24 padding 96/88).
2. **Build and gate tests.** `corepack pnpm build` (Node 22.23.1, corepack pnpm 12.18.0), full log `build.log`:
   ```
   check-no-eyebrows: 13 files, no eyebrow labels
   check-claims: PASS (3 claims, shipped: none; 4 captures checked)
   ✓ Compiled successfully in 1439ms
   check-copy: PASS (122 text nodes, 800 words of copy)
   check-budget: initial JS 137.0 KB of 150.0 KB; first load 566.6 KB of 1000.0 KB; film 0.0 KB of 3000.0 KB; poster 0.0 KB of 150.0 KB
   check-budget: PASS
   ```
   `corepack pnpm test:gates` (log `test-gates.log`): eyebrow self-test all ok; `# tests 38 # pass 38 # fail 0`.
   `tsc --noEmit` exit 0. Gates were made stricter, none weakened: new headline (the old "Burn all of it"
   check replaced), images must carry width and height, every `/shots/` image must be listed in
   `lib/captures.ts`; new `scripts/check-claims.mjs` (runs before `next build`): shipped claim without data,
   banned copy in any claim string shipped or not, capture without source/safety note/alt, missing file,
   size mismatch (reads PNG and WebP headers). Budget and film rules unchanged.
   `~/agent-kit/bin/prove-red node --test scripts/gates.test.mjs` → `prove-red: red on old code (1 test file(s) laid over the last commit; command exited 1).`
3. **page-check** `~/agent-kit/bin/page-check --accent '#FF3B70' http://localhost:3517/` (production build, `next start`):
   ```
   PASS @1440 no overflow, smallest text 15px, fonts loaded, 3 accent pairings clear
   INFO @1440 accent share of first screen: 1.3%
   PASS @720 no overflow, smallest text 15px, fonts loaded, 3 accent pairings clear
   PASS @390 no overflow, smallest text 15px, fonts loaded, 3 accent pairings clear
   ```
   First run failed on inline `tokei` code at 14.1px; fixed to 1em. Screens: `page-check/`.
4. **Every image and claim is real and sourced.** Table below.
5. **Reduced motion, keyboard, contrast, no shift.** Reduced motion: 0 elements armed under
   `prefers-reduced-motion: reduce` (CDP check), full page `shots/reduced-full-1440.png`, `reduced-full-390.png`
   (identical to the motion versions after scroll, as intended: final frames). Keyboard: skip link, nav, demo
   buttons (`aria-pressed`, live region announcing the top pick), FAQ `<details>`; focus ring 2px solid ink,
   offset 3: `shots/focus-tab3-1440.png` (nav link), `focus-demo-button-1440.png`, `focus-faq-390.png`.
   Contrast measured on the rendered page for every text element: lowest 4.95:1 (ink on the pink Download),
   next 5.81 (muted on panel), then 6.34; accent pairings pass page-check. No shift: every img has width and
   height (gate), Switzer and Apfel load through `next/font/local` with its Arial metric fallback, hero image
   eager with `fetchpriority=high`, others lazy. CLS not measured with a tool (see gaps).
6. **Screenshots**: `shots/full-1440.png` (1440x5716), `shots/full-390.png` (390x6682),
   `shots/side-by-side-hero-route-facts.png` (hero, which plan, facts at one width: same type scale,
   ground, rules and spacing). Demo after picking Friday: `shots/demo-friday-1440.png`. Social image:
   `shots/og-1200.png`, installed as `app/opengraph-image.png` and `app/twitter-image.png` (the old one was
   the retired dark style with uppercase mono labels).
7. **H1 prerendered, budget.** `grep` of `.next/server/app/index.html` finds "Are you using the AI plans you
   pay for?"; check-copy's H1 rule passes; initial JS 137.0 of 150 KB (baseline before this work 137.3),
   first load 566.6 of 1000 KB (baseline 749.4).
8. **Servers stopped.** Both `next start` runs on :3517 stopped; `lsof -nP -iTCP -sTCP:LISTEN` shows none of
   mine. Headless Chrome instances from the capture script exit with it.

## Images and claims, with sources

| Item on the page | Source | Why it is true or safe |
|---|---|---|
| Hero image `public/shots/burn.webp` (1800x1494) | `burn-ui/captures/burn-sample-dark-top.png`, Debug build, `-TokeiProofRoute burn -TokeiBurnSample YES` (2026-11-14) | All figures are `BurnSnapshot.sample`; no account, email or path visible (checked by eye) |
| `public/shots/value.webp` (1800x790) | `burn-sample-dark-middle.png`, crop rows 178 to 968 | Sample only |
| `public/shots/badges.webp` (1704x428) | `burn-sample-dark-bottom.png`, crop at 48,398 | Badge rules and sample progress |
| `public/shots/strip.webp` (600x236) | `dropdown-sample-dark.png`, crop at 20,86 | Only the sample burn strip; the rows below it showed this Mac's real token totals (714M) and were cut off |
| Agent marks `public/marks/*` | app `Resources/Assets.xcassets/ProviderMarks` | Real integrations the app reads (`ProviderID` cases) |
| Terminal `tokei burn` lines | `node scripts/cli-sample.mjs /Applications/Tokei.app/Contents/Helpers/tokei burn` (shipped 0.12.0 CLI, fictional snapshot via `TOKEI_SNAPSHOT_PATH`), exit 0 | Verbatim real output; data fictional |
| "CPU at rest, window closed 2.17%" | CHANGELOG 0.12.0: "idle CPU with the window closed 3.68 % → 2.17 %" (Release, audited Mac) | Measured, method shown |
| "Download 8.1 MB" | `gh release view v0.12.0`: `Tokei-0.12.0-arm64.dmg 8143876` | 8,143,876 bytes; lives in `lib/site.ts` beside the version |
| "Free", "open source", requirements | `lib/site.ts`, repo is public, project.yml deployment target 14.0, arm64 DMG | |
| "Notifications" is the permission asked | `Core/Notifications/NotificationEngine.swift` is the only `requestAuthorization`; Settings has alert levels and the nudge switch (CHANGELOG 0.11.0, 0.12.0) | |
| "Talks to your own providers, a public price list, update checks"; FAQ "Does anything leave my Mac?" | hosts in Swift source: api.anthropic.com, cursor.com, Google (Gemini quota), raw.githubusercontent.com (prices), Sparkle; Claude quota reads Claude Code's own sign-in via `/usr/bin/security` | The old page's "Keys never enter Tokei" was not true and is gone |
| "No account, no analytics, no Tokei server" | no analytics SDK; only Sparkle in project.yml packages | |
| "One folder on your Mac, readable only by you" | CHANGELOG 0.11.0 Security: files 0600 in a 0700 folder | |
| Pace tick, forecast, use-it-or-lose-it nudges, left on the table, value multiple, 13 badges, streak | CHANGELOG 0.10.0 (pace tick), 0.11.0 (run-out forecast), 0.12.0 (Burn tab, nudges, badges) | |
| Burn counts plans only; Claude Code, Codex, Cursor, Antigravity, Copilot | CHANGELOG 0.12.0 "Burn counts plan usage only" | |
| MCP one click for Claude Code, Codex, Cursor; `tokei mcp install`; refuses a different entry, keeps a backup | CHANGELOG 0.12.0 "Added: agents" | |
| "Which plan" fallback lead: flags the expiring window, marks the plan with most room, agents can ask | 0.12.0 Use it or lose it; route mark `RouteTargetPolicy` / `OverviewAgentGrid`; MCP `get_route_recommendation` (`tokei help` of 0.12.0) | |
| The demo's ranking | `lib/route.ts`: patch bible WP-B AC1 order, `ExpiringHeadroomFinder.Policy.standard` (25%, horizons), avoid at 85% (`RouteTargetPolicy`), countdown words ported from `BurnCopy.countdown`; made-up plans, labelled as such | WP-B is not merged yet (lane2 had no commits); check `lib/route.ts` against `RoutePlan` at release |

## Claims file (`lib/claims.ts`), all off

| Claim | State | Shipped renders | Fallback renders (true of 0.12.0) |
|---|---|---|---|
| `route` | `shipped: false` | "Tokei ranks your plans and says where to send the next task..." | "Tokei flags the window about to reset with room left, and marks the plan with the most room. Your agents can ask it the same question." |
| `routeCli` | `shipped: false`, `output: null` | terminal shows `$ tokei route` with `output` lines | terminal shows real 0.12.0 `tokei burn` |
| `footprint` | `shipped: false`, data null | rows "CPU while an agent works" (busyCpu, method) and "Memory" | row "CPU at rest, window closed 2.17%" |

At release: fill `routeCli.output` from `node scripts/cli-sample.mjs <0.13.0 tokei> route`, `footprint` from
WP-A's harness, flip the three, bump `version` and `downloadMB` in `lib/site.ts`, rebuild; the gate refuses a
flip without data. Final captures from WP-C can replace or join `lib/captures.ts` entries (each needs
`source` and `safe`, and the gate checks the size).

## Mobbin and research references
Recorded in `mobbin/references.md`: Cursor light hero (product window on a tinted field below one Download),
Rivian, Ghost and Daylight spec tables (label left, value right, hairline rows, numbers in the body face),
The Content Architecture (a real terminal as the dark object on a light page), Dabbit FAQ (Mac utility:
heading left, hairline accordion right), Norma closing band (one sentence and Download), plus the brief's
hutch.coursion.studio (interactive demo), chirpy.pro/press (fact table), leewaybar.app (question headline).

## Commits (`git log --oneline master..HEAD`)
```
5b5760d docs(site): README and a lesson for the rebuilt page
9363c45 feat(site): fresh clean rebuild, a light page with the real app
a82f349 feat(site): what the page shows, from the app
```
Only the final tree was built and tested; the first commit adds unused data and was not built on its own.

## Security scan
`~/agent-kit/bin/secscan /Users/abhayp/wt/lane3` → `VERDICT: INCOMPLETE`, one `GAP pnpm audit failed: no JSON
from the audit (offline?)` (its audit call fails in this shell). Run by hand with corepack: `pnpm audit` →
4 advisories (3 high, 1 moderate), all build-time tooling inside `next` (browserslist, source-map-js,
baseline-browser-mapping), nothing shipped to the browser. The base commit had 8 (6 high, 2 moderate);
removing Tailwind cleared four. Not fixed: it needs a `next` bump, out of this lane. secscan wrote its report
under the shared git dir (`~/src/tokei-macos/website/.git/secscan/`), not the working files.

## Not checked, gaps, risks
- Final captures from WP-C (`route-ui/site-captures/`) did not exist; the page uses only the four Burn sample
  captures. "Which plan" has the code demo and no app capture; "Pace and value" shows Left on the table and
  the value tier, not the quota bars with the pace tick (the tick is described in a small line).
- CLS was not measured with Lighthouse; layout shift is prevented by sized images and next/font fallbacks.
  DM Mono (terminal only, below the fold) has no metric fallback, so the terminal may reflow slightly on load.
- `app/icon.png` (223 KB, pre-existing) is the largest first-load item; untouched.
- Dependencies: no new runtime or dev dependency; Tailwind and @tailwindcss/postcss removed; `"type": "module"`
  added to package.json so Node loads `lib/*.ts` in the gates without a warning. Gates need Node 22.18+ (type
  stripping); local and Vercel defaults satisfy that, but it is a new requirement, noted in the README.
- Fonts: Switzer (Fontshare FFL), Apfel Grotezk (OFL), DM Mono (OFL, woff2 fetched from Google Fonts' own
  file) self-hosted with licences in `app/fonts/`.
- Not checked in a real browser other than headless Chrome; not checked on Safari.
- Lesson L1034 recorded (`lessons add`): sample popover captures still show real totals below the strip.

## Round 2a (review r1 S1), STATUS: READY

- **Fix.** `components/route-demo.tsx`: each moment button carries `aria-label` with its full label
  ("Monday 9:40"), so its name survives the short label below 560 px (where the long span is
  `display: none` and the short one `aria-hidden`).
- **Check that would have failed.** `scripts/check-copy.mjs` now reads the page's linked stylesheets
  (and inline `<style>`), collects every class some rule hides with `display: none` at any width
  (`hiddenClasses` in `scripts/lib/html.mjs`), and fails any `button`, `a[href]` or `summary` whose name,
  without that text and without aria-hidden text, is empty (`controlNames`). aria-label, aria-labelledby
  and img alt count.
  - New gate on the previous build (`.next` built from 5b5760d), before the fix:
    ```
    check-copy: FAIL, 3 problem(s) in /Users/abhayp/wt/lane3/.next/server/app/index.html
      [control without an accessible name] <button>: <button type="button" aria-pressed="true">
      [control without an accessible name] <button>: <button type="button" aria-pressed="false">
      [control without an accessible name] <button>: <button type="button" aria-pressed="false">
    ```
  - Two new tests (the review's exact markup and CSS, read from a stylesheet and from inline `<style>`;
    icon-only and empty controls fail; text, alt and aria-label pass).
    `~/agent-kit/bin/prove-red node --test scripts/gates.test.mjs` →
    `prove-red: red on old code (1 test file(s) laid over the last commit; command exited 1).`
- **Rebuild, all gates** (`build-r2a.log`): build exit 0;
  `check-no-eyebrows: 13 files, no eyebrow labels`; `check-claims: PASS (3 claims, shipped: none; 4 captures checked)`;
  `check-copy: PASS (122 text nodes, 800 words of copy)`;
  `check-budget: initial JS 137.0 KB of 150.0 KB; first load 566.6 KB of 1000.0 KB ...`; `check-budget: PASS`.
  `test:gates` (`test-gates-r2a.log`): `# tests 40 # pass 40 # fail 0`. `tsc --noEmit` exit 0.
- **Real browser.** Chrome's accessibility tree (CDP `Accessibility.getFullAXTree`) on the served build:
  `AX buttons at 390px: "Monday 9:40", "Wednesday 15:10", "Friday 22:30"`, same at 1440.
  Screenshot `shots/r2a-demo-390.png`.
- **page-check** `--accent '#FF3B70'` (`page-check-r2a/`):
  `PASS @390 no overflow, smallest text 15px, fonts loaded, 3 accent pairings clear` (1440 and 720 PASS too).
- Server on :3517 stopped; `lsof` shows no listener of mine.
- The three large deletions stay uncommitted for Abhay's yes. Not waited on round 2b.
- Commits added: `c8909c5 fix(site): the demo's moment buttons keep their name on a phone`,
  `dce77e9 docs(site): README lists the accessible-name rule`.
