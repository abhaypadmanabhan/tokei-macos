# TOKEI RELAY BATON

Sequential relay. One agent at a time. Read this file FIRST, run your leg
(`tasks/relay/0N-<agent>.md`), then APPEND your handover entry below and tell
the user the next leg's file. Do not run someone else's leg.

## Standing rules (every leg)
- Work in `/Users/abhayp/Downloads/Projects/AI_tracker` (main repo, no worktrees —
  relay is sequential). Branch `relay/0N-<agent>` off `main`, commit there,
  merge back to `main` with `--no-ff` ONLY after build + all tests are green.
- Build/test (always regenerate first — `.xcodeproj` is gitignored):
  ```
  cd AIUsageDashboard && xcodegen generate
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
  ```
- Frozen contracts: `UsageProvider` protocol; `UsageStore` public API;
  existing `ProviderSnapshot` fields (append-only — and any new stored field MUST
  be added to `Core/Storage/ModelCodableExtensions.swift` in the same commit,
  it is manual Codable); existing tests stay green, never delete or weaken them.
- Design: Padzy OS theme "aitracker" — ground #131316, surface #1D1D22,
  ink #ECECF1, muted #6E6E78, ONE accent #FF3B70. Mono for all data. No shadows,
  no gradients, no rounded card grids, radius ≤4px. UI changes only in the
  Antigravity leg.
- Test fixtures = Swift string literals in `Tests/Fixtures/Fixtures.swift`
  (never resource files).
- Report: write `tasks/reports/relay-<agent>.md` (changed files / what works /
  stubbed / tests run / risks) and append handover entry below.

## Current state (start of relay, main @ db5f421+)
- Product: **Tokei** (`ai.padzy.tokei`), Padzy dark dashboard, live menu bar count.
- Claude Code: fully working (parser verified <0.1% vs baseline, sparklines via
  `ProviderSnapshot.dailyTotals`, FSEvents auto-sync on `~/.claude/projects`).
- Codex/Cursor/Cline/Antigravity providers: skeletons returning unavailable.
- 27 tests green.

## Legs
1. `01-codex.md` — Codex: real CodexProvider (tokens + REAL quota windows) — **run this first**
2. `02-cursor.md` — Cursor: ClineProvider (tokens + cost), Cursor detection
3. `03-antigravity.md` — Antigravity: multi-provider UI, quota gauges, cost display
4. `04-kimi.md` — Kimi: notification thresholds, real Settings, docs
Then the user returns to Fable (Claude Code) for final review with: "relay done".

## Handover log (append below — newest last)
<!-- template:
### Leg N — <agent> — <date>
- Merged: <commit sha> ("<subject>")
- Done: ...
- Stubbed/skipped: ...
- Tests: N passing
- Watch out: ...
-->
### Leg 1 — Codex — 2026-07-06
- Merged: a8701fb ("Implement Codex usage provider")
- Done: Replaced the Codex skeleton with a local `~/.codex/sessions` JSONL adapter, token delta aggregation, daily totals, latest provider-reported session/weekly quota windows, `~/.codex` availability/auth detection, shared `UsageWindows` bucketing with Claude, and watcher defaults for Claude + Codex paths.
- Stubbed/skipped: Codex cost remains nil; auth is presence-only for `auth.json` by design.
- Tests: 37 passing
- Watch out: Codex real-log smoke saw 1 malformed-line warning skipped; latest smoke printed 39 files, 139,497,475 delta tokens vs 138,915,496 final-session tokens (~0.42% diff), session quota 18%, weekly quota 36%.

### Leg 2 — Cursor — 2026-07-06
- Merged: 4bdc594 ("Merge relay/02-cursor: Cline provider and Cursor detection.")
- Done: Real `ClineProvider` from `~/.cline/data/sessions/*/*.messages.json` with token windows via shared `UsageWindows`, lifetime dollar cost in `CostUsage`, message dedupe by `id`, and `FileWatcher` path for Cline sessions. `CursorProvider` detects install via `state.vscdb` presence only; metrics stay unavailable with post-MVP warning.
- Stubbed/skipped: Cline credits quota and auth (no cline.bot API); Cursor metrics/SQLite; `~/.cline/db/` ignored.
- Tests: 47 passing
- Watch out: Cline real-log smoke printed 13 files, 131,011,355 lifetime tokens, $22.74 total cost; `CostUsage` is lifetime-only (no period fields on model).

### Leg 3 — Antigravity — 2026-07-06
- Merged: 67017b0 ("Merge relay/03-antigravity: multi-provider UI, quota gauges, cost")
- Done: Replaced static Claude-only dashboard/sidebar with dynamic multi-provider selection driven by `selectedProvider` in `DashboardViewModel`. Implemented Codex quota gauges with visual hairline meters, live-updated countdown timers, >90% warning indicators (using only `PadzyTheme.accent` per theme guidelines), and custom VoiceOver labels. Integrated Cline lifetime cost display in today breakdown and the lifetime metric block corner. Updated the menu bar to show summed today total, and populated the menu bar panel with dynamic dense rows for all active providers.
- Stubbed/skipped: Left Cursor and Antigravity snapshots unavailable/non-interactive per leg requirements.
- Tests: 48 passing
- Watch out: Sidebar selection via ↑/↓ keys requires focus to be active on the dashboard.

### Leg 4 — Kimi — 2026-07-06
- Merged: TBD ("Merge relay/04-kimi: quota notifications, real Settings, docs")
- Done: Implemented `NotificationEngine` with 80%/95% quota thresholds, no-spam re-arm logic (resetAt-based + percent-drop), UserDefaults-persisted armed state, lazy UNUserNotificationCenter authorization, and injectable clock/notification-center fakes. Wired one-line hook into `SyncEngine.refreshAll()`. Made Settings real with a "QUOTA ALERTS" toggle bound to `notificationsEnabled`, threshold text, and preserved Padzy styling. Refreshed README and roadmap to reflect legs 1–4.
- Stubbed/skipped: Per-provider threshold overrides, custom notification body overrides, and extended settings polish deferred.
- Tests: 59 passing (48 previous + 11 new notification tests).
- Watch out: Real Codex windows are ~29% session / ~38% weekly on this machine, so live 80%/95% fires will be exercised later; UNUserNotificationCenter wrapper is `@unchecked Sendable` due to singleton usage.

