VERDICT: APPROVE
STATUS: READY

S2 [nit] lib/route.ts:94 Unknown rows use provider order, whereas the merged app uses `unknown.sorted { $0.id < $1.id }` (`RoutePlan.swift:56`, dev `1f452de`). Two stale plans therefore appear in a different order. None of the three demo moments has two unknown rows, so the intended demo and its recommendation are unaffected. Fix: sort unknown rows by id, or narrow the comment claiming exact parity. Repro: the Node comparison below (exit 0) -> website `codex,antigravity`; app's id order `antigravity,codex`. App comparator verified by reading.

No blocker or should finding remains. S1 from round 1 is resolved: all three buttons expose their full names at 390 and 1440, and the new gate rejects the previous markup without an aria-label.

## Target and scope

Reviewed the whole branch `master...HEAD`, base `ab5b0f3`, head `e11dfdf4e8b8b85b7053a472d0ead654835d6a0e`, plus its working tree. Read the site/review briefs, round 1, rounds 2a/2b and the author's results; page, components, CSS, data, gates and lockfile; the relevant 0.12.0 changelog and merged app sources on dev `1f452de`; the speed result's Fix round 1 / S9; capture provenance and each shipped image.

No source edits, commits, pushes, deployments, dependency additions or subagents. The only written deliverable is this report. The three existing asset deletions remain unchanged.

## Spec

- **Captures:** inspected all six WebPs at their actual resolution. Overview has 15.92M demo tokens and four agent tiles; popover has the same demo tokens, $14.62, 11 days and 2.6x; quota shows the 88% Cursor limit, pace ticks and forecast lines; Value shows $361.44 from $140; Burn shows $14.62 against $9.68 and the sample expiring windows; badges show sample progress. No account name, email or home path is visible. `lib/captures.ts` identifies the six files, sizes, sources and safety notes. The source `snapshots.md` identifies the fictional DemoFixture and fixed plan prices. Both social images have identical hashes; their older Burn crop is also sample data and reveals no identity.
- **Release gates:** `route`, `routeCli` and `footprint` all remain `shipped: false`. The served page uses 0.12.0's route wording and `get_route_recommendation`, the real `tokei burn` output, and the changelog's 2.17% idle-CPU fallback. It does not expose the new route command or the 0.478% / 66.9 MB footprint claims. Download remains 0.12.0. The route-capture slot is null and gated by route shipping, as requested for pass 2.
- **Future data:** the stored four-line `tokei route` output exactly matches my run of the author's Release CLI against the fictional snapshot. The six fallback Burn lines exactly match the installed 0.12.0 CLI against that snapshot. Footprint values match the speed result: median CPU 0.478%, original baseline 1.583%, median mean physical footprint 66.898 MB rounded to 66.9 MB. The stored method identifies Release, a writer every second, closed windows, three 120-second runs and one Apple silicon Mac. The source establishes a synthetic workload. No memory-improvement claim was added.
- **Demo:** the three scenarios have the app's intended orders and reason sentences. Checked elapsed-minus-used scoring, zero elapsed for unknown pace, 25% unused threshold, per-window expiry horizons, 85% avoid threshold, avoid-row pace ordering and provider tie break. S2 is confined to ordering multiple unknown rows.

## Standards

- Existing budget, eyebrow and home-HTML discovery gates are byte-for-byte unchanged against master. Copy restrictions remain; the headline expectation follows the requested new headline. Capture/claim and accessible-name checks extend the gates. Existing negative fixtures remain, including banned copy, oversized JS/film/poster, missing assets and Vercel-adapter HTML discovery. All run successfully.
- No new runtime dependency. Tailwind/PostCSS and their lockfile entries were removed together; frozen install passes. Self-hosted fonts replace build-time Google font fetches. Real Chrome font inspection confirmed Apfel Grotezk Mittel on H1, Switzer Variable on body copy and DM Mono on the terminal.
- The retired MP4, WebM and large mark are absent locally but remain tracked in HEAD (1,316,620; 1,270,088; 223,471 bytes). This is the already recorded deletion-approval follow-through, not a new round-2 finding. Include the authorized deletions before shipping a clean checkout; I did not change or bypass that block.

## Proof: commands and real results

| Command | Exit | Result |
|---|---:|---|
| `corepack pnpm install --frozen-lockfile` | 0 | Lockfile passes supply-chain policies; up to date; resolution skipped; pnpm 12.18.0. |
| `corepack pnpm build` | 0 | All gates and Next.js 16.4.3 production build/TypeScript pass; home page prerendered. |
| `corepack pnpm test:gates` | 0 | Eyebrow self-test: 17 fixtures; TAP: 42 tests, 42 pass, 0 fail. |
| `corepack pnpm start --port 3529 --hostname 127.0.0.1` | 143 at intentional shutdown | Ready in 104 ms; used for local proof, then terminated. |
| `~/agent-kit/bin/page-check --accent '#FF3B70' http://127.0.0.1:3529/` | 0 | PASS at 1440, 720 and 390: no overflow; 15 px minimum text; fonts loaded; three accent pairings clear; accent share 1.1%. |
| `curl --fail --silent http://127.0.0.1:3529/` piped to a Node HTML-reader/assertion probe | 0 | Expected H1, no armed reveal/roll in HTML, correct 0.12 fallbacks, no new route or footprint copy. An earlier raw-text regex probe exited 1 because React inserts a comment between the prompt and command; corrected to use the repo's HTML reader. |
| `node scripts/cli-sample.mjs /Users/abhayp/Library/Developer/TokeiWork/dd-site/Build/Products/Release/tokei route` | 0 | All four lines exactly match `routeCli.output`; CLI itself exits 0. |
| `node scripts/cli-sample.mjs /Applications/Tokei.app/Contents/Helpers/tokei burn` | 0 | All six lines exactly match `TERMINAL_BURN`; CLI itself exits 0. |
| Inline Node claims/source/scenario comparison | 0 | All claims off; CPU/baseline/memory match S9; all three demo orders match expected orders; S2 reproduced. |
| Inline Node/Chrome CDP browser probe, attempt 1 | 1 | Keyboard/scenario assertions ran; stopped on an over-broad font assertion that also required unused fallback faces to be loaded. Those fallback faces are correctly unused; this was a probe error. |
| Inline Node/Chrome CDP browser probe, attempt 2 | 1 | All functional, font and visibility assertions below passed. Final empty-console assertion failed on one blank console-error event. No diagnostic text was captured, so a zero-error-console claim is unverified. Stopped after the second probe attempt. |
| `git diff --numstat master...HEAD -- scripts/check-budget.mjs scripts/check-no-eyebrows.mjs scripts/check-no-eyebrows.test.mjs scripts/lib/home-html.mjs` | 0 | Empty: existing gates unchanged. |
| `git ls-tree -l HEAD public/film/hero-burn.mp4 public/film/hero-burn.webm public/tokei-mark.png` | 0 | Confirms the recorded retired assets still tracked. |
| `shasum -a 256 app/opengraph-image.png app/twitter-image.png` | 0 | Same hash for both; older sample Burn image inspected. |
| `kill -TERM 89347` | 0 | Stopped my production server. |
| `lsof -nP -iTCP -sTCP:LISTEN` after shutdown | 0 | No review next-server or headless Chrome listeners; unrelated listeners left alone. |
| `lsof -nP -iTCP:3529 -sTCP:LISTEN` after shutdown | 1 | Empty: my server port is free. |
| `git status --short` | 0 | Same three existing unstaged asset deletions; no source changes from review. |

Build output:
```text
check-no-eyebrows: 13 files, no eyebrow labels
check-claims: PASS (3 claims, shipped: none; 6 captures checked)
check-copy: PASS (123 text nodes, 795 words of copy)
check-budget: initial JS 137.1 KB of 150.0 KB; first load 580.8 KB of 1000.0 KB; film 0.0 KB of 3000.0 KB; poster 0.0 KB of 150.0 KB
check-budget: PASS
```

Browser assertions completed before the final console assertion:
```text
1440 and 390 button names: Monday 9:40, Wednesday 15:10, Friday 22:30
Tab reaches the demo; focus-visible true; outline solid 2px
Space selects Wednesday: cursor:room,codex:room,claude:room,antigravity:avoid
Enter selects Friday: codex:expiring,claude:expiring,cursor:avoid,antigravity:unknown
Live region announces Friday and Codex
Seven rapid switches settle with no retained row transforms
After scrolling: armed reveals/rolls 0; incomplete/broken images 0
Painted custom fonts: Apfel Grotezk Mittel, Switzer Variable, DM Mono
Reduced motion: armed 0, hidden capture/terminal parents 0
JavaScript disabled: armed 0, hidden capture/terminal parents 0
```

Page-check screenshots, independently inspected at 390 and 1440:
`/var/folders/c2/c3gk3d7d11x6zzpz8nwzppsm0000gn/T/page-check-Oy6Clh/`.

S2 reproduction:
```sh
node --input-type=module <<'NODE'
import { rankPlans } from './lib/route.ts';
const p = id => ({ id, agent: id, window: 'weekly', usedPercent: 50,
  elapsed: 0.5, resetsInMinutes: 3000, fresh: false });
console.log('website:', rankPlans([p('codex'), p('antigravity')]).map(p => p.id).join(','));
console.log('app id order:', ['codex', 'antigravity'].sort().join(','));
NODE
```

## Not checked / limits

- The blank console-error event remains unclassified. No functional assertion failed, but I cannot certify absence of runtime/hydration errors from that probe. Its collection logic discarded the information needed to identify the empty event.
- The mixed interaction/scroll probe recorded layout shifts (about 0.023 at desktop and 0.057 at mobile). It also changed demo row content programmatically; it did not retain shift sources or timestamps. These are not a clean cold-load measurement and do not prove a font/image shift. Cold-load zero-CLS is unverified in this round.
- Did not rebuild or rerun the speed benchmark; checked the requested numbers against its recorded three-run output. Did not rebuild the app/CLI; used the existing author-built CLI and inspected dev sources. Did not independently reconstruct captures from the Debug fixture.
- No actual `vercel build --prod`, prebuilt deploy, remote download, Safari or slow-network proof. Security scan, release review and work-log gates belong to the orchestrator under the worker rules.
- Waits on: orchestrator for release follow-through, the recorded asset deletions and any desired clean console/cold-load recheck. S2 is optional and does not block this review approval.
