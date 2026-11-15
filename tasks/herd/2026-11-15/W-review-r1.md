VERDICT: CHANGES

S1 [should] components/route-demo.tsx:50 The three scenario buttons have no accessible name on mobile. Below 560 px, the long labels become `display: none` (app/globals.css:487), while the visible short labels have `aria-hidden="true"` (line 52). A screen reader encounters three unnamed toggle buttons and cannot identify which moment it will select. Fix: add `aria-label={s.label}` to each button and cover the 390 px accessibility tree. Repro: the production-page CDP command below (exit 0) -> `button names @390: ["","",""]`; at 1440 it returns the three expected labels. This breaks the brief's demo screen-reader requirement and AC5.

## Target and scope

Reviewed `master...HEAD` at `5b5760d` on `redesign/2026-11-15`, plus the working-tree state. Read the site brief, author's result, page/components/data/gates, and the relevant shipped app sources and 0.12.0 changelog. No source edits, commits, pushes, deployments, dependencies, or subagents.

## Commands and real results

| Command | Exit | Result |
|---|---:|---|
| `corepack pnpm install --frozen-lockfile` | 0 | Lockfile passes supply-chain policies (96 entries); up to date; resolution skipped. pnpm 12.18.0. |
| `corepack pnpm build` | 0 | All four gates pass; Next.js 16.4.3 production build and TypeScript pass; home page prerendered. |
| `corepack pnpm test:gates` | 0 | Eyebrow self-test: 17 fixtures; TAP: 38 tests, 38 pass, 0 fail. |
| `corepack pnpm start --port 3529 --hostname 127.0.0.1` | 143 at intentional shutdown | Production server ready in 136 ms; used for the following local checks, then stopped with TERM. |
| `~/agent-kit/bin/page-check --accent '#FF3B70' http://127.0.0.1:3529/` | 0 | PASS at 1440, 720 and 390: no overflow, 15 px minimum text, fonts loaded, 3 accent pairings clear. Accent share 1.3%. Screenshots: `/var/folders/c2/c3gk3d7d11x6zzpz8nwzppsm0000gn/T/page-check-qgfgrm/`. |
| `curl --fail --silent http://127.0.0.1:3529/` piped to a Node HTML probe | 0 | H1 present with expected text; zero armed reveal/roll attributes in served HTML; 0.12 route fallback rendered; no `$ tokei route`. |
| `node scripts/cli-sample.mjs /Applications/Tokei.app/Contents/Helpers/tokei burn` | 0 | All six lines match `TERMINAL_BURN`, including fictional $14.62 value, $9.68 goal and 11-day streak. CLI itself reports exit 0. |
| Inline Node/Chrome CDP browser probes | 0 each | Mobile unnamed buttons reproduced; keyboard Space selects Friday; Enter with its character event selects Wednesday and Cursor; visible solid focus ring; no retained row transforms after settling. |
| Inline CDP visibility/scroll probes | 0 each | Reduced motion: 0 armed elements, 0 hidden captures/terminal. JavaScript disabled: H1 and all capture/terminal parents opacity 1, no armed elements. Normal scroll: fact table becomes `played`, digit transforms resolve to 2.17% and 8.1 MB. |
| Inline CDP cold-page probes at 1440 and 390 | 0 | No layout-shift entries in these local, unthrottled runs; no runtime exceptions or failed network requests in the focused second probe. Switzer, Apfel and DM Mono load. |
| `git diff --numstat master...HEAD -- scripts/check-budget.mjs scripts/check-no-eyebrows.mjs scripts/lib` | 0 | Empty: existing budget, eyebrow and HTML-reading gates unchanged. Existing copy tests retained; headline expectation changed for the requested headline; capture/claims checks added. |
| `git diff --check master...HEAD` (via Node to summarize output) | 2 | 94 trailing-whitespace reports, confined to the two imported font licence texts. No runtime impact; not a required fix. |
| `git ls-tree -l HEAD public/film/hero-burn.mp4 public/film/hero-burn.webm public/tokei-mark.png` | 0 | The three retired assets remain tracked in HEAD (1,316,620; 1,270,088; 223,471 bytes); their deletions remain only in the worktree, as the author disclosed. |
| `kill -TERM 68547` | 0 | Stopped my next-server. |
| `lsof -nP -iTCP -sTCP:LISTEN` after shutdown | 0 | No production server on 3529 or review Chrome listeners; unrelated existing listeners left alone. |
| `lsof -nP -iTCP:3529 -sTCP:LISTEN` after shutdown | 1 | Empty output: port free. |
| `git status --short` after review | 0 | Same three pre-existing unstaged asset deletions; no changes from this review. |

Build output:
```text
check-no-eyebrows: 13 files, no eyebrow labels
check-claims: PASS (3 claims, shipped: none; 4 captures checked)
check-copy: PASS (122 text nodes, 800 words of copy)
check-budget: initial JS 137.0 KB of 150.0 KB; first load 566.6 KB of 1000.0 KB; film 0.0 KB of 3000.0 KB; poster 0.0 KB of 150.0 KB
check-budget: PASS
```

## Accessibility reproduction command

Start the production server with the command above, then run this from the worktree. The script closes its own headless Chrome and removes its own temporary profile.

```sh
node --input-type=module <<'NODE'
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const profile = mkdtempSync(join(tmpdir(), 'tokei-review-ax-'));
const port = 9743;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless=new', '--no-first-run', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });
const wait = ms => new Promise(r => setTimeout(r, ms));
let ws;
try {
  let target;
  for (let n = 0; n < 50 && !target; n++) {
    await wait(100);
    try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
  }
  if (!target) throw Error('Chrome did not start');
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let id = 0; const pending = new Map();
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id) { const [resolve, reject] = pending.get(m.id); pending.delete(m.id); m.error ? reject(Error(m.error.message)) : resolve(m.result); }
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    pending.set(++id, [resolve, reject]); ws.send(JSON.stringify({ id, method, params }));
  });
  await send('Page.enable'); await send('Page.bringToFront');
  for (const width of [1440, 390]) {
    await send('Emulation.setDeviceMetricsOverride', { width, height: 844, deviceScaleFactor: 1, mobile: width === 390 });
    await send('Page.navigate', { url: 'http://127.0.0.1:3529/' }); await wait(800);
    const { nodes } = await send('Accessibility.getFullAXTree');
    console.log(`button names @${width}: ${JSON.stringify(nodes.filter(n => n.role?.value === 'button').map(n => n.name?.value))}`);
  }
} finally {
  if (ws) ws.close();
  const exited = new Promise(resolve => chrome.once('exit', resolve)); chrome.kill();
  await Promise.race([exited, wait(3000)]); rmSync(profile, { recursive: true, force: true });
}
NODE
```

Observed output, exit 0:
```text
button names @1440: ["Monday 9:40","Wednesday 15:10","Friday 22:30"]
button names @390: ["","",""]
```

## Other checks and release follow-through

- Inspected all four shipped app captures by eye. They show the documented sample figures and contain no account name, email or home path. Cross-checked the sample source, cropped strip, 0.12.0 feature claims, route thresholds, CLI output and idle-CPU source. No further claim/privacy defect found.
- No gate weakening found against master. The passing tests include rejected banned-copy, eyebrow and over-budget fixtures, missing-asset failures, and the Vercel-adapter HTML-layout fixture.
- The committed tree still contains the three retired assets above; the author's result already records the deletion approval block. Resolve that existing block and include the deletions before shipping from a clean checkout. I did not change or bypass it.
- Not checked: actual `vercel build --prod` or prebuilt deployment, a remote deployment/download, Safari, slow-network CLS, and future 0.13.0 route output/footprint claims. Those claims are currently off. Security scan and release gates remain with the orchestrator under the worker rules.
- Waits on: website author, for S1; orchestrator, for the recorded release follow-through.

