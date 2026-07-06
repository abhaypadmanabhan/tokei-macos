# Agent: Cursor — Package B: Claude Parser Hardening

Worktree: `/Users/abhayp/Downloads/Projects/AI_tracker-cursor` (branch `agent/cursor-parser`).
Work ONLY there. Commit to that branch.

## Setup / build / test
```
cd /Users/abhayp/Downloads/Projects/AI_tracker-cursor/AIUsageDashboard
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
```

## Files you own (touch NOTHING else)
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/*`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/ClaudeCodeProvider.swift`
- `AIUsageDashboard/Tests/ParserTests/*`
- `AIUsageDashboard/Tests/Fixtures/*` (new; fixtures = Swift string literals in a `Fixtures.swift`, NOT resource files — avoids project.yml changes)

Do NOT touch: `Core/Models/*` (frozen; you may add fields to `ClaudeUsageRecord` — it lives in Parsing/), `Core/Storage/*`, `Core/Sync/*`, `UI/*`, `App/*`, `project.yml`. Do not change the `UsageProvider` protocol or `ClaudeJSONLParser.parse(logSources:) -> AggregateUsage` signature/return shape.

## The problem (verified against real logs on this machine)
Current parser is written against a FICTIONAL schema. Real Claude Code JSONL (`~/.claude/projects/<project>/<session-uuid>.jsonl`) assistant lines look like:

```json
{"parentUuid":"…","isSidechain":false,"userType":"external","cwd":"/path","sessionId":"8f83c022-…","version":"2.1.201","gitBranch":"HEAD",
 "message":{"model":"claude-fable-5","id":"msg_01Tmq…","type":"message","role":"assistant","content":[…],"stop_reason":"tool_use",
   "usage":{"input_tokens":4,"cache_creation_input_tokens":24924,"cache_read_input_tokens":14085,"output_tokens":250,"service_tier":"standard"}},
 "requestId":"req_011Cck…","type":"assistant","uuid":"79741816-…","timestamp":"2026-07-06T07:55:59.226Z"}
```
Other line types: `"type":"user"` (no usage), `"type":"summary"` ({"type":"summary","summary":"…","leafUuid":"…"}), progress/system lines. Skip lines without `message.usage`.

Confirmed bugs (measured on 278 real files / 46,083 lines):
1. **Timestamp**: real timestamps have fractional seconds (`2026-07-06T07:55:59.226Z`). Default `ISO8601DateFormatter` returns nil → today/week/month totals are ALWAYS ZERO. Fix: formatter with `[.withInternetDateTime, .withFractionalSeconds]`, fall back to non-fractional, keep epoch-number fallback. Cache formatters statically (46k+ lines; don't allocate per line).
2. **Dedupe broken → 2.34x overcount**: parser looks for top-level `message_id`/`id`/`request_id` — none exist. Real IDs: `message.id` and `requestId` (camelCase). One API response with multiple content blocks = multiple lines with SAME `message.id` and same usage. Measured: 16,856 usage lines → 7,132 unique messages; naive sum 2.63B tokens vs correct 1.12B. Fix dedupe key: `message.id` ?? `requestId` ?? top-level `uuid`; keep first occurrence; dedupe set spans ALL files (already does). Never synthesize keys from record count.
3. Remove the `usage ?? json` top-level fallback (counts garbage lines as zero-records). Accept `json["message"]["usage"]`; keep top-level `json["usage"]` tolerance for old/edge formats only if a `*_tokens` key is actually present.
4. Count sidechain lines (`isSidechain:true`) — they are real token spend by subagents. Add a test proving it.
5. Malformed lines: skip silently per line, but count them; emit one `ProviderWarning` per file if >0 malformed. Zero-token valid lines are not malformed.

## Also
- Aggregate on the fly per record instead of accumulating all records in an array (memory-bounded; `URL.lines` streaming already in place).
- Make "now" injectable in the parser (init param, default `Date()`) so window tests are deterministic.
- Window semantics stay: today = start of day; week = rolling last 7 days; month = rolling last month; lifetime = all.
- `ClaudeCodeProvider.fetchSnapshot` currently swallows discovery/parse errors with `try?` — surface as warnings instead.
- Rewrite tests against the REAL schema (fixtures above). Keep/extend: dedupe across files, fractional + non-fractional + epoch timestamps, missing usage lines, malformed lines, sidechain counting, window bucketing with injected now. Sanity-check by running the app parser against your own `~/.claude/projects` if present.

## Rules
- No architecture changes. No new dependencies. Swift strict concurrency stays `complete` in Core — keep everything Sendable/actor-safe.
- All tests must pass before you finish: run the test command above and paste the summary.

## Report back (in your final message + `tasks/reports/cursor-report.md` on your branch)
- Changed files; what works; what is stubbed; tests run + results; known risks.
