VERDICT: APPROVE

S5 [nit] scripts/check-copy.mjs:37 The new buy-nudge exception recognizes "don't", but the separate paid-spend negation rule does not. Consequently the truthful warning "Don't buy credits." still fails the gate. The current page uses "Never buy", which passes; this does not block this version. Fix: include straight/curly "don't" in NEGATION and add one warning fixture.

Repro: `checkCopy("<h1>Burn all of it.</h1><p>Don't buy credits.</p>").hits` -> `paid spend without a never`; "Do not buy credits." and "Never buy credits." -> no hits. Reproduced with the inline Node probe below, exit 0.

## Round 1 finding status

| ID | Status | Independent verification |
| --- | --- | --- |
| S1 | RESOLVED | app/page.tsx:123 now discloses that Claude Code's logs cannot separate extra usage, so totals may include it. Nudges are separately limited to plan capacity. The disclosure appears in the HTTP response and passes the copy gate. Compared with BurnCopy.eligibilityFinePrint and Bible §7. |
| S2 | RESOLVED | The original `Climb the global <strong>leaderboard</strong>.` fixture now reports `global leaderboard promise`. `Overage <strong>never</strong> scores.` passes. The new tests cover both. The parser reads inline descendants as one block without joining separate block sentences. |
| S3 | RESOLVED | Reran the original missing-film fixture against the executable budget gate: exit 1, naming both gone.webm and gone.mp4. The real video remains excluded from first-load bytes and included in the film budget. |
| S4 | RESOLVED | Production browser run: normal playback -> Reduce Motion on -> off -> scroll away/back. Film stays paused and the control stays absent. The observer is disconnected and its play closure is suppressed. No replay without a pause button. |

No open blocker or should findings. S5 is nonblocking.

## New code reviewed

- Terminal output matches the supplied CLI source: install result from AgentConnection, opportunity text from AgentSnapshot.advice, streak/today/goal formatting and the final warning from BurnFormatting. The 41-minute CLI countdown versus the strip's 42 minutes matches their floor/ceiling rules. The helper path wraps on phones.
- Connect agents labels, status lines, Connect/Disconnect states and the install-command caption match AgentConnectSection. The scene remains an illustration, with a descriptive image label and no fake interactive controls in the tab order.
- Badge order, titles, rules and glyph choices match BurnBadge/BurnCopy. Glyphs are decorative SVGs; lock and status words carry state. Reviewed the independent phone screenshot, including the unlocking badge and final outline. The dropdown comparison image matches the app's wording/order; sample values are allowed to differ.
- Phone checks at 390 px: page width stayed 390 before, during and after the badge halo; no heading, paragraph or terminal overflow. The long helper path wraps. All five normal-motion scenes played. Reduced-motion/no-JavaScript pages showed final content.
- Removed dependencies have no source, CSS, script or build-config imports. The only remaining name matches outside prose are the shadcn schema URL in components.json and helper names in the eyebrow checker; neither imports those packages. Package dependencies are now Next, React and React DOM. Lockfile package-key comparison against ff79ef5: 437 -> 143, 294 removed, zero added. No remaining package version changed in that comparison.

## Commands and results

Reviewed HEAD `9d778e672c87c729b849d90193301777c26c135d`, branch `redesign/2026-11-14`, diff `ff79ef5..HEAD`. Worktree was clean before and after. The same brief's SHA-256 matched `b23da68a5ef97a8bd4e59d5fd7edf3d97c14c69b1ea06201426a4d36c7da8f62` before reading. Read W-fix-r1.md, W-round-2c.md and the Round 2b/2c evidence. No source edits, subagents, commits, pushes or deployment.

| Command | Exit | Result |
| --- | ---: | --- |
| `shasum -a 256 /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/W-review.brief.md` | 0 | Brief matches. |
| `git diff ff79ef5..HEAD`, targeted source reads, `git status --short`, `git rev-parse HEAD` | 0 | Reviewed state above; no uncommitted changes. |
| `corepack pnpm install --frozen-lockfile` | 0 | Lockfile current, resolution skipped. Ran once. |
| `corepack pnpm build` | 0 | Ran once. TypeScript passed; `/` prerendered static. Eyebrow gate: 20 files. Copy: 302 text nodes, 1056 words. JS 137.3/150 KB; first load 749.4/1000 KB; film 2586.7/3000 KB; poster 33.6/150 KB. All gates passed. |
| `corepack pnpm test:gates` | 0 | Ran once. Eyebrow self-test: 17 fixtures; gate tests: 23 passed, 0 failed. |
| `corepack pnpm start --port 3420` | 143 after intentional shutdown | Free port checked before starting. Production page served successfully; stopped with SIGTERM after review. |
| `curl -fsS -o /tmp/tokei-w-review-r2.html -w 'HTTP %{http_code}, bytes %{size_download}\n' http://127.0.0.1:3420/` | 0 | HTTP 200, 168766 bytes. Disclosure, CLI output and warning present. Served HTML also passes checkCopy with no hits. |
| Inline Node copy probes | 0 | S2 regression now rejected; inline negation and CLI "Never buy" warning pass; "Never stop: buy more credits to score." and a second positive buy sentence still fail. S5 reproduced. |
| Inline Node temporary missing-film fixture invoking `node scripts/check-budget.mjs --root <fixture>` | 0 wrapper / 1 gate | Both missing source URLs rejected. Fixture removed; real assets untouched. |
| Installed headless Google Chrome with isolated profile `/tmp/tokei-w-review-r2.bKELrT`, debugging port 3421; inline Node browser protocol checks | 0 | 1440×1000 normal, 390×844 normal, 390 reduced motion, 390 Save-Data and 390 JavaScript disabled. Zero page exceptions or console errors. Normal film plays then pauses offscreen; reduced/Save-Data/no-JS make zero film requests. S4 preference-change sequence passes. |
| Inline Node HEAD requests for built local assets and film sources | 0 | 29 assets, all HTTP 200. |
| `rg` import/name checks across app, components, lib, scripts and configs; source reads of CLI, Settings and BurnCopy/BurnSections | 0 | No removed-package imports; contract comparisons described above. |
| Inline Node lockfile package-key comparison | 0 | 294 package keys removed; zero added. |
| `corepack enable --install-directory /tmp/tokei-w-review-r2-bin` | 0 | Temporary pnpm shim for the scanner. |
| `PATH="/tmp/tokei-w-review-r2-bin:$PATH" SECSCAN_BASE=master /Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-site` | 1 | FLAG; exact lines below. No GAP. |
| `corepack pnpm audit --json > /tmp/tokei-w-review-r2-audit.json` | 1 | Audit completed: critical 0, high 6, moderate 2, low 0. |
| Inline Node comparison with independent Round 1 master/HEAD audit JSON files | 0 | Eight current advisories; zero new module/advisory/version/dependency-path combinations versus master. No proxy-addr advisory remains. Round 1 HEAD had critical 1, high 34, moderate 49, low 9. |
| `git diff --check ff79ef5..HEAD` | 0 | No new whitespace errors. |
| Browser `Browser.close`; `kill -TERM 48447`; `lsof -nP -iTCP -sTCP:LISTEN` | 0 | Review Chrome and server stopped; neither 3421 nor 3420 remains. Other listeners left alone. |

Security scan:

```text
VERDICT: FLAG
AUDIT pnpm: critical 0, high 6, moderate 2, low 0
VULN high/critical while this branch changed pnpm-lock.yaml: browserslist,nanoid,postcss,source-map-js; confirm none came from this change
```

All remaining advisory/version/path combinations occur in the independently captured master baseline. The last critical advisory is gone. This is approval of the reviewed change, not a clean security verdict or a new exploitability audit of inherited packages.

S5 probe:

```sh
node --input-type=module <<'JS'
import {checkCopy} from './scripts/check-copy.mjs';
for (const text of ["Don't buy credits.", "Do not buy credits.", "Never buy credits.", "Never stop: buy more credits to score."]) {
  console.log(text, checkCopy('<h1>Burn all of it.</h1><p>' + text + '</p>').hits.map(h => h.rule));
}
JS
```

Evidence: `/tmp/tokei-w-review-r2-browser.json`, `/tmp/tokei-w-review-r2-390-badges.png`, `/tmp/tokei-w-review-r2-390-agents.png`; screenshots viewed directly. Also viewed the author's `proof/site/round2c/compare-dropdown.png`.

Not checked: deployment/hosted headers, Safari/physical phone, VoiceOver, measured LCP/layout shift, or a new app/CLI build. App matching was reviewed against the named source and capture evidence; the site itself was run. Release version bump remains the orchestrator's release step.

Waits on: nobody for this review. S5 is optional follow-up.
