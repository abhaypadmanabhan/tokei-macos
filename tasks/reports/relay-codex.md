# Relay Leg 1 - Codex

## Changed files
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/CodexProvider.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/CodexJSONLParser.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/UsageWindows.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/ClaudeJSONLParser.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/ClaudeJSONLParser+Streaming.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Utilities/FileWatcher.swift`
- `AIUsageDashboard/Tests/Fixtures/Fixtures.swift`
- `AIUsageDashboard/Tests/ParserTests/CodexJSONLParserTests.swift`
- `AIUsageDashboard/Tests/ParserTests/CodexProviderTests.swift`
- `AIUsageDashboard/Tests/ParserTests/CodexRealLogsSmokeTests.swift`

## What works
- `CodexProvider` now detects `~/.codex`, treats `auth.json` presence as authenticated, discovers recursive `~/.codex/sessions/**/*.jsonl` logs, and returns local parsed token snapshots with daily totals.
- `CodexJSONLParser` streams JSONL via `URL.lines`, skips non-`token_count` events, sums `last_token_usage` deltas, buckets today / 7d / month / lifetime, and maps latest Codex CLI `rate_limits` into session and weekly `QuotaWindow`s.
- Quota windows use provider-reported confidence when the newest event is fresh and degrade to estimated after 24h.
- Claude and Codex share `UsageWindows` for range bucketing; existing Claude parser tests stayed green.
- `FileWatcher` defaults now watch both `~/.claude/projects` and `~/.codex/sessions` with the same debounce path.

## Stubbed or skipped
- No stubs remain in `CodexProvider`.
- Cost usage is still `nil`; this leg only covers Codex tokens and quota windows.
- Auth validation is intentionally presence-only and does not read token contents.

## Tests run
- `xcodegen generate`
- `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build` - succeeded.
- `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test` - 37 tests passed, 0 failures.
- Codex real-log smoke: 39 files, delta total 139,497,475, final session total 138,915,496, difference about 0.42%; session quota 18%, weekly quota 36%; 1 malformed-line warning skipped.
- `git diff --check` - clean.

## Risks
- One real Codex JSONL line on this machine is malformed or unsupported and is skipped with a warning.
- Codex input/output counts are normalized by separating cached input and reasoning output so `TokenUsage.totalTokens` matches Codex `total_tokens`; raw detail totals are still exposed through cache and reasoning fields.
