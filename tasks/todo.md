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
- [ ] A Kimi — persistence (JSON store + daily rollups) + FSEvents watcher + auto-sync — branch agent/kimi-storage-watcher
- [ ] B Cursor — parser rewrite vs real schema + dedupe + tests — branch agent/cursor-parser
- [ ] C Antigravity — Padzy UI: dashboard, menu bar live count, shared VM — branch agent/antigravity-ui
- [ ] D Fable — review diffs, merge, integrate updates stream into VM, build/tests, final report

## Definition of done (MVP)
- Claude tokens correct vs ccusage-style dedupe baseline (±1%)
- Dashboard: today/7D/30D/lifetime + confidence labels; other providers marked unavailable
- Menu bar: live today total + sync status
- Auto-refresh on ~/.claude/projects changes (debounced) + manual ⌘R
- History persisted to Application Support (survives log rotation)
- Build + all tests green
