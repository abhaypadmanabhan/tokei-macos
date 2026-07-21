# Changelog

All notable changes to Tokei (`ai.padzy.tokei`). Format loosely follows
[Keep a Changelog](https://keepachangelog.com/). Dates are ISO-8601.

## [Unreleased] — on `dev` (2026-07-19 wave)

Audit trail: `tasks/patch-bibles/2026-07-19.md`. Awaiting manual QA (`/dev-approved`).

### Changed
- **New brand identity.** Rebranded to the red/black split-square + white swoosh mark:
  regenerated app icon (all sizes, Big Sur grid, transparent corners), `BrandMark` /
  `BrandWordmark` assets, in-app logo, and a dynamic menu-bar mark that fills
  black→accent as the tightest quota window burns (0→100%). Palette unchanged
  (`#131316` / `#FF3B70` / `#FAFAF8` already matched the app theme).
- **Overview quota/heatmap/hover fixes (re-QA).** Heatmap now follows the 7/30/90-day
  range control (was folding all-time). The Quota lens shows used% + %-remaining per
  agent instead of tokens. Every provider with live quota enabled now appears in the
  quota view with an honest state (fetching / connect / local-only) — previously a
  provider whose fetch was transiently down (cooldown/auth) silently vanished. Menu-bar
  quota bars animate-fill and show a red pace notch vs the previous period. Trend graph
  and heatmap gained hover callouts (date · total · top agent).
- **Full dashboard redesign — sidebar removed.** The 10-row sidebar is gone: Overview
  and Value are in-content tab pills (doubling as the KPI row), each provider is a chip
  in a strip with a trailing `+` (Add agent) and drills into a unified detail view,
  Settings and Add-agent are right-hand drawers (gear icon / `+`). Overview condensed
  6 cards → 4 with an hour-tinted activity heatmap; Value rebuilt around an 84pt hero
  multiple + tier chip + hairline rows; Agents tab is per-agent management cards; the
  menu-bar popover was rebuilt (tokens hero + plan value + tightest quota + top agents).
  ~900 lines of dead code removed. Real Cline/opencode brand marks. Fixes 3 aggregate
  bugs (hidden agents feeding the hero, merged-confidence reading UNAVAILABLE over a real
  total, StatCard dropping date captions).

### Added
- **Value pane (#23).** "Am I using the tokens I pay for" — headline plan-value multiple
  (API-equivalent USD ÷ configured monthly plan cost) with Maxxer tier (idle / warming /
  break-even / maxxing / goblin mode), dense per-agent table (plan $, API-equiv $,
  multiple, confidence), real empty/loading/error states. Totals are paired-only: a
  provider without a configured plan cost never inflates the headline multiple.
- **Plan costs in Settings (#23).** Per-provider monthly USD entry (blank = unset, never
  $0), persisted to `maxxer.planCost.<providerID>`.
- **Lifetime usage (#41).** "X tokens all-time" stat with confidence badge (reported
  lifetime preferred, daily-totals floor as fallback) + fourth menu-bar display mode
  showing all-time tokens.

### Fixed
- **QuotaSeriesStore retention now per-series (#48)** — a high-frequency series can no
  longer evict another series' history (cap 2 000/series, global 20k backstop).
- **Cursor cooldown scoped per account (#49)** — cooldown files keyed by SHA-256 hash of
  the session cookie; a 429 on one account no longer gates another. Legacy global
  cooldown honored for its remaining duration, then removed.

## [0.5.0] — 2026-07-13 (release candidate)

Prepared via `/dev-approved`. On `dev`, PR [#50](https://github.com/abhaypadmanabhan/tokei-macos/pull/50);
**not yet merged to `main` or tagged.** Audit trail: `tasks/patch-bibles/2026-07-12.md`.
Manual QA completed against the `dev` Debug build (menu-bar item verified rendering).

### Added
- **Gemini connector (#26).** New provider surfacing Google Gemini CLI quota. Reads
  `~/.gemini/oauth_creds.json` **read-only**, refreshes via `oauth2.googleapis.com`, then
  queries cloudcode-pa `loadCodeAssist` → `retrieveUserQuota` for per-window used%/reset.
  `.providerReported` confidence; degrades to a clean empty state when gemini-cli is absent
  or not signed in. TLS uses default validation; the OAuth token is never logged or placed
  in a URL. Only the **public** gemini-cli client id is bundled — no client secret.
- **Live model pricing (LiteLLM).** Replaced the frozen ~15-model static price snapshot with
  a resilient `PricingService`: fresh <24h disk cache → live LiteLLM fetch (async, off the UI
  path) → stale cache → bundled seed, resolving ~2.5k models. Costs for previously-known
  models are unchanged. Built on the existing `Core/Pricing` engine/seed.

### Fixed
- **Menu-bar battery drain.** The status item held an always-on `Timer.publish(0.15s)` that
  woke the main runloop ~6.6×/s for the app's whole lifetime. The spinner now ticks only
  during an active sync (via a `.task(id:)` loop) — nothing at idle.
- **Menu-bar item render regression.** A first cut of the battery fix put a `TimelineView`
  inside the `MenuBarExtra` label, which SwiftUI snapshots into the status-item image — that
  broke the render and the item disappeared. Restored via a `@State`-backed `Image`.

### Changed
- **Internal dedup (#45).** Extracted the duplicated SQLite `-wal`/`-shm` sidecar-copy loop
  (3 DB parsers) into one `SQLiteSidecarCopy` helper, and the RFC-1123 Retry-After /
  cooldown-persistence logic (2 network clients) into one `CooldownStore`. Cooldown-write
  failures are now logged instead of silently dropped (was causing repeat 429s across
  relaunch). Behavior-preserving.

### Known limitations
- **Gemini expired-token refresh** needs the gemini-cli OAuth client secret, which is
  deliberately not bundled. A valid token works fully; an expired one degrades to a "run
  `gemini` to refresh" nudge until re-authed. (Greptile P1 — accepted for this release.)
- **First-sync live pricing:** a model that exists only in the live LiteLLM table (not the
  bundled seed) may show cost unavailable on the very first sync that triggers the background
  refresh; it resolves on the next sync. (Greptile P2 — accepted.)
- **Gemini live quota schema** modeled on the 2026-07-06 cloudcode-pa capture; unverified
  against a live authed machine. Degrades to empty cleanly if Google's shape differs.
- `mark_gemini` menu asset not yet added — the Gemini row falls back to an SF Symbol.

## [Unreleased] — dev (release candidate 2026-07-06)

Prepared via `/dev-approved`. On `dev`, **not yet merged to `main` or tagged.**
Suggested version for this release: **0.2.0** (feature release over the 0.1.0 MVP) —
bump `MARKETING_VERSION` in `AIUsageDashboard/project.yml` at merge if adopted.

### Added
- **Antigravity — live Model Quota (opt-in).** New `AntigravityQuotaClient` reads the
  real per-model-group weekly + 5-hour limits (Gemini / Claude&GPT) with reset countdowns
  from the running Antigravity app's **local** `language_server` connect-rpc
  (`RetrieveUserQuotaSummary`, csrf-authed over 127.0.0.1-scoped TLS) — the Google `ya29`
  OAuth token is never read, sent, or stored. Gated behind `@AppStorage("antigravityOnlineQuotaEnabled")`
  (default OFF); degrades silently to local data when the app is closed. Rendered as grouped
  gauges + live countdowns, `.providerReported` confidence. Verified end-to-end against live
  data (91.5%/87.6% Gemini, 100%/100% Claude&GPT).
- **Cursor — accurate plan label.** Opt-in `full_stripe_profile` fetch (same Bearer JWT) adds
  an honest plan label (`Pro · monthly · auto-billing on`); no fabricated gauge for uncapped
  accounts.
- **OpenAI Codex — estimated USD cost.** Static, dated per-model pricing table
  (`CodexPricing`) multiplies parsed token components into an estimated cost shown
  next to Codex, at `.estimated` confidence. Newer model slugs (`gpt-5.5`,
  `gpt-5.4`, `gpt-5.3-codex`) price under the verified `gpt-5` base rate via
  boundary-aligned family fallback; a slug with no known base family shows no cost
  (never a fabricated number).
- **Cursor connector (A offline + B network toggle).** A: reads `state.vscdb` (read-only
  temp copy) for plan/tier (`stripeMembershipType`/`stripeSubscriptionStatus`) and
  accepted-code-lines/day (`aiCodeTracking.dailyStats`) — the local DB has NO token counts,
  so token usage is honestly `.unavailable` offline. B: opt-in `@AppStorage("cursorNetworkUsageEnabled")`
  (default OFF) → one authenticated `GET api2.cursor.sh/auth/usage` (JWT as Bearer over TLS only)
  for real quota at `.providerReported`; defensive decode falls back to A on any drift, never crashes.
- **Antigravity connector — offline protobuf.** Zero-dependency `MiniProtobufReader` decodes
  `state.vscdb` `userStatusProtoBinaryBase64` (plan "Pro" + raw quota fields) and `modelCredits`
  (available/min) via read-only SQLite `json_extract` — the `apiKey`/OAuth token never enters
  Swift memory. Surfaces plan + a `.credits` quota window at `.localParsed`. Fully offline.
- **In-app Settings pane.** Settings now render inside the dashboard window's right
  pane, reached from a bottom-pinned `SETTINGS` entry in the provider sidebar (and the
  menu-bar `SETTINGS` button). Sections: `QUOTA ALERTS`, `REFRESH INTERVAL`, `ABOUT`.
  The separate macOS Settings (⌘,) dialog was removed.
- Reusable `SurfaceStateView` — real loading / empty / error states across dashboard
  and menu bar.
- **Value engine (internal, no UI yet).** New `Core/Pricing` layer — `PricingEngine`
  turns `(model, token counts)` into API-equivalent USD for *every* provider (not just
  Cline's provider-supplied `$`), pricing input / cache-creation / cache-read / output at
  distinct rates, folding reasoning into output. Dated bundled offline `PricingSeed`
  (Anthropic / OpenAI-Codex / curated Cursor·Kimi·Cline·GLM overrides), boundary-prefix
  fuzzy model matcher, and an `APIEquivalentCost` value type carrying `MetricConfidence`
  plus an unpriced-token coverage flag. Unknown slugs yield `nil`, never a guessed number.
  A `refresh()` seam is stubbed for a future daily LiteLLM pull (no network this cycle).
  Not yet surfaced in the UI (the "value multiple" hero lands with #23). (#22)
- **Utilization spine (internal, no UI yet).** New `Core/Utilization` layer — a unified
  `Utilization` / `AggregateUtilization` contract and a pure `UtilizationEngine` that maps
  the snapshots Tokei already collects to a live-quota `usedPercent` per window (omitting,
  never zero-filling, providers with no computable quota) plus a single "today's
  utilization across plans" aggregate (mean of each provider's peak window). Ships a fully
  tested `UtilizationCache` actor (TTL expiring early at the next reset, a **global** 429
  cooldown marker, and a token-free last-good sidecar) — the robustness primitives the
  Claude live fetch (#5) will reuse. `DashboardViewModel` gains read-only `utilization` /
  `aggregateUtilization` accessors. Not yet wired to any fetch path or view. (#21)
- **Cursor — real token usage + live quota (opt-in, user-visible).** Re-pointed the
  Cursor connector off `api2.cursor.sh` (which returns only a request count, empty for
  uncapped Pro) onto the `cursor.com` dashboard endpoints, authenticating with the WorkOS
  session cookie: `export-usage-events-csv?strategy=tokens` → per-event token usage parsed
  into today / week / month (input / cache-read / cache-write / output split) + daily
  totals; `usage-summary` → plan utilisation % (reset = billing-cycle end). Cookie userId
  is derived from the JWT `sub` (normalized like the Cursor CLI); the token is never logged
  or persisted. Gated behind `cursorNetworkUsageEnabled` (default OFF); any failure falls
  back to the offline code-line read. Verified live: today 1.38M tokens, quota 7%
  "Pro (active)". Closes the "Cursor detection-only" gap in #13. (#3)

### Changed
- **Padzy "aitracker" design-system compliance:** accent reserved to state/action only
  (cost + sparklines render in ink, not accent), all numeric data in DM Mono, dark-mode
  locked on all surfaces, hairline structure, radius ≤ 4px.
- About copy drops the misleading "TELEMETRY" wording → "LOCAL-FIRST AI USAGE · nothing
  leaves your machine"; version read live from the bundle.
- `no-secret` gate no longer self-matches its own pattern literals (excludes only
  `no-secret.sh`; every other file — including other gate scripts — stays scanned).

### Fixed
- Codex cost previously showed nothing on machines running `gpt-5.x` models (unpriced).
- Settings were unreachable (a menu-bar-extra app has no ⌘, app menu).

### Known issues
- Cursor token metrics are unavailable where `state.vscdb` holds only local code-line
  stats (no token counters). Antigravity remains a non-interactive skeleton.
- Codex cost prices the whole lifetime aggregate under the most-recent model (no
  per-model token bucketing yet).
- UI error state is wired but not yet reachable live (no Core path sets `errorMessage`).
- Menu-bar *label* total is not monospaced (lives in `App/`, deferred).
- Distribution not configured: adhoc/unsigned, not notarized (see release doc).

## [0.1.0] — 2026-07-06 (MVP)
- Claude Code, OpenAI Codex, and Cline/Cline Pass local adapters; multi-provider
  dashboard, menu-bar extra, FSEvents auto-refresh, JSON persistence, quota
  notifications. See `AIUsageDashboard/README.md`.
