# RELAY LEG 1 — Codex: real CodexProvider

Read `tasks/relay/BATON.md` first — standing rules, build commands, frozen contracts.
Branch: `relay/01-codex`.

## Mission
Replace the `CodexProvider` skeleton with a real adapter over local Codex CLI
session logs. This is the first provider with REAL QUOTA DATA — it lights up
Tokei's quota model end-to-end.

## Files you own
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/CodexProvider.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/Codex*` (new)
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/UsageWindows.swift` (new, see Refactor)
- `AIUsageDashboard/AIUsageDashboardApp/Core/Utilities/FileWatcher.swift` (ONLY the default-paths change below)
- `AIUsageDashboard/Tests/ParserTests/Codex*` (new), `Tests/Fixtures/Fixtures.swift` (append only)
Nothing else. No UI. No Models edits except none should be needed.

## Ground truth (verified on this machine 2026-07-06)
Logs: `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl` (38 files
present). `~/.codex/auth.json` exists. Relevant lines are `token_count` events:

```json
{"timestamp":"2026-07-06T02:53:16.504Z","type":"event_msg","payload":{"type":"token_count",
 "info":{"total_token_usage":{"input_tokens":17772,"cached_input_tokens":4992,"output_tokens":600,"reasoning_output_tokens":516,"total_tokens":18372},
         "last_token_usage":{"input_tokens":17772,"cached_input_tokens":4992,"output_tokens":600,"reasoning_output_tokens":516,"total_tokens":18372},
         "model_context_window":258400},
 "rate_limits":{"limit_id":"codex","primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1783324383},
                "secondary":{"used_percent":29.0,"window_minutes":10080,"resets_at":1783457462},
                "credits":null,"plan_type":"plus","rate_limit_reached_type":null}}}
```
Notes: `total_token_usage` is cumulative within the session; `last_token_usage`
is the latest turn's delta. `resets_at` is epoch seconds. `window_minutes` 300 =
5h session window, 10080 = weekly. Other line types exist — skip anything that
is not a `token_count` payload. Some fields can be null — parse defensively.

## Spec
1. **Token usage**: stream files (reuse `URL.lines` pattern from the Claude
   parser). Sum `last_token_usage` deltas, bucketed by event `timestamp`
   (fractional-second ISO8601 — reuse the cached-formatter approach) into
   today / rolling 7d / rolling month / lifetime, plus `dailyTotals` per
   calendar day (feed `ProviderSnapshot.dailyTotals` — sparklines depend on it).
   Map `reasoning_output_tokens` → `TokenUsage.reasoningTokens`,
   `cached_input_tokens` → `cacheReadTokens`. Confidence: `.localParsed`.
   Cross-check in a real-logs smoke test (pattern: `RealLogsSmokeTests`, skip
   when `~/.codex` absent): sum-of-deltas vs sum of each session's final
   `total_token_usage`; print both; assert within 5%.
2. **Quota windows** — the star of this leg: take the `rate_limits` from the
   most recent event across all sessions (by timestamp).
   - primary → `QuotaWindow(type: .session, used: used_percent, limit: 100, remaining: 100-used, resetAt: Date(epoch), confidence: .providerReported, source: "Codex CLI rate_limits (5h window)")`
   - secondary → same with `.weekly`.
   - Include `plan_type` in the source string (e.g. "plus plan").
   If the newest event is older than 24h, keep the windows but degrade
   confidence to `.estimated` (stale).
3. **Availability/auth**: `~/.codex` exists → `.installed`; `auth.json`
   present → `.authenticated` (do NOT read token contents, presence only).
4. **Refactor (small, no behavior change)**: extract the window-bucketing logic
   (todayStart/weekStart/monthStart computation + accumulate) into
   `Core/Parsing/UsageWindows.swift` and use it from BOTH `ClaudeJSONLParser`
   and your Codex aggregator. All existing Claude parser tests must still pass
   unchanged — they are the regression net for this refactor.
5. **Watcher**: change `FileWatcher` default watch paths to
   `[~/.claude/projects, ~/.codex/sessions]` (FSEventStream accepts multiple
   paths; keep the single debounce). Touch nothing else in that file.
6. **Tests**: fixtures as string literals — token_count lines (fractional
   timestamps), non-token_count lines skipped, null rate_limit fields, delta
   summing across events, dailyTotals bucketing, quota mapping incl. stale
   degradation (injectable now), malformed lines.

## Definition of done
Build green; ALL tests green (existing 27 + yours); real-logs smoke prints
plausible totals AND live quota percentages on this machine; merged to main
--no-ff; report + BATON handover entry written.

## Handover
Append your entry to `tasks/relay/BATON.md`, then end with exactly:
"Leg 1 complete. Next: run Cursor with tasks/relay/02-cursor.md".
