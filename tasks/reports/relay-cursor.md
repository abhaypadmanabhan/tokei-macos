# Relay Leg 2 - Cursor

## Changed files
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/ClineMessagesParser.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/ClineProvider.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/CursorProvider.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Utilities/FileWatcher.swift`
- `AIUsageDashboard/Tests/Fixtures/Fixtures.swift`
- `AIUsageDashboard/Tests/ParserTests/ClineMessagesParserTests.swift`
- `AIUsageDashboard/Tests/ParserTests/ClineProviderTests.swift`
- `AIUsageDashboard/Tests/ParserTests/ClineRealLogsSmokeTests.swift`
- `AIUsageDashboard/Tests/ParserTests/CursorProviderTests.swift`

## What works
- `ClineProvider` detects `~/.cline`, returns auth `.unknown`, discovers `data/sessions/<id>/<id>.messages.json`, and returns local parsed token snapshots with daily totals plus lifetime dollar cost in `CostUsage`.
- `ClineMessagesParser` decodes assistant message metrics, dedupes by message `id`, maps `cacheWriteTokens` to `cacheCreationTokens`, buckets via shared `UsageWindows`, and sums `metrics.cost`.
- `CursorProvider` detects install via `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` presence only; metrics stay unavailable with post-MVP info warning. SQLite is not opened.
- `FileWatcher` defaults now also watch `~/.cline/data/sessions`.

## Stubbed or skipped
- Cline credits quota window remains unavailable; no cline.bot API auth.
- Cursor token/cost metrics deferred to post-MVP dashboard auth.
- `~/.cline/db/` SQLite ignored by design.

## Tests run
- `xcodegen generate`
- `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build` — succeeded.
- `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test` — 47 tests passed, 0 failures.
- Cline real-log smoke: 13 files, lifetime 131,011,355 tokens, total cost $22.74, 0 warnings.

## Risks
- Cline `ts` uses millis heuristic (`> 1e12`); sessionId prefix is fallback when `ts` is absent.
- `CostUsage` is lifetime-only (no today/month cost fields on the model).
- Cross-session message ID reuse would under-count; not observed on this machine.
