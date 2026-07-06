# RELAY LEG 2 — Cursor: ClineProvider (tokens + REAL COST) + Cursor detection

Read `tasks/relay/BATON.md` first — standing rules, build commands, frozen
contracts. Read the Leg 1 handover entry. Branch: `relay/02-cursor`.

## Mission
Real ClineProvider from local Cline CLI data — first provider with real dollar
cost. Plus honest availability detection for the Cursor app (metrics stay
unavailable this leg).

## Files you own
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/ClineProvider.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Providers/CursorProvider.swift` (detection only)
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/Cline*` (new)
- `AIUsageDashboard/AIUsageDashboardApp/Core/Utilities/FileWatcher.swift` (ONLY append `~/.cline/data/sessions` to default paths)
- `AIUsageDashboard/Tests/ParserTests/Cline*` (new), `Tests/Fixtures/Fixtures.swift` (append only)
Nothing else. No UI. Reuse `UsageWindows` helper from Leg 1 — do not fork the
window logic.

## Ground truth (verified on this machine 2026-07-06)
`~/.cline/data/sessions/<sessionId>/<sessionId>.messages.json` (13 sessions).
Top-level: `{version, updated_at, agent, sessionId, messages, system_prompt}`.
Assistant messages carry:

```json
{"id":"msg_N-XXz57J","role":"assistant","ts":...,
 "modelInfo":{"id":"cline-pass/kimi-k2.7-code","provider":"cline-pass","family":"kimi-k2"},
 "metrics":{"inputTokens":6520,"outputTokens":189,"cacheReadTokens":0,"cacheWriteTokens":0,"cost":0.00695}}
```
`ts` = epoch (verify millis vs seconds against the sessionId prefix, e.g.
`1783325327533_...` is epoch millis). `cost` = real dollars. sessionId dirs are
the source of truth; there is also a `db/` dir — IGNORE it (no SQLite this leg).

## Spec
1. **ClineProvider**: enumerate session dirs, decode each messages.json
   (Codable structs, tolerant: metrics/modelInfo/ts optional; skip messages
   without metrics; malformed file → per-file ProviderWarning, keep going).
   Dedupe by message `id` across files. Aggregate via `UsageWindows`:
   today/7d/month/lifetime `TokenUsage` (cacheWriteTokens → cacheCreationTokens,
   confidence `.localParsed`) + `dailyTotals`.
   **Cost**: sum `metrics.cost` into `CostUsage` (inspect the existing model in
   `Core/Models/CostUsage.swift` and fill what it supports; confidence
   `.localParsed`; if the model has period fields, fill today/month/lifetime).
2. **Availability/auth**: `~/.cline` exists → `.installed`. Auth: `.unknown`
   (credits/subscription need the cline.bot API — post-relay, do NOT attempt).
3. **CursorProvider**: availability only — `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
   exists → `.installed`, else `.notInstalled`. Snapshot stays unavailable with
   one info warning "Cursor metrics require dashboard auth (post-MVP)". Do not
   open the SQLite file.
4. **Watcher**: append `~/.cline/data/sessions` to FileWatcher default paths.
5. **Tests**: fixtures as string literals — happy path aggregation + cost
   summing, ts millis handling, dedupe by id, message without metrics skipped,
   malformed JSON warning, dailyTotals bucketing. Real-logs smoke test pattern
   (skip when `~/.cline` absent) printing totals + total cost.

## Definition of done
Build green; ALL tests green (Leg 1's included); smoke prints plausible Cline
totals AND a real dollar figure on this machine; merged to main --no-ff;
report `tasks/reports/relay-cursor.md` + BATON handover entry.

## Handover
End with exactly:
"Leg 2 complete. Next: run Antigravity with tasks/relay/03-antigravity.md".
