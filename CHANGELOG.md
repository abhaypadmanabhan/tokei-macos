# Changelog

All notable changes to Tokei (`ai.padzy.tokei`). Format loosely follows
[Keep a Changelog](https://keepachangelog.com/). Dates are ISO-8601.

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
