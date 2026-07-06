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
1. Implement SwiftData persistence layer with entities for `ProviderSnapshot`, `QuotaWindow`, `TokenUsage`, and `CostUsage`. (Deferred: using JSON persistence via `UsageStore` for MVP.)
2. Implement `UsageStore` with read/write/query operations. (Done)
3. Implement App Group container sharing for widgets. (Post-MVP)
4. Implement `SyncEngine` with basic refresh scheduling and error aggregation. (Done)
5. Implement FSEvents-based file watcher for provider log directories. (Done)
6. Implement notification threshold engine. (Done — 80%/95% thresholds, no-spam re-arm, UserDefaults state, Settings toggle.)
7. Implement Keychain credential storage wrapper. (Done)

## Phase 2: Providers
1. **Claude Code:**
   - Implement `ClaudeJSONLParser` with streaming and deduplication. (Done)
   - Implement log directory discovery and session detection. (Done)
   - Compute daily/weekly/monthly/lifetime token totals. (Done)
   - Split input/output/cache tokens. (Done)
2. **OpenAI Codex:**
   - Detect local config/logs. (Done)
   - Implement adapter reading `~/.codex/sessions/**/*.jsonl` with real token windows and quota windows. (Done)
3. **Cursor:**
   - Detect local `state.vscdb`. (Done)
   - Implement monthly-budget quota model. (Post-MVP)
4. **Cline:**
   - Implement adapter reading `~/.cline/data/sessions/**` with lifetime tokens and cost. (Done)
   - OAuth/web dashboard integration for credits/quota. (Post-MVP)
5. **Antigravity:**
   - Keep provider skeleton; document research TODOs. (Post-MVP)

## Phase 3: UI & Experience
1. Implement dashboard layout with provider cards. (Done)
2. Implement provider detail pages. (Done)
3. Implement confidence badges and tooltips. (Done)
4. Implement menu bar extra with quick summary. (Done)
5. Implement settings view with quota alerts toggle. (Done)
6. Implement WidgetKit widgets reading shared storage. (Post-MVP)
7. Add app icons and visual polish. (Post-MVP)

## Phase 4: Integration & Polish
1. Wire SyncEngine to View Models. (Done)
2. Add background refresh via `BGTaskScheduler` or `Timer` based on macOS version. (Post-MVP)
3. Add keyboard shortcuts and menu items. (Done — ⌘R manual refresh, ↑/↓ sidebar selection.)
4. Add error handling and user-facing warnings. (Done)
5. Add debug/dev raw response viewer. (Post-MVP)
6. Run full test suite and fix regressions. (Done)

## Phase 5: Future Work
- Provider endpoint adapters for Codex and Cursor.
- OAuth/web dashboard integration for Cline.
- Per-model quota for Antigravity.
- Browser extension or global shortcut capture.
- Export/reporting features.
