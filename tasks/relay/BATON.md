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
