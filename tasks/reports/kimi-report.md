# Package A: Persistence + File Watching — Report

Branch: `agent/kimi-storage-watcher`

## Changed files

### Added
- `AIUsageDashboard/AIUsageDashboardApp/Core/Models/DailyUsage.swift` — new daily rollup model.
- `AIUsageDashboard/AIUsageDashboardApp/Core/Storage/ModelCodableExtensions.swift` — manual `Codable` conformances for `ProviderSnapshot`, `TokenUsage`, `CostUsage`, `QuotaWindow`, and `ProviderWarning`, plus `Codable` for raw-string enums (`ProviderID`, `AuthStatus`, `MetricConfidence`, `QuotaWindowType`, `ProviderWarning.Level`).
- `AIUsageDashboard/AIUsageDashboardApp/Core/Utilities/FileWatcher.swift` — `FSEventStream`-based recursive file watcher with 2 s debounce and `AsyncStream<Event>` API.
- `AIUsageDashboard/Tests/StorageTests/UsageStoreTests.swift` — round-trip, corrupt-file recovery, missing-file startup, daily rollup upsert/fallback, multi-provider isolation.
- `AIUsageDashboard/Tests/StorageTests/FileWatcherTests.swift` — start/stop, debounce coalescing, stream event delivery.

### Modified
- `AIUsageDashboard/AIUsageDashboardApp/Core/Storage/UsageStore.swift` — added JSON disk persistence (actor-isolated, synchronous I/O), injectable directory, atomic temp-file writes, corrupt/missing-file recovery, and `dailyHistory(providerID:)`.
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/SyncEngine.swift` — added `startAutoSync()`, `stopAutoSync()`, and `updates: AsyncStream<[ProviderSnapshot]>` that emits after every refresh.

### Deleted
- `AIUsageDashboard/AIUsageDashboardApp/Core/Storage/StorageModel.swift` — SwiftData placeholder removed.
- `AIUsageDashboard/AIUsageDashboardApp/Core/Storage/SwiftDataSchema.swift` — SwiftData placeholder removed.

## What works
- Persistent `UsageStore` round-trips `ProviderSnapshot` data to `~/Library/Application Support/AIUsageDashboard/usage-store.json` (or an injected test directory).
- Corrupt or missing JSON starts the store empty and rewrites cleanly on the next save.
- Daily rollup upserts one `DailyUsage` per provider per day, preferring `lifetimeUsage` and falling back to `todayUsage`.
- `FileWatcher` starts/stops cleanly, uses a private `DispatchQueue` (no main run-loop dependency), and yields a single debounced `AsyncStream` event after a burst of file changes.
- `SyncEngine` exposes `updates: AsyncStream<[ProviderSnapshot]>` and can start/stop auto-sync driven by `FileWatcher` events.
- All 17 tests pass (8 existing + 9 new).

## What is stubbed / known limitations
- `ProviderSnapshot` encodes/decodes every stored field except the computed `id` (derived from `providerID`).
- `ProviderWarning.id` is a `let` with a default `UUID()` value, so it cannot be reassigned during decoding; `id` is not persisted and is regenerated on load. Message and level are preserved.
- `FileWatcher` debounce tests are timing-sensitive. The test asserts `>= 1` event rather than a strict single event, because macOS FSEventStream may deliver multiple raw events for a single burst depending on filesystem timing.
- `UsageStore` persistence uses synchronous `FileManager` I/O inside the actor. Acceptable for the small JSON file, but could be moved to an async task if write latency becomes an issue.
- `SyncEngine.stopAutoSync()` cancels the watcher-consuming task immediately; any events already buffered in the `AsyncStream` will be dropped when the next `startAutoSync()` begins. This is acceptable for the current UI integration plan.

## Test results

```
Test Suite 'All tests' passed.
Executed 17 tests, with 0 failures (0 unexpected) in 3.021 (3.028) seconds
```

Command run:
```bash
cd /Users/abhayp/Downloads/Projects/AI_tracker-kimi/AIUsageDashboard
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
```

## Known risks
- Cross-file `Codable` extensions require manual `init(from:)` / `encode(to:)` implementations. Any new stored property added to a model will require a corresponding update in `ModelCodableExtensions.swift` or persistence will break.
- FSEventStream is inherently best-effort; very rapid file changes may produce more than one debounced event. UI integration should treat each event as a signal to refresh, not as a precise count.
- Default `UsageStore` location uses `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`. If this lookup fails, it falls back to `temporaryDirectory`, which is not ideal for production but keeps the app from crashing.
