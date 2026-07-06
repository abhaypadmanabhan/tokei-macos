# Implementation Roadmap

## Phase 0: Scaffold (Done)
- Repository structure.
- Documentation set.
- Core model definitions.
- Provider protocols and skeletons.
- Claude JSONL parser skeleton.
- Storage, sync, UI, and widget skeletons.
- Tests and fixtures.

## Phase 1: Core Infrastructure
1. Implement SwiftData persistence layer with entities for `ProviderSnapshot`, `QuotaWindow`, `TokenUsage`, and `CostUsage`.
2. Implement `UsageStore` with read/write/query operations.
3. Implement App Group container sharing for widgets.
4. Implement `SyncEngine` with basic refresh scheduling and error aggregation.
5. Implement FSEvents-based file watcher for Claude log directories.
6. Implement notification threshold engine.
7. Implement Keychain credential storage wrapper.

## Phase 2: Providers
1. **Claude Code:**
   - Implement `ClaudeJSONLParser` with streaming and deduplication.
   - Implement log directory discovery and session detection.
   - Compute daily/weekly/monthly/lifetime token totals.
   - Split input/output/cache tokens.
2. **OpenAI Codex:**
   - Detect local config/logs.
   - Implement adapter skeleton with `unavailable` metrics.
3. **Cursor:**
   - Detect local `state.vscdb` and extract auth token if available.
   - Implement monthly-budget quota model.
4. **Cline:**
   - Implement provider skeleton and credits window.
5. **Antigravity:**
   - Keep provider skeleton; document research TODOs.

## Phase 3: UI & Experience
1. Implement dashboard layout with provider cards.
2. Implement provider detail pages.
3. Implement confidence badges and tooltips.
4. Implement menu bar extra with quick summary.
5. Implement settings view.
6. Implement WidgetKit widgets reading shared storage.
7. Add app icons and visual polish.

## Phase 4: Integration & Polish
1. Wire SyncEngine to View Models.
2. Add background refresh via `BGTaskScheduler` or `Timer` based on macOS version.
3. Add keyboard shortcuts and menu items.
4. Add error handling and user-facing warnings.
5. Add debug/dev raw response viewer.
6. Run full test suite and fix regressions.

## Phase 5: Future Work
- Provider endpoint adapters for Codex and Cursor.
- OAuth/web dashboard integration for Cline.
- Per-model quota for Antigravity.
- Browser extension or global shortcut capture.
- Export/reporting features.
