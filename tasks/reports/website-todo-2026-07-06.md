# Website TODO — Tokei (no site exists yet)

No website exists anywhere in/near the repo (confirmed: no HTML/landing assets). This
lists exactly what to build/update when a site is created. Tracks issue #10 (P0).

## Create (single-page, Padzy "aitracker" theme — same treatment as Voxi)
- **Hero** — name + one-line ("local-first AI usage dashboard for macOS"), app screenshot.
- **Feature list** — local-first · zero network calls · zero-config · multi-provider
  (Claude Code, OpenAI Codex, Cline; Cursor local read layer; Antigravity skeleton).
- **Download** — DMG button → GitHub Releases (needs a signed+notarized build first, issue #8).
- **/privacy** — short + honest: "Tokei reads local agent log files and never transmits
  them; update checks contact <appcast-host> only." (Matches the in-app ABOUT copy.)
- **Support** — mailto + GitHub Issues link.
- **Appcast host** — for Sparkle auto-update (issue #9).

## Values to fill from this release (keep in sync with CHANGELOG.md)
- **Version:** 0.1.0 today; **0.2.0** if bumped at merge. Wire to the changelog highlight.
- **Supported providers (accurate as of 2026-07-06):**
  - Claude Code — full local token tracking.
  - OpenAI Codex — token windows + session/weekly quota + **estimated USD cost** (new).
  - Cline / Cline Pass — tokens + real dollar cost.
  - Cursor — **local read layer (new)**; surfaces tokens when present, else "unavailable".
  - Antigravity — detected, data source TBD (skeleton).
- **Feature highlights for copy:** estimated Codex cost, in-app Settings, real
  empty/loading/error states, Padzy design system, one-accent restraint.
- **Changelog highlight:** link `CHANGELOG.md` *Unreleased* section.

## Blockers
- Download link needs a distributable (signed+notarized) build — issue #8.
- Privacy page's update-check host depends on the appcast decision — issue #9.
- Hosting choice (Vercel or GitHub Pages) — Abhay.
