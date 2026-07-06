# Cursor Parser Hardening Report

Branch: `agent/cursor-parser`  
Worktree: `/Users/abhayp/Downloads/Projects/AI_tracker-cursor`

## Changed Files

| File | Summary |
|------|---------|
| `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/ClaudeUsageRecord.swift` | Added `uuid`, `dedupeKey`, `toTokenUsage()` |
| `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/ClaudeJSONLParser.swift` | Injectable `now`, on-the-fly aggregation, global dedupe, malformed-line warnings |
| `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/ClaudeJSONLParser+Streaming.swift` | Real schema parsing, `LineParseOutcome`, static ISO8601 formatters |
| `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/ClaudeCodeProvider.swift` | Discovery errors surfaced as warnings; parser warnings merged |
| `AIUsageDashboard/Tests/Fixtures/Fixtures.swift` | **New** — real-schema string literal fixtures |
| `AIUsageDashboard/Tests/ParserTests/ClaudeJSONLParserTests.swift` | Rewritten/extended (12 tests) |

## What Works

1. **Timestamp parsing** — Cached fractional + standard ISO8601 formatters; epoch fallback. Fractional timestamps like `2026-07-06T07:55:59.226Z` now bucket into today/week/month correctly.
2. **Dedupe** — Key is `message.id` → `requestId` → `uuid`; first occurrence wins across all files. No synthetic `file:count` keys.
3. **Usage extraction** — Primary path `message.usage`; top-level `usage` only when `*_tokens` keys present. Lines without usage (user/summary/progress) skipped silently.
4. **Sidechain** — `isSidechain: true` lines with usage are counted (no filter).
5. **Malformed lines** — Invalid JSON counted per file; one `ProviderWarning` per file when count > 0.
6. **Memory** — Records aggregated on the fly; no `[ClaudeUsageRecord]` accumulation.
7. **Injectable now** — `ClaudeJSONLParser(calendar:now:)` for deterministic window tests.
8. **Provider warnings** — `discoverLogSources()` propagates errors; `fetchSnapshot` merges discovery + parse warnings.

## What Is Stubbed / Unchanged

- `reasoningTokens` — not present in Claude logs; always 0.
- `service_tier` — parsed in logs but not stored or surfaced.
- Quota windows remain `.unavailable` (by design).
- `UsageProvider` protocol and `parse(logSources:) -> AggregateUsage` signature unchanged.

## Tests Run

```bash
cd AIUsageDashboard
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore \
  -destination 'platform=macOS' test
```

**Result: TEST SUCCEEDED** (17 tests total; 12 parser tests)

Parser tests: `testEmptyLogSources`, `testRealSchemaAggregation`, `testDeduplicationByMessageId`, `testDeduplicationAcrossFiles`, `testFractionalTimestamp`, `testEpochTimestamp`, `testNonFractionalTimestamp`, `testSkipsLinesWithoutUsage`, `testSidechainCounted`, `testMalformedLinesWarning`, `testWindowBucketing`, `testLegacyTopLevelUsage`

## Real Log Sanity Check

`~/.claude/projects` present (681 `.jsonl` files). Sample of 50 files:

- 2,377 usage lines → 1,012 unique dedupe keys (ratio **2.35×**, matching pre-fix overcount)
- All sampled usage lines use fractional ISO8601 timestamps
- Schema matches fixtures (`message.usage`, `requestId`, `message.id`)

## Known Risks

- Usage lines with **no** `message.id`, `requestId`, or `uuid` are counted on every occurrence (no dedupe possible; per spec).
- `discoverLogSources` now throws if `~/.claude/projects` is unreadable (surfaced as warning, empty snapshot).
- Legacy snake_case IDs (`message_id`, `request_id`) still accepted for backward compatibility.
- `Tests/Fixtures/sample_claude.jsonl` superseded by `Fixtures.swift` but left in place.
