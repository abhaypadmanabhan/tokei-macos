# Website update — v0.4.0 (2026-07-09)

A Next.js site exists (in/near the repo). Deploying is an outward action — do these when shipping v0.4.0,
after Abhay's go-ahead. This is a scope list, not applied edits.

## Update
- [ ] **Version string** → `0.4.0` wherever the current version is shown.
- [ ] **Download link** → new DMG for tag `v0.4.0` (`Tokei-0.4.0-arm64.dmg`) + updated appcast if the
      site references it.
- [ ] **Changelog / What's New** highlight:
      - Full visual redesign — analytics dashboard (charts, donut, activity heatmap, gauges, streaks).
      - Token-Maxxer: pace verdict, tightest-window %, route-here, dynamic menu-bar status icon.
      - Cursor 429 resilience; quota history sampler.
- [ ] **Screenshots** — replace old flat-UI shots with the redesigned Overview / Provider Detail /
      Settings / menu-bar popover (hero screenshots are the main marketing asset for a redesign).
- [ ] **Supported providers** — confirm the list shows: Claude Code, Codex, Cursor, Cline, Antigravity
      (plan-only), OpenCode. (opencode already added in 0.3.0.)

## Do NOT overclaim
- Antigravity is **plan/credits/quota-only** — do NOT market Antigravity token/cost tracking (Tokei stays
  honest; that data isn't locally available). See the release doc's Antigravity decision.
