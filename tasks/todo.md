# AI Usage Dashboard (native macOS) — Plan

## Phase 0 — Research (in progress)
- [x] Local scout: verify provider data on this machine
- [x] Deep-research workflow — stopped early to save tokens; 31/~40 agent results salvaged
      → raw: research/raw-findings.md, distilled: research/provider-research.md
      (verify phase cut short — treat unverified claims section with caution)

## Local scout findings (2026-07-05)
- **Codex** `~/.codex/sessions/**/*.jsonl` — 38 files. `token_count` events carry:
  - `rate_limits.primary`: `used_percent`, `window_minutes: 300` (5h session), `resets_at` (epoch) — plus likely `secondary` = weekly window
  - `total_token_usage`: input / cached_input / output / reasoning_output / total
  - `auth.json`: OAuth tokens (access_token, account_id) — enables account usage endpoints if needed
  - → Session %, reset countdown, full token splits: ALL LOCAL, no network
- **Claude Code** `~/.claude/projects/**/*.jsonl` — 639 files, 30 projects. Per-message `usage`:
  input / cache_creation / cache_read / output tokens → ccusage-style aggregation (daily/weekly/lifetime)
  - Session/weekly LIMITS not in transcripts — need OAuth usage endpoint (research pending)
- **Cursor** — `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (SQLite) present; dashboard API needs session auth (research pending)
- **Antigravity** — installed (`~/Library/Application Support/Antigravity`, `~/.antigravity`); data source TBD
- **Cline** — CLI installed at `~/.cline` (601MB data). Per-message `metrics` in
  `~/.cline/data/sessions/<id>/<id>.messages.json`: inputTokens / outputTokens /
  cacheReadTokens / cacheWriteTokens / **cost** ($) + `modelInfo` (provider/model, e.g. cline-pass/glm-5.2).
  `sessions.db` SQLite: session_id, provider, model, started/ended_at, status.
  `providers.json`: cline + cline-pass configured. → Tokens + real cost: ALL LOCAL.
  Credits balance/subscription: needs app.cline.bot API (research pending)

## Phase 1 — Architecture + design (after research)
- [ ] Provider capability matrix → final report
- [ ] Architecture doc (provider plugin protocol, Keychain, SwiftData, WidgetKit, refresh)
- [ ] /padzy-os design pass for UI
- [ ] Implementation plan split into agent-delegable work packages

## Phase 2 — Build (delegated grunt work: Codex, Kimi, Cursor, GLM, Antigravity agents)
- [x] Xcode project scaffold (Kimi; xcodegen, builds clean, 8 tests pass)
- [ ] Core: provider protocol, local parsers (Codex, Claude first)
- [ ] Menu bar + dashboard UI
- [ ] Widgets, notifications, settings

## Phase 3 — Fable audit + MVP orchestration (2026-07-06)
Audit verdict: builds clean, 8/8 tests pass, architecture sound — BUT parser targets
a fictional JSONL schema. Verified on real logs: dedupe dead (2.34x overcount:
2.63B naive vs 1.12B correct) + fractional-second timestamps unparsed (today/week/month
always 0). Tests pass because fixtures use the same fictional schema.

Decisions:
- Persistence = JSON file store, NOT SwiftData (strict concurrency `complete` in Core).
- Widget target DEFERRED post-MVP (app-group/signing risk).
- Codex agent NOT used; Fable does integration.
- .xcodeproj gitignored — regenerate via `xcodegen generate`.
- Padzy theme "aitracker" proposed (cool dark + signal pink #FF3B70) — pending Abhay confirm;
  see AIUsageDashboard/docs/07-padzy-theme.md.

Work packages (prompts in tasks/agent-prompts/):
- [x] A Kimi — persistence (JSON store + daily rollups) + FSEvents watcher + auto-sync — branch agent/kimi-storage-watcher
- [x] B Cursor — parser rewrite vs real schema + dedupe + tests — branch agent/cursor-parser
- [x] C Antigravity — Padzy UI: dashboard, menu bar live count, shared VM — branch agent/antigravity-ui
- [x] D Fable — review diffs, merge, integrate updates stream into VM, build/tests, final report

## Definition of done (MVP) — ALL MET 2026-07-06
- [x] Claude tokens correct vs independent dedupe baseline (<0.1% divergence; delta = live log growth between runs)
- [x] Dashboard: today/7D/30D/lifetime + confidence labels; other providers marked unavailable (screenshot-verified)
- [x] Menu bar: live today total (⌾ 20.9M observed) + sync status
- [x] Auto-refresh on ~/.claude/projects changes (observed: SYNCED advanced + TODAY grew with no manual refresh)
- [x] History persisted to Application Support (usage-store.json written on first run)
- [x] Build + all 27 tests green

Integration fixes by Fable post-merge:
- .DS_Store in ~/.claude/projects crashed log discovery (caught by new real-logs smoke test) → skip non-directories
- Daily rollup stored lifetime-cumulative → changed to per-day todayUsage (lifetime shrinks on log rotation)
- Wired SyncEngine.updates AsyncStream + startAutoSync into DashboardViewModel (beginAutoSync, idempotent)
- Deleted unreferenced .jsonl fixtures; added RealLogsSmokeTests

Known limitations (accepted for MVP):
- SyncEngine stopAutoSync→startAutoSync cycle dead (AsyncStream terminates on cancel); app starts auto-sync once at launch
- updates stream single-consumer (the shared view model)
- Padzy theme "aitracker" still pending Abhay confirmation

## Leg 3 — Antigravity UI (current session)
- [x] Add selectedProvider & selection logic to DashboardViewModel
- [x] Implement available providers checks & keyboard navigation helpers
- [x] Generalize DashboardView to selected provider
- [x] Add Codex Quota Gauges with countdown & warning markers
- [x] Display Cline lifetime cost
- [x] Update menu bar sum and list all active providers in panel
- [x] Validate with build & test suite


## Relay (post-MVP) — COMPLETE 2026-07-06
- [x] Leg 1 Codex — CodexProvider: tokens + REAL quota windows (verified 0.41% vs baseline; quotas live)
- [x] Leg 2 Cursor — ClineProvider: tokens + $ cost (exact match: 131,011,355 tokens / $22.74); Cursor detection
- [x] Leg 3 Antigravity — multi-provider UI, quota gauges w/ countdowns, cost display, menu bar sum (screenshot-verified)
- [x] Leg 4 Kimi — notification thresholds 80/95% (11 tests, no-spam re-arm), QUOTA ALERTS toggle, docs
- [x] Fable final: accent-as-data cost fix, full verification — 59/59 tests, build green
Remaining post-relay: Cursor metrics (dashboard API auth), Antigravity data source, WidgetKit, app polish.

## padzy-os skill enhancement — 2026-07-06

Gap analysis done (baseline: current skill cannot answer these build questions):
dataviz/charts absent (Tokei IS a dashboard); anti-slop = one phrase; no data-formatting
spec; focus-visible contradiction ("no glow ring" vs a11y); no overlay/scrim/toast spec;
no dark-ground rules; no empty/error/destructive patterns; decks/PDF promised but missing;
stale theme lists; no responsive/metrics/voice/perf thresholds.

- [x] NEW `references/antislop.md` — AI-slop tell taxonomy (visual/layout/copy/motion/dataviz) + Padzy replacement per tell
- [x] NEW `references/dataviz.md` — chart rules: one-accent series logic, hairline axes, mono ticks, stat tiles, sparklines, chart states
- [x] NEW `references/decks-print.md` — decks, PDFs, docs surface rules
- [x] `language.md` — data formatting, measure cap, focus-visible spec, dark-ground rules, responsive degradation, voice
- [x] `components.md` — modal/scrim, toast, command palette, empty state, destructive pattern, control metrics
- [x] `ux-principles.md` — perceived-performance thresholds
- [x] `themes.md` — fix stale: volini + aitracker now locked
- [x] `SKILL.md` — wire new refs, fix stale theme list, extend shipping checklist
- [x] Verify: subagent probe PASSED — agent routed to dataviz.md + antislop.md via SKILL.md alone; all 5 specs compliant (focus+context series, tile anatomy, empty state, slop-free hero, focus-visible outline)
- [x] NEW `references/image-mockups.md` — GPT Images mockup loop (prompt recipe + image→code reconciliation); wired as SKILL.md step 4
- [x] Verify: Auto Coach probe PASSED — agent hit image-mockups.md via routing, produced full-recipe prompt (theme hexes, positive invariants, negative slop bans, aspect, single-variable variations) + correct reconciliation plan
