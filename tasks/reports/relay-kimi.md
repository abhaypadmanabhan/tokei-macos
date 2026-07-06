# Relay Leg 4 — Kimi Report

## Changed Files

- `AIUsageDashboard/AIUsageDashboardApp/Core/Notifications/NotificationEngine.swift`
  - Implemented `NotificationEngine` actor with 80%/95% threshold evaluation.
  - Added injectable `Clock` protocol + `SystemClock` and `UserNotificationCenter` protocol + `UserNotificationCenterWrapper` for testability.
  - Extracted pure `ThresholdEvaluator` for percent, crossing, and re-arm logic.
  - Added `FiredNotificationKey` (provider + window + threshold + stored resetAt) persisted in UserDefaults.
  - No-spam re-arm: fires once per threshold until the stored `resetAt` passes or percent drops below the threshold.
  - Lazy notification authorization: only requests UNUserNotificationCenter permission when a threshold is crossed.
  - Master toggle read from `notificationsEnabled` UserDefaults key (default true).
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/SyncEngine.swift`
  - One-line hook: `await NotificationEngine.shared.evaluateThresholds(for: snapshots)` after each `refreshAll()` save.
- `AIUsageDashboard/AIUsageDashboardApp/UI/Settings/SettingsView.swift`
  - Added real "QUOTA ALERTS" toggle bound to `notificationsEnabled` via `@AppStorage`.
  - Added "ALERTS AT 80% / 95%" threshold label and description text.
  - Preserved existing Padzy styling and watcher description; increased settings window height to fit the new section.
- `AIUsageDashboard/Tests/NotificationTests/NotificationEngineTests.swift`
  - New test suite with 11 tests covering: single threshold fire, dual 80/95 fire, no re-fire while armed, re-arm after resetAt, re-arm after percent drop, disabled toggle suppression, unavailable confidence ignored, missing limit skipped, authorization denied suppression, persistence across engine re-init, and pure evaluator re-arm.
  - Uses protocol fakes: injectable `FakeClock` and `FakeNotificationCenter`; zero real notifications delivered.
- `AIUsageDashboard/project.yml`
  - Added `UserNotifications.framework` dependency to `AIUsageDashboardCore`.
- `AIUsageDashboard/README.md` and `AIUsageDashboard/docs/04-implementation-roadmap.md`
  - Updated "What Works", "What Is Stubbed", roadmap status to reflect legs 1–4 (Codex quotas, Cline cost, multi-provider UI, notifications).

## What Works

- Quota threshold notifications fire at 80% and 95% for any quota window with `used`/`limit` and non-unavailable confidence.
- No-spam re-arm logic: one notification per threshold per window reset/usage-drop cycle.
- UserDefaults persistence of armed state survives relaunch.
- Settings toggle enables/disables the engine in real time.
- SyncEngine invokes the engine after every refresh.
- Full test suite: 59 tests passing (48 previous + 11 new).
- App and core framework build green after `xcodegen generate`.

## Stubbed / Skipped

- No per-provider or per-threshold custom overrides (master toggle only).
- Notification sound/body formatting is fixed; no custom user messages.
- Settings window height increased slightly to accommodate the new section; further visual polish deferred.

## Tests Run

```bash
cd AIUsageDashboard && xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
```

Result: **59 tests passed, 0 failures**.

## Risks / Watch Out

- Real Codex quota windows on this machine are ~29% (session) and ~38% (weekly), so no live 80%/95% fire during this session; behavior is covered by unit tests with synthetic data.
- The `UserNotificationCenter` wrapper is marked `@unchecked Sendable` because `UNUserNotificationCenter.current()` is a singleton. This is standard but worth noting under strict concurrency.
- UserDefaults armed state is keyed by `(providerID, windowType, threshold)`; if a provider changes its `resetAt` without the old one passing and usage stays above the threshold, the engine will not re-fire until the stored resetAt passes. This matches the spec's "resetAt passes" re-arm rule.

## Handover

Leg 4 complete. Relay finished — return to Fable (Claude Code) and say `relay done` for final review.
