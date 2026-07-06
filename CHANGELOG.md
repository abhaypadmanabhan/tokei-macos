# Changelog

All notable changes to Tokei (`ai.padzy.tokei`). Format loosely follows
[Keep a Changelog](https://keepachangelog.com/). Dates are ISO-8601.

## [Unreleased] — dev (release candidate 2026-07-06)

Prepared via `/dev-approved`. On `dev`, **not yet merged to `main` or tagged.**
Suggested version for this release: **0.2.0** (feature release over the 0.1.0 MVP) —
bump `MARKETING_VERSION` in `AIUsageDashboard/project.yml` at merge if adopted.

### Added
- **OpenAI Codex — estimated USD cost.** Static, dated per-model pricing table
  (`CodexPricing`) multiplies parsed token components into an estimated cost shown
  next to Codex, at `.estimated` confidence. Newer model slugs (`gpt-5.5`,
  `gpt-5.4`, `gpt-5.3-codex`) price under the verified `gpt-5` base rate via
  boundary-aligned family fallback; a slug with no known base family shows no cost
  (never a fabricated number).
- **Cursor — local read layer.** Reads `state.vscdb` (SQLite) from a read-only temp
  copy, excluding secret/auth rows, and surfaces real token windows at `.localParsed`
  confidence when Cursor writes token-count rows locally. No network, no cookie/dashboard
  auth. Falls back honestly to "unavailable" with an info warning otherwise.
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
