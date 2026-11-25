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

## Round 2b (final captures and 0.13.0 data), STATUS: READY

Commit `e11dfdf feat(site): the final demo-data captures, 0.13.0 route data, the app's route rule`.
Proof: `~/Library/Developer/TokeiWork/proof/site-1115/` (`shots-r2b/`, `page-check-r2b/`, `crops-r2b/`,
`build-r2b.log`, `test-gates-r2b.log`, `cli/tokei-route-0.13.txt` and `.json`).

1. **Captures** (route-ui site captures pass 1, `*-content.png`, demo fixture; the page draws a plain window
   bar with unlit buttons since the title bar is cropped). Hero: `overview.webp` (Overview Usage, 2200x1456)
   with `popover.webp` (640x1102) in front, lower right; on a phone the popover sits over the window's right
   edge. "Use it before it resets": `quota.webp` (Overview Quota, rows 0 to 1100: 88% tightest, four bars with
   the pace tick and ahead/behind lines) above `value.webp` (Value, rows 0 to 1100), stacked, no overlap.
   Burn section: `burn.webp` (Burn tab rows 110 to 910: ring, $14.62, streak, use it or lose it) plus the
   existing sample `badges.webp`. Removed: the old Burn hero and the popover strip crop. Every entry in
   `lib/captures.ts` has source and safety note; the gate checked 6 captures and their sizes.
   `ROUTE_CAPTURE` (null now) takes pass 2: set it and the "which plan" section shows it under the demo
   once `route` ships; the gates check it too.
2. **`tokei route`.** Built the `tokei` scheme (Release) from `git archive dev` at 1f452de (contains
   dbdc98e) into `~/Library/Developer/TokeiWork/site-cli-src` and DerivedData `dd-site` (main checkout
   untouched). `scripts/cli-sample.mjs` now writes a `route` block shaped as `AgentRoute` with the rows,
   order and reason sentences `RoutePlan.make` produces for those plans. `node scripts/cli-sample.mjs <tokei> route`, exit 0:
   ```
   Send the next task to Codex. Use this plan before unused capacity resets in 42m.
   Codex: 62% left · fiveHour · resets in 41m · behind · ready
   Claude Code: 39% left · weekly · resets in 18h · behind · ready
   Cursor: 66% left · monthly · resets in 287h · behind · ready
   ```
   `--json` parses. In `routeCli.output`, `shipped: false`. The dev build's `tokei burn` prints the same six
   lines as 0.12.0, so the fallback terminal is unchanged. Note: this dev build still reports `tokei 0.12.0`
   (MARKETING_VERSION not bumped yet).
3. **Footprint**, quoted from `A-speed.result.md` Fix round 1, S9: "Median CPU: 0.478%. Median mean physical
   footprint: 66.898 MB." and "the original measured baseline of 1.583%". In `footprint`: busyCpu "0.478%",
   busyCpuBefore "1.583%", memory "66.9 MB", method "Release build, one agent writing every second, no window
   open, median of three 120 s runs on one Apple silicon Mac"; `shipped: false`. When shipped the table shows
   "CPU while an agent works 0.478%" with the method and "The previous release on the same rig: 1.583%", and
   "Memory 66.9 MB, mean footprint over the same runs" (a figure, no improvement claim). The gate now also
   requires busyCpuBefore when shipped.
4. **Demo rule vs merged `RoutePlan.swift`** (dev 1f452de). Already equal: avoid at 85% used goes last;
   expiring leads only with 25% or more left in the tightest window and within the type's horizon, soonest
   first; stale is unknown. Changed to agree:
   - room for pace treats an unknown pace as zero elapsed (`elapsed` may be null);
   - plans to avoid sort by room for pace, then left (was: left only);
   - the last tie break is the app's provider order (`ProviderID.allCases`), not the name;
   - unknown rows sort by provider order;
   - reasons are RoutePlan's sentences ("Use this plan before unused capacity resets in 42m.", "This plan
     has room to spare relative to its pace.", "This plan has N% left in its tightest window.", "Avoid this
     plan because only N% remains in its tightest window.", "A fresh, confirmed plan reading is
     unavailable."), with `compactDuration` ported; pace "behind" uses `QuotaPace.band` (5 points).
   The three demo moments keep their order. New tests for each difference; the tie and avoid-order tests
   fail against the previous `lib/route.ts` (`not ok 1 - tie by provider order`, `not ok 2 - avoid by room`),
   and `prove-red node --test scripts/gates.test.mjs` → `red on old code`.
5. **Tool names.** `ROUTE_COPY` in `lib/claims.ts` (scanned by the gate): fallback "Agents ask which plan to
   use over MCP with get_route_recommendation."; shipped "Agents get the same ranked list over MCP with
   get_route, or from the tokei route command." The "which plan" lead also switches there.

**Checks.** Build exit 0: `check-no-eyebrows: 13 files, no eyebrow labels`; `check-claims: PASS (3 claims,
shipped: none; 6 captures checked)`; `check-copy: PASS (123 text nodes, 795 words of copy)`;
`check-budget: initial JS 137.1 KB of 150.0 KB; first load 580.8 KB of 1000.0 KB`; `check-budget: PASS`.
`test:gates`: `# tests 42 # pass 42 # fail 0`. `tsc --noEmit` exit 0.
page-check `--accent '#FF3B70'`: `PASS @1440 ... 3 accent pairings clear`, `PASS @720`, `PASS @390 no overflow,
smallest text 15px, fonts loaded, 3 accent pairings clear`; accent share 1.1%.
Chrome AX tree at 390: `"Monday 9:40", "Wednesday 15:10", "Friday 22:30"`. Demo Friday order:
`codex:expiring claude:expiring cursor:avoid antigravity:unknown`.
Screens: `shots-r2b/full-1440.png`, `full-390.png`, `reduced-full-390.png`, `demo-friday-1440.png`,
`z-pace.png`, `z-hero-390.png`. Server on :3517 stopped.

**Not checked / notes.** The social preview image still shows the earlier Burn hero (taken in round 1);
retake it from the new hero at release if wanted. Captures show the app's own em dash ("Cursor, Auto monthly
window — the tightest live quota.") inside the image; page text has none. The three large deletions stay
uncommitted for Abhay's yes.

## Round 2c (pass-2 route captures, review r2 S2), STATUS: READY

Commit `f73a588 feat(site): route-row captures wait behind the route claim`.
Proof: `~/Library/Developer/TokeiWork/proof/site-1115/shots-r2c/`, `page-check-r2c-off/`, `page-check-r2c-on/`,
`build-r2c-off.log`, `build-r2c-on.log`, `test-gates-r2c.log`, `crops-r2c/`.

1. **Route captures behind the claim.** Pass 2 overwrote `popover-dark` and `overview-usage-dark` with
   versions that show the route row, so the repo's existing `popover.webp` and `overview.webp` (encoded from
   pass 1, no route row) stay as the 0.12.0-true set in `CAPTURES`. New `ROUTE_CAPTURES` in `lib/captures.ts`:
   `overview` (overview-usage-tall, 2200x1816), `popover` (pass 2 popover, 640x1336) and `route` (crop
   600x310 at 20,408 of popover-route: "Send work here next", Codex 5-hour with its reason, then Claude Code
   and Gemini). The page picks the hero set from `CLAIMS.route.shipped` and shows `route` under the demo only
   when shipped, so the release flip of `lib/claims.ts` alone swaps both.
   Gates: `check-copy` fails "route capture shown before the route claim ships" for any `ROUTE_CAPTURES`
   image while the claim is off (test both ways); `check-claims` checks both sets:
   `check-claims: PASS (3 claims, shipped: none; 6 + 3 route captures checked)`.
2. **S2.** Unknown plans sort by id (`unknown.sorted { $0.id < $1.id }`). New test; against the previous
   `lib/route.ts` it fails (`not ok 1 - unknown by id`).
3. **Both states.**
   - Claims off (committed): build exit 0; `check-copy: PASS (123 text nodes, 795 words of copy)`;
     `check-budget: initial JS 137.1 KB of 150.0 KB; first load 580.8 KB of 1000.0 KB`; images on the page:
     `overview.webp popover.webp quota.webp value.webp burn.webp badges.webp`; page-check PASS at 1440, 720, 390.
     Screens `shots-r2c/claims-off-full-1440.png`, `claims-off-full-390.png`.
   - Claims on (route, routeCli, footprint flipped in `lib/claims.ts` locally, built, then restored with
     `git checkout -- lib/claims.ts`; not committed): build exit 0;
     `check-claims: PASS (3 claims, shipped: route, routeCli, footprint; 6 + 3 route captures checked)`;
     `check-copy: PASS (130 text nodes, 839 words of copy)`; `check-budget: initial JS 137.1 KB ...; first load
     603.0 KB of 1000.0 KB`; images: `overview-route.webp popover-route.webp route-rows.webp quota.webp
     value.webp burn.webp badges.webp`; page-check PASS at 1440, 720, 390. The terminal shows `tokei route`,
     the fact table shows 0.478% (with 1.583% before) and 66.9 MB. Screens `shots-r2c/claims-on-full-1440.png`,
     `claims-on-full-390.png`.
   - `test:gates`: `# tests 44 # pass 44 # fail 0`; `tsc --noEmit` exit 0; prove-red: red on old code.
4. Server on :3517 stopped (lsof count 0). The three large deletions stay uncommitted for Abhay's yes.

## Round 2d (release flip)

STATUS: READY. Commit `58f6c74` on `redesign/2026-11-15` (worktree `~/wt/lane3`). No deploy, no push.

1. `routeCli.output`: `node scripts/cli-sample.mjs <dist/Tokei.app/Contents/Helpers/tokei> route` (signed, team
   A47GG9FV27, `tokei 0.13.0`), exit 0, four lines copied verbatim ("… resets in 42 min.", "5-hour window",
   "under pace"). The demo's reasons now use the CLI's own countdown (`RouteFormatting.countdown`, main 878f043:
   minutes rounded up, "42 min" / "19 h" / "12 d"); the RoutePlan sentences are unchanged since 1f452de. Note: the
   app's own route row still says "40m" (RoutePlan `compactDuration`), so the popover crop and the demo use
   different duration styles; the demo follows the CLI as the brief asked. Unused `countdown` (BurnCopy) and
   `compactDuration` ports deleted. Tests updated and red on the old code (prove-red: "red on old code").
2. All three claims shipped. Hero and route section use the pass-2 captures; footprint 0.478% / 1.583% before /
   66.9 MB (median of three); the one-run 0.481% / 65.1 MB noted in the claims file.
3. `lib/site.ts`: version 0.13.0, `…/releases/download/v0.13.0/Tokei-0.13.0-arm64.dmg`, `downloadMB: "10.5"` from
   the real DMG: waited until `stapler validate` passed and the size held (unsigned 10,511,756 → signed 10,521,270
   → stapled 10,523,275 bytes); `spctl` "accepted, source=Notarized Developer ID".
4. Copy: the agents line is one sentence ("Agents call get_route over MCP, and tokei route prints the same ranked
   list in a terminal."), then "Either way, Tokei points agents at capacity your plans already include …". Also:
   "which plan to spend" → "to use"; "Tokei notices" → "Tokei shows a new record" (BurnCopy "New record: best day");
   "same rig" → "same Mac and workload"; memory note "Physical footprint, median of the same runs" (it is a
   median, not a mean); route caption no longer says "the same answer" (the crop shows different demo plans).
   Fallback agents line also made true and single ("… and tokei burn lists the windows to use first.").
   Layout fix found in the screenshots: at 390 px a fact value that wrapped under its label sat left/centred; it
   now stays on the right edge (`margin-left: auto`).
5. Build exit 0: check-claims PASS (shipped: route, routeCli, footprint; 6 + 3 captures), check-copy PASS (128
   nodes, 848 words), initial JS 137.1 of 150 KB, first load 603.0 KB; tsc clean; `test:gates` 44/44. page-check
   PASS at 1440, 720 and 390 (15 px min, fonts loaded, 3 accent pairings clear). Screens:
   `~/Library/Developer/TokeiWork/proof/site-1115/shots-r2d/` (full-1440, full-390, agents-1440, facts-1440,
   facts-390, route-390, page-check.txt) and `page-check-r2d/`. Server on :3517 stopped (lsof 0).
   secscan: INCOMPLETE, one GAP (its `pnpm audit` call returned no JSON, as in earlier rounds); no FLAG.

Not checked: the download URL resolves only once the v0.13.0 GitHub release has the DMG; the OG/twitter images
still show the round-1 hero; Safari. Still uncommitted: the three large deletions, waiting on Abhay's yes.

## Round 2e (link previews)

STATUS: READY. Commit `227e845` on `redesign/2026-11-15`. No deploy, no push.

1. Cause: `app/layout.tsx` built the origin from `NEXT_PUBLIC_SITE_URL` / `VERCEL_URL`, falling back to
   `http://localhost:3000`; the deployed build had neither, so og:url, og:image and twitter:image were on
   localhost. Fix: `site.origin = "https://tokei-website.vercel.app"` in `lib/site.ts` is the one canonical
   origin; the layout uses `metadataBase: new URL(site.origin)` and `openGraph.url: "/"` (Next 16
   `generate-metadata.md`, metadataBase and URL composition). No env var involved any more.
   Built head now: `og:url` https://tokei-website.vercel.app, `og:image` / `twitter:image`
   https://tokei-website.vercel.app/opengraph-image.png?… (and twitter-image.png), 1200x630, with `og:image:alt`.
2. Gate: `scripts/check-meta.mjs`, in `pnpm build` after check-copy. Fails on localhost / 127.0.0.1 / 0.0.0.0 /
   [::1] in any `meta` or `link` tag, and unless og:image (required), twitter:image and og:url are absolute https
   on `site.origin`. Red on the previous build's real HTML: "check-meta: FAIL, 9 problem(s)" (the three localhost
   tags, not https, not on the origin). Four tests in `gates.test.mjs` (origin in one place; the layout reads
   it and has no localhost/VERCEL_URL fallback; the served head is rejected; https/origin/relative/missing/
   127.0.0.1 cases), plus check-meta added to the "no prerendered page" test. prove-red with the gate laid
   over the old commit: "red on old code" (the two code tests fail there).
3. `app/opengraph-image.png` and `app/twitter-image.png` replaced (92 KB, was 246 KB): the headline in Apfel
   Grotezk, a short line in Switzer, the page's ground and window frame, and the pass-2 Overview capture
   (`overview-route.webp`, DemoFixture data, with the "Send work here next" row). Rendered in headless Chrome,
   fonts confirmed loaded. Alt text in `opengraph-image.alt.txt` / `twitter-image.alt.txt`. Proof:
   `~/Library/Developer/TokeiWork/proof/site-1115/shots-r2e/` (card PNG and its HTML source). `next start`
   served the image at the og:image path (200, image/png, byte-identical to the file).
4. Build exit 0 (check-claims, check-copy, check-meta "PASS (previews on https://tokei-website.vercel.app)",
   check-budget: initial JS 137.1 KB, first load 603.1 KB); `test:gates` 48/48; tsc clean; secscan INCOMPLETE
   with the same single GAP (its `pnpm audit` returned no JSON), no FLAG. Server stopped (lsof 0).
   Note: the first two builds this round hit a Turbopack panic ("ModuleGraph::from_graphs_inner was canceled",
   in NFT tracing) from a stale `.next` cache; with `.next` moved aside the build passed every time after. A
   Vercel build cache could in principle hit the same; a clean redeploy clears it.

Not checked: a real Slack / X / iMessage unfurl (needs the deploy); the live page until it is redeployed.
Still uncommitted: the three large deletions, waiting on Abhay's yes.
