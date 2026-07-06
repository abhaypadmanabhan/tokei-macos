# RELAY LEG 4 — Kimi: notification thresholds, real Settings, docs

Read `tasks/relay/BATON.md` first — standing rules, build commands, frozen
contracts. Read Leg 1–3 handover entries. Branch: `relay/04-kimi`.

## Mission
Close the loop: quota threshold notifications (Codex windows are live now),
make Settings real, refresh docs. Final leg before Fable review.

## Files you own
- `AIUsageDashboard/AIUsageDashboardApp/Core/Notifications/NotificationEngine.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/SyncEngine.swift` (ONLY the notification hook below)
- `AIUsageDashboard/AIUsageDashboardApp/UI/Settings/SettingsView.swift`
- `AIUsageDashboard/Tests/NotificationTests/*` (new)
- `AIUsageDashboard/README.md`, `AIUsageDashboard/docs/` (status refresh only)
Nothing else. No provider/parser/model edits. No dashboard/menu-bar edits.

## Spec
1. **NotificationEngine** (actor, exists as skeleton):
   - `evaluateThresholds(for snapshots: [ProviderSnapshot])`: for every
     QuotaWindow with `used != nil && limit != nil` and confidence not
     `.unavailable`, compute percent. Thresholds 80% and 95% (constants).
   - Fire via `UNUserNotificationCenter`: title "Tokei", body e.g.
     "Codex weekly window at 82% — resets 14:32". Request authorization
     lazily on first fire, not at launch.
   - **Debounce/no-spam**: remember per (providerID, windowType, threshold)
     which threshold was already notified; re-arm only after the window's
     `resetAt` passes or percent drops below the threshold. Persist this state
     in UserDefaults (survives relaunch; keep it simple, no UsageStore change).
   - Master toggle read from UserDefaults key `notificationsEnabled`
     (default true).
   - Design for testability: percent/threshold/re-arm logic in a pure,
     injectable-clock component; UNUserNotificationCenter behind a small
     protocol so tests don't touch the real center.
2. **SyncEngine hook**: after each `refreshAll()` save, call
   `await NotificationEngine.shared.evaluateThresholds(for: snapshots)`.
   One line plus wiring — change nothing else in SyncEngine.
3. **Settings — make it real** (keep exact Padzy styling already in the file):
   - GENERAL tab: Toggle "QUOTA ALERTS" bound to `notificationsEnabled`
     (@AppStorage), static text showing thresholds "ALERTS AT 80% / 95%",
     the existing watcher description stays.
   - ABOUT tab: unchanged except verify it still says TOKEI.
   - Toggle styling: default macOS switch is fine (platform contract) — do
     not build a custom toggle.
4. **Tests** (`Tests/NotificationTests/`): threshold crossing fires once;
   no re-fire while armed; re-arms after resetAt passes (injectable clock);
   disabled toggle suppresses; unavailable-confidence windows ignored.
   Use the protocol fake, zero real notifications in tests.
5. **Docs**: README "What Works" + roadmap — reflect legs 1–4 (Codex quotas,
   Cline cost, multi-provider UI, notifications). Update
   `docs/04-implementation-roadmap.md` status column/section if it has one.
   Keep edits surgical.

## Definition of done
Build green; ALL tests green (every previous leg's included); toggling the
setting on/off works in the running app; merged to main --no-ff; report
`tasks/reports/relay-kimi.md` + BATON handover entry.

## Handover
End with exactly:
"Leg 4 complete. Relay finished — return to Fable (Claude Code) and say 'relay done' for final review."
