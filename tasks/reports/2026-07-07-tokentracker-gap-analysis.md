# TokenTracker vs Tokei — Gap Analysis & Contradiction Check

**Date:** 2026-07-07
**Compared repo:** https://github.com/mm7894215/TokenTracker (`mm7894215`, MIT, npm `tokentracker-cli`)
**Our repo:** Tokei (`AIUsageDashboard/`, macOS SwiftUI native)
**Method:** Read TokenTracker source directly via GitHub API — `usage-limits.js`, `subscriptions.js`, `claude-config.js`, `passive-mode.js`, `codex-token-refresh.js`, full file tree, README.

---

## 1. What TokenTracker is (architecture)

- **Node.js core** (`src/`) + **web dashboard** (`dashboard/`, React, served at `localhost:7680`) rendered inside native shells: macOS menu-bar app (`TokenTrackerBar/`, SwiftUI over WKWebView) and Windows tray (`TokenTrackerWin/`, C# + WebView2). Linux = CLI/web. **Cross-platform by construction.**
- Local **SQLite** store. Optional cloud (InsForge edge functions) for sync/leaderboard.
- **Capture = SessionEnd hook injection first, passive log-parse fallback.** `tracker init` writes a `SessionEnd` hook into each CLI's `settings.json` running `node notify.cjs --source=<tool>` → sync fires within seconds. Where hook install fails (WSL, locked settings, sandbox), `passive-mode.js` detects it and the per-tool parsers read session logs directly (fresh after next scheduled sync, not seconds). Same Claude hook schema reused for CodeBuddy (Claude fork).
- ~200 test files, acceptance harness (hook-install smoke, offline-replay, backend-probe-cadence), CI (codeql, dependabot, release-dmg/windows/npm workflows), architecture guardrails, i18n copy registry, visual baselines. Very mature release/CI.

## 2. Capability matrix

| Capability | TokenTracker | Tokei (now) |
|---|---|---|
| Tools tracked | **25** (Claude Code, Codex, Cursor, Gemini CLI, Copilot, Kiro, OpenCode, OpenClaw, Grok, Kilo, Roo, Antigravity, Goose, Zed, Mimo, ZCode, CodeBuddy, WorkBuddy, pi/oh-my-pi, Hermes, Every Code, Kimi, Craft, …) | **5** (Claude Code, Cursor, Antigravity, Codex, Cline) |
| Capture mechanism | Hook injection + passive parse fallback | Passive JSONL/SQLite parse + FSEvents only |
| Live rate-limit/quota | **Claude, Codex, Cursor, Gemini, Kiro, Copilot, Antigravity** — live %, reset countdowns, OAuth-token refresh, 429 cooldown, stale-cache fallback, reset-bank inference | Codex (session/weekly), Antigravity (RE'd local language_server); Cursor built but acct uncapped; Claude hardcoded tiers |
| Cost engine | **LiteLLM 2,200+ models**, daily auto-refresh + curated overrides + 24h disk cache + **bundled offline seed** | Cline only (provider-supplied `$`); Codex estimate = backlog; no general engine |
| Views | Trend, model breakdown, **GitHub-style heatmap**, hourly, monthly, **per-project attribution**, pace-vs-limit bars | Hero numeral, sparklines, daily totals, quota gauges |
| Widgets | 4 (Usage / Heatmap / Top Models / Limits) | Deferred (needs App Group) |
| Cross-platform | macOS + Windows + Linux | macOS only |
| Cloud sync | Opt-in cross-device account view (device-flow OAuth) | None |
| Social | Leaderboard, profiles/likes, share cards + SVG badges, **"Wrapped"** year-in-review | None |
| Skills | `skills-manager` — browse/sync 250+ public skills; `skill-usage` tracks which used | None |
| Onboarding/ops | `init` (dry-run + clean `uninstall` of hooks), `doctor`, `diagnostics`, dual-install detection, passive-mode banner | Issue #12 still open; no doctor/uninstall |
| i18n | 5 langs (de, ja, ko, zh, zh-TW) | English |
| Gamification | Desktop pet (Clawd), confetti | None |

## 3. Contradictions with prior research / open issues

**C1 — "Live quota not possible" is FALSE.** Earlier I told the user quota/limits weren't obtainable (notably Cursor, Antigravity). TokenTracker fetches live limits for 7 providers using the **locally-stored OAuth tokens**, refreshing when stale:
- Codex: `chatgpt.com/wham/usage` + `/wham/rate-limit-reset-credits`, token refreshed via `auth.openai.com/oauth/token` (public client `app_EMoamEEZ73f0CkXaXp7hrann`, mirrors steipete/CodexBar).
- Claude: OAuth usage endpoint (shared budget → 429 cooldown persisted globally, stale-read fallback).
- Cursor: session token → usage summary (confirms our issue #3 `api2.cursor.sh` path is right).
- **Antigravity: live quota windows with reset countdowns are shipped.** Our memory said "real Model Quota is NOT offline / must RE Google endpoint." Disproven — it's fetchable. (Our later local language_server connect-rpc RE is *a* valid path; theirs likely refreshes the Google OAuth token and hits cloud directly.)

**C2 — our own issues are self-consistent; the verbal "not possible" was the outlier.** Issues #3 (Cursor usage) and #5 (Claude 5h/weekly) already assume feasibility. TokenTracker validates both. No open issue needs retraction; two need *upgrading*:
- **#4 (Antigravity):** scope beyond "decode local protobuf" — add live quota fetch; drop the "impossible" framing.
- **#5 (Claude rate-limit):** fetch **live %** via the Claude OAuth token instead of hardcoding published tiers.
- **#13 (honest capability labels):** current labels likely *under-claim* — mark providers whose live quota is actually achievable.

**C3 — capture strategy.** Our issue #2 parses JSONL (correct, and arguably more robust — no `settings.json` mutation). TokenTracker's hook is a **low-latency trigger**, not the token source; passive parse is its fallback = our primary. Opportunity, not a defect: add an optional SessionEnd hook to cut refresh latency from FSEvents-debounce to seconds.

## 4. Proposed new issues (gap-driven)

Prioritized against our existing P0–P2 ship backlog.

- **G1 [P1] Cost engine** — port the LiteLLM pattern: bundled offline pricing seed + daily refresh + curated overrides + fuzzy model matcher → USD for every provider, not just Cline. (Unblocks Codex cost backlog item.)
- **G2 [P1] Live quota for Claude + reconcile Antigravity** — fetch live Claude 5h/weekly % via OAuth token (supersedes hardcoded tiers in #5); confirm Antigravity live path, update #4, drop "impossible" note in memory.
- **G3 [P1] Provider expansion via hook+parser framework** — generalize the connector layer (hook install + passive parse fallback + `status`/`doctor`) so adding a tool is config, not bespoke code. First new targets: Gemini CLI, Copilot, OpenCode.
- **G4 [P2] Optional SessionEnd hook trigger** — opt-in, cuts Claude/Codex refresh latency to seconds; passive parse stays default. Clean `uninstall`.
- **G5 [P2] `doctor` / diagnostics command** — health check: which connectors detected, hook vs passive, token freshness, last sync. Feeds onboarding #12.
- **G6 [P2] Richer views** — GitHub-style activity heatmap + per-project attribution + per-model breakdown.
- **G7 [P3] Cost/usage "Wrapped" + share card** — shareable summary (brand-aligned), local-only render. Growth lever.
- **G8 [P3] Cross-device sync (opt-in)** — decision-gated; ties to monetization issue #11. Local-first stays default.
- **G9 [P3] Skills usage tracking** — track which Claude skills fire per session; lightweight, novel, no new auth.

**Not recommended to port:** full leaderboard/cloud backend (heavy, off-brand for a local-first Padzy tool unless monetization says otherwise), desktop pet/confetti (off-brand), Windows/Linux shells (strategic fork — our native-SwiftUI bet is a deliberate UX choice, not a gap).
