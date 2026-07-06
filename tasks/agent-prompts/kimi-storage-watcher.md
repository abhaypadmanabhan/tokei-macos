# Agent: Kimi K2.7 — Package A: Persistence + File Watching

Worktree: `/Users/abhayp/Downloads/Projects/AI_tracker-kimi` (branch `agent/kimi-storage-watcher`).
Work ONLY there. Commit to that branch.

## Setup / build / test
```
cd /Users/abhayp/Downloads/Projects/AI_tracker-kimi/AIUsageDashboard
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
```

## Files you own (touch NOTHING else)
- `AIUsageDashboard/AIUsageDashboardApp/Core/Storage/*`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/SyncEngine.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Utilities/FileWatcher*.swift` (new)
- `AIUsageDashboard/Tests/StorageTests/*` (new)
- You may ADD new model files under `Core/Models/` (e.g. `DailyUsage.swift`) but MUST NOT edit existing model files.

Do NOT touch: `Core/Sync/DashboardViewModel.swift` (owned by another agent), `Core/Parsing/*`, `Core/Providers/*`, `UI/*`, `App/*`, `project.yml`, existing `Core/Models/*` files, existing test files.

## Architecture decision (final, do not revisit)
MVP persistence = **JSON file store, NOT SwiftData**. Delete the `SwiftDataSchema.swift` and `StorageModel.swift` placeholders. Core has `SWIFT_STRICT_CONCURRENCY: complete`; a Codable + actor store is the simple, testable fit.

## Goals
1. **Persistent UsageStore.** Keep type name `UsageStore` (actor) and existing API (`save(snapshot:)`, `save(snapshots:)`, `snapshot(providerID:)`, `allSnapshots()`) so other branches compile unchanged. Add disk persistence:
   - Location: `~/Library/Application Support/AIUsageDashboard/usage-store.json` (injectable directory for tests; create dir if missing).
   - Persist provider snapshots (make needed models `Codable` — if existing frozen models lack Codable, add conformance via `extension` in a NEW file under Storage/, don't edit model files).
   - Load from disk on first access; atomic writes; corrupt/missing file → start empty, don't crash.
2. **Daily history rollups.** New `DailyUsage` model (date day-key, providerID, TokenUsage totals). On each save, upsert today's rollup per provider from its lifetime/today usage. API: `dailyHistory(providerID:) -> [DailyUsage]`. Purpose: Claude logs rotate (~30 days) — history must outlive raw logs.
3. **File watcher.** `FileWatcher` (FSEventStream wrapper or DispatchSource-based) in Core/Utilities:
   - Watch `~/.claude/projects` recursively.
   - Debounce 2s (coalesce bursts).
   - Callback-based / AsyncStream API; must be actor-safe under strict concurrency; stop cleanly.
4. **Auto-sync wiring in SyncEngine.** Keep `refreshAll() async -> [ProviderSnapshot]` exactly as is. Add:
   - `startAutoSync()` — starts watcher; on debounced change runs `refreshAll()`.
   - `stopAutoSync()`.
   - `updates: AsyncStream<[ProviderSnapshot]>` emitting after every refresh (manual or auto). Integration will wire UI to this later — you do NOT touch the view model.
5. **Tests** (`Tests/StorageTests/`, auto-picked-up by xcodegen — just re-run `xcodegen generate`): store round-trip, corrupt-file recovery, daily rollup upsert, watcher debounce (temp dir, write files, assert single callback). Skip flaky timing-sensitive assertions if unreliable — note them instead.

## Rules
- No architecture changes beyond the above. No new dependencies. No SwiftData.
- Strict concurrency `complete` must still compile warning-free in Core.
- All tests (existing 8 + yours) must pass: run the test command and paste the summary.

## Report back (in your final message + `tasks/reports/kimi-report.md` on your branch)
- Changed files; what works; what is stubbed; tests run + results; known risks.
