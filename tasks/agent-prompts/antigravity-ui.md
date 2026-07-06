# Agent: Antigravity — Package C: UI MVP (Padzy OS design, STRICT)

Worktree: `/Users/abhayp/Downloads/Projects/AI_tracker-antigravity` (branch `agent/antigravity-ui`).
Work ONLY there. Commit to that branch.

## Setup / build / test
```
cd /Users/abhayp/Downloads/Projects/AI_tracker-antigravity/AIUsageDashboard
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
```

## Files you own (touch NOTHING else)
- `AIUsageDashboard/AIUsageDashboardApp/UI/*`
- `AIUsageDashboard/AIUsageDashboardApp/App/*`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel.swift`

Do NOT touch: `Core/Parsing/*`, `Core/Providers/*`, `Core/Storage/*`, `Core/Sync/SyncEngine.swift`, `Core/Models/*`, `Tests/*`, `project.yml`, `AIUsageDashboardWidgets/*` (widget target DEFERRED post-MVP — do not add it).
Code against the CURRENT `SyncEngine` API only: `refreshAll() async -> [ProviderSnapshot]`. Auto-refresh streams get wired at integration, not by you.

## Design system — Padzy OS (STRICT, non-negotiable)
Theme "aitracker" (see `AIUsageDashboard/docs/07-padzy-theme.md`):
- ground `#131316`, surface `#1D1D22`, ink `#ECECF1`, muted `#6E6E78`, accent `#FF3B70` (signal pink).
- Define as a Swift `PadzyTheme` enum/struct of `Color`s in UI/ (use a `Color(hex:)` extension — not an Apple API, ship it yourself). App presents dark-editorial in both system modes for MVP.

Five invariants, every view:
1. **Mono data, always**: every number, timestamp, token count, ID uses mono. Use DM Mono via `Font.custom` ONLY if the font is installed; otherwise `.monospaced` system font (SF Mono). Never render a metric in the UI sans.
2. **Numbered editorial kickers**: section labels as two-digit uppercase mono, e.g. `01 / PROVIDERS`, `02 / USAGE`, 12–13pt, tracking 0.04em, muted.
3. **Exposed hairline structure**: 1px rules (`Rectangle().fill(muted.opacity(...)).frame(height: 1/displayScale)`) dividing labeled regions. NO rounded card grids, NO shadows, NO `.regularMaterial`/glass/vibrancy — flat fills only. Radius 0–4px max.
4. **Accent tick**: active/selected/syncing state = square 2px accent bar on leading or bottom edge (e.g. selected provider row, sync-in-progress indicator).
5. **One accent, ruthless restraint**: `#FF3B70` only for active state, sync progress, focus, or the single primary action. Everything else ink/muted. Replace the current multi-color ConfidenceBadge palette: badges use ink/muted outline chips; do NOT introduce green/blue/purple/orange.

Headings: PP Neue Machina via `Font.custom` if installed, else SF Pro Display heavy weights; ALL CAPS display labels; hard left alignment; strong size contrast (big headline, small body — no fat middle). Spacing on 8px scale. Dashboard = Functional tier; menu bar panel + data rows = Dense tier.

macOS platform contract (preserve, never override): title bar/traffic lights, resizable window with sane minimums, `Settings` scene at ⌘,, MenuBarExtra behavior, keyboard shortcuts (⌘R refresh, ⌘W, ⌘Q), hover affordances on rows, VoiceOver labels, contrast ≥4.5:1 body / ≥3:1 large+non-text (verify pink-on-dark and muted-on-ground), Reduce Motion honored.

## Functional goals
1. **Shared state**: ONE `DashboardViewModel` instance for the whole app (create in `App` struct, inject via `.environmentObject`). Currently dashboard + menu bar each make their own — fix that. Rewrite the view model as needed (it stays `@MainActor ObservableObject` calling `syncEngine.refreshAll()`; remove the pointless `do {}`; add `lastSyncedAt`, per-provider accessors, a `claudeSnapshot` convenience).
2. **Dashboard** (`Window` scene with id, not `WindowGroup`): 
   - Kicker `01 / PROVIDERS`: provider rows — Claude Code first with real data; Codex/Cursor/Cline/Antigravity visibly present but flat "UNAVAILABLE" state in muted (no accent).
   - Claude detail region `02 / USAGE`: Today / 7D / 30D / Lifetime token totals (input, output, cache read, cache write + total), all mono, compact formatting (`1.12B`, `48.3M`). Label windows honestly: "7D" and "30D" are rolling windows.
   - Confidence label ("LOCAL PARSED" etc.) as mono chip per metric block.
   - Sync status: last-synced timestamp (mono), refresh button (⌘R), accent tick animating ONLY while syncing (respect Reduce Motion).
3. **Menu bar**: `MenuBarExtra` label shows compact today total (e.g. `⌾ 48.3M`) — live via the shared view model. Panel (`.window` style, Dense tier): Claude today/7D rows mono, sync status line, "Open Dashboard" (must actually open/focus the dashboard window via `openWindow`), "Quit".
4. **Settings** (⌘,): keep minimal — General tab with refresh-interval placeholder + About. Padzy-styled, no fake controls.
5. **Empty/error states**: no `~/.claude` dir → honest empty state with instruction line; parser warnings surfaced in a muted warnings region.
6. Number formatter: shared compact token formatter (K/M/B, one decimal), mono everywhere.

## Rules
- No architecture changes; no new dependencies; no new targets; no asset catalogs beyond colors if needed.
- Build AND tests must pass (commands above); paste summaries.
- If a Padzy rule and a macOS convention conflict, macOS interaction/accessibility wins, Padzy visual language wins on decoration.

## Report back (in your final message + `tasks/reports/antigravity-report.md` on your branch)
- Changed files; what works; what is stubbed; tests/build run + results; known risks; screenshot if possible.
