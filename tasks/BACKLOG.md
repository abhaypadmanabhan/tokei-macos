# TOKEI BACKLOG

Single source of truth for future build work. When Abhay says "build the next
thing" (or names an item), pick from here — top of each tier first. Each item
lists enough context to start without re-research. Keep this file updated:
move finished items to DONE with date + commit.

## How agents should use this
1. Read this file + `tasks/relay/BATON.md` (protocol, frozen contracts, Padzy rules).
2. Confirm item scope with Abhay only if the item is marked [needs-decision].
3. Branch `feat/<slug>`, build+test green (`cd AIUsageDashboard && xcodegen generate` first), merge --no-ff, move the item to DONE here.

## P1 — high value, unblocked
- [ ] **Cursor real metrics** — hardest one. Two paths from research
      (`research/provider-research.md` L90-110): (a) local `state.vscdb` SQLite
      read-only copy → parse usage keys; (b) dashboard API with
      `WorkosCursorSessionToken` cookie extracted from state.vscdb (auth
      fragile, undocumented). Start with (a); confidence `.localParsed` for (a),
      `.providerReported` for (b). [needs-decision: is cookie extraction
      acceptable?]
- [ ] **Codex cost estimate** — tokens exist; multiply by plan/model pricing
      table (static, versioned in code, confidence `.estimated`). Shows $ next
      to Codex like Cline.
- [ ] **WidgetKit target** — small/medium widgets showing today total + quota %.
      Needs App Group (`group.ai.padzy.tokei`) + UsageStore reading from the
      shared container; widget target added to project.yml. Deferred twice
      already for signing risk — do it in isolation.
- [ ] **Per-provider alert thresholds** — Settings UI (per provider row:
      80/95 defaults, editable) + NotificationEngine reads per-provider config
      from UserDefaults. Engine already has injectable evaluator.

## P2 — polish / depth
- [ ] **Daily history chart view** — UsageStore.dailyHistory() is persisted but
      unused by UI. Add a `03 / HISTORY` pane: 30-day bar chart per provider,
      Padzy style (hairline bars, accent = today).
- [ ] **Session drill-down** — per-session table (Dense tier) for the selected
      provider: session id, start, tokens, cost where known.
- [ ] **Launch at login** — SMAppService toggle in Settings.
- [ ] **CSV/JSON export** — export dailyHistory + snapshots from Settings.
- [ ] **Menu bar display options** — Settings: choose which providers count
      toward the menu bar total; compact vs percent display.
- [ ] **Sparkline hover** — hover a sparkline point → mono tooltip with date +
      exact tokens (macOS hover affordance).

## P3 — research / speculative
- [ ] **Antigravity data source** — `~/.antigravity` + Application Support
      exist but format unknown (research stalled). Needs a scout pass first.
- [ ] **Claude quota windows** — session/weekly limits not in local logs;
      requires OAuth usage endpoint (`research/provider-research.md` L40-60).
      [needs-decision: OAuth scope/comfort]
- [ ] **Cline credits balance** — app.cline.bot internal API, undocumented.
      [needs-decision]
- [ ] **Multi-machine aggregation** — sync usage-store.json via iCloud Drive
      container; dedupe by day+provider.
- [ ] **App Store / notarization** — Developer ID signing, sandbox
      entitlements (read-only home dirs won't fly in sandbox — needs
      security-scoped bookmarks UX), notarized DMG pipeline.

## DONE
- 2026-07-06 — MVP: Claude parser + dashboard + menu bar + persistence +
  watcher (commit 1ccf4d1); Tokei rebrand + icon + hero UI (db5f421);
  Relay legs 1-4: Codex quotas, Cline cost, multi-provider UI, notifications
  (ff3b897, 4bdc594, 67017b0, cc3cb17); close-out 400c1e8. 59 tests.
