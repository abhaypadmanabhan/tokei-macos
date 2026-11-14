VERDICT: CHANGES

S1 [should] app/page.tsx:123 The page promises that overage never scores, contrary to the binding eligibility decision. Patch Bible §7 explicitly says Claude extra-usage tokens cannot be separated from Claude Code's daily totals and requires that limitation in UI copy. A user paying for Claude extra usage would receive a false assurance here. Fix: state that scoring uses plan products, disclose the Claude extra-usage limitation, and retain the promise that nudges never encourage paid overage.

Reading: `/Users/abhayp/src/tokei-macos/tasks/patch-bibles/2026-11-14.md`, §7, versus the new sentence `Overage, credits and API keys never score.` This is a website contract mismatch, independent of the deferred app/CLI string reconciliation.

S2 [should] scripts/check-copy.mjs:55 The new copy gate scans individual text nodes, so ordinary inline emphasis bypasses a required banned-copy check. `<p>Climb the global <strong>leaderboard</strong>.</p>` passes, although the rendered sentence promises a global leaderboard. Fix: scan normalized text across inline descendants within each text block, preserving sentence boundaries; add this fixture to the existing gate tests.

Repro: command A below -> `check-copy: PASS (4 text nodes, 8 words of copy)`, exit 0. The gate must reject this input. The same problem affects other multiword banned patterns split across tags.

S3 [nit] scripts/check-budget.mjs:51 The asset check ignores video/source URLs. A page referencing two nonexistent film files passes with a zero-byte film total. Current checked-in film URLs both serve successfully, so this is a guard limitation rather than a currently broken hero. Fix: validate local video/source references for existence, separately from their exclusion from the first-load byte total.

Repro: command B below -> `film 0.0 KB of 3000.0 KB`, `check-budget: PASS`, exit 0, despite both referenced film files being absent.

S4 [nit] components/hero-film.tsx:45 Changing Reduce Motion on and then off during a visit restarts the film without restoring its pause control. The handler removes the button with `setAllowed(false)`; when CSS displays the video again, the intersection observer calls `play()` without restoring that state. Fix: update playback permission and control visibility together on preference changes, or keep the film suppressed for the rest of that visit as the comment promises.

Repro: production page in Chrome; `Emulation.setEmulatedMedia` reduce, then no-preference -> `{paused:true, display:"none", button:undefined}` then `{paused:false, display:"block", button:undefined}`. Initial playback and manual pause were tested first and worked. Classified nit because this requires changing the preference mid-visit.

## Reviewed state

- Brief SHA-256 verified before reading: `b23da68a5ef97a8bd4e59d5fd7edf3d97c14c69b1ea06201426a4d36c7da8f62`.
- Worktree `/Users/abhayp/src/tokei-worktrees/2026-11-14-site`, branch `redesign/2026-11-14`, HEAD `ff79ef5476afdde207b396840a21baec20600389`.
- Merge-base with master: `3c5feda8a1a5fb9eaea6f06adbdf94de5520c7c2`. `git status --short` empty before and after. Read the branch diff, surrounding source, binding WP-W acceptance criteria, §7, and both portions of W-site.result.md.
- No source edits, commits, pushes, deployments, or subagents. Only this report and temporary review fixtures/screenshots were written. The scanner also writes its normal git metadata report.

## Commands and results

Commands ran from the site worktree unless a temporary baseline directory is named.

| Command | Exit | Result |
| --- | ---: | --- |
| `shasum -a 256 /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/W-review.brief.md` | 0 | Matches the supplied checksum. |
| `git branch --show-current`; `git status --short`; `git merge-base HEAD master`; `git rev-parse HEAD`; `git diff master...HEAD` and targeted diff/source reads | 0 | State above; lockfile importer changes only Next from 16.2.10 to 16.4.3. Next-owned transitive changes inspected. |
| `corepack pnpm install --frozen-lockfile` | 0 | Lockfile up to date; resolution skipped. |
| `corepack pnpm build` | 0 | Next 16.4.3; TypeScript passed; `/` prerendered static; every build gate passed. Copy: 264 text nodes, 815 words. JS 137.3/150 KB; first load 744.8/1000 KB; film 2586.7/3000 KB; poster 33.6/150 KB. |
| `corepack pnpm test:gates` | 0 | Eyebrow self-test: 17 fixtures; node tests: 18 passed, 0 failed. |
| `corepack pnpm start --port 3418` | 143 after intentional stop | Served the production build; terminated my server with SIGTERM after review. |
| `curl -fsS -o /tmp/tokei-w-review-r1.html -w 'HTTP %{http_code}, bytes %{size_download}\n' http://127.0.0.1:3418/` | 0 | HTTP 200; 140488 bytes; headline and final scene content present in served HTML. |
| Headless installed Google Chrome, isolated `/tmp/tokei-w-review-r1.jWzmKV` profile, debugging port 3419 | 0 | Closed through `Browser.close`. |
| `node --input-type=module` inline Chrome DevTools Protocol checks | 0 | 1440×1000 normal; 390×844 normal; 1440 reduced motion; 390 Save-Data; 390 JavaScript disabled. No page exceptions or console errors. All five scenes reached played state under normal motion; reduced/no-JS scenes stayed on final frames. No horizontal overflow or overflowing paragraph/terminal text in the checked layouts. |
| Second inline Chrome protocol run: pause, offscreen/onscreen, preference changes, keyboard and accessibility tree | 0 | Manual pause survives leaving/returning to hero. Offscreen playback pauses. Preference change exposes S4. Ten checked keyboard stops had visible solid 2px focus outlines. Five faux UI images have descriptive accessible names; a real screen-reader reading pass was not performed. |
| Inline Node HEAD requests for measured local assets plus film sources | 0 | 29 assets checked, all HTTP 200; MP4 and WebM return correct video MIME types. |
| Inline copy probes, including command A | 0 | S2 reproduced; normal banned fixtures remain covered by passing gate tests. A variable containing all-caps text also escapes the pre-existing eyebrow source checker; no separate change-blocking finding for that inherited weakness. |
| Inline budget probes, including command B | 0 | S3 reproduced without changing the real build or public files. |
| `git diff --check master...HEAD` | 2 | One trailing blank line at app/globals.css:210; formatting only, not a finding. |
| `SECSCAN_BASE=master /Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-site` | 2 | Initial result INCOMPLETE; audit command not found on scanner's PATH. Exact GAP below. |
| `corepack pnpm audit --json > /tmp/tokei-w-review-r1-audit.json` | 1 | Audit completed: critical 1, high 34, moderate 49, low 9. |
| `corepack pnpm --dir /tmp/tokei-w-review-baseline.ZIUG2h audit --json > /tmp/tokei-w-review-r1-baseline-audit.json` | 1 | Temporary fixture contains master package.json and lockfile from `git show`; no install. Baseline: critical 6, high 44, moderate 58, low 10. |
| Inline Node comparison of both audit JSON files | 0 | Zero new module/advisory/version/dependency-path combinations. |
| `corepack enable --install-directory /tmp/tokei-w-review-r1.jWzmKV/pnpm-bin` | 0 | Temporary package-manager shim lets the same scanner finish its audit. |
| `PATH="/tmp/tokei-w-review-r1.jWzmKV/pnpm-bin:$PATH" SECSCAN_BASE=master /Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-site` | 1 | Final result FLAG; exact flagged dependency line below. Baseline comparison confirms none was introduced by this change. |
| `kill -TERM 5425`; browser `Browser.close`; `lsof -nP -iTCP -sTCP:LISTEN` | 0 | Neither review server 3418 nor review Chrome 3419 remains. Other existing listeners left alone. |

Security scan output requiring disclosure:

```text
Initial VERDICT: INCOMPLETE
GAP pnpm audit failed: no JSON from the audit (offline?)

Final VERDICT: FLAG
AUDIT pnpm: critical 1, high 34, moderate 49, low 9
VULN high/critical while this branch changed pnpm-lock.yaml: @modelcontextprotocol/sdk,body-parser,brace-expansion,browserslist,fast-uri,ip-address,js-yaml,nanoid,postcss,proxy-addr,source-map-js,systeminformation; confirm none came from this change
```

The audit ran successfully after adding the temporary shim. The remaining advisories are inherited according to the independent baseline comparison; this is not a clean security verdict or a fresh audit of those packages' exploitability.

### Command A: rendered copy bypass

```sh
node --input-type=module <<'JS'
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const dir = mkdtempSync(join(tmpdir(), 'tokei-w-copy-'));
try {
  const path = join(dir, 'split-leaderboard.html');
  writeFileSync(path, '<h1>Burn all of it.</h1><p>Climb the global <strong>leaderboard</strong>.</p>');
  const p = spawnSync(process.execPath, ['scripts/check-copy.mjs', '--html', path], {encoding:'utf8'});
  console.log('gate exit=' + p.status);
  console.log(p.stdout + p.stderr);
} finally { rmSync(dir, {recursive:true}); }
JS
```

### Command B: missing film sources

```sh
node --input-type=module <<'JS'
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
const root = mkdtempSync(join(tmpdir(), 'tokei-w-budget-missing-'));
try {
  mkdirSync(join(root, '.next/server/app'), {recursive:true});
  mkdirSync(join(root, 'public/film'), {recursive:true});
  writeFileSync(join(root, 'public/film/poster.webp'), 'x');
  writeFileSync(join(root, '.next/server/app/index.html'), '<video poster="/film/poster.webp"><source src="/film/gone.webm" type="video/webm"><source src="/film/gone.mp4" type="video/mp4"></video>');
  const p = spawnSync(process.execPath, ['scripts/check-budget.mjs', '--root', root], {encoding:'utf8'});
  console.log('missing-film-source exit=' + p.status + '\n' + p.stdout + p.stderr);
} finally { rmSync(root, {recursive:true}); }
JS
```

Screenshots independently viewed: `/tmp/tokei-w-review-r1-390-top.png`, `/tmp/tokei-w-review-r1-390-agents.png`, `/tmp/tokei-w-review-r1-1440-burn.png`.

Not verified: actual Vercel deployment or hosted headers; Safari/real iPhone; VoiceOver; measured LCP/layout-shift trace; generated-film provenance or every design artboard. No claim that prerendering is `output: "export"` (it is not configured, and Vercel can serve the prerendered Next route). Deferred app/CLI reconciliation and the release version bump remain outside this round.

Waits on: website author for S1 and S2. S3 and S4 are nonblocking nits.
