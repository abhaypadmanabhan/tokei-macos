# Codex parser incremental cache (mirror Claude fix)

## Context
Claude parser CPU fix (already done, uncommitted, verified):
`ClaudeJSONLParser` now caches per-file aggregates keyed by path, skips
unchanged files (mtime+size match), resumes grown files from last byte
offset via FileHandle. 306/306 tests pass. Remaining CPU hog: Codex
provider still does full re-parse of ~93MB logs every sync (~11% CPU
per earlier sample).

## Why Codex is harder than Claude
Codex's parser isn't a flat token-sum — it tracks 3 things per record
beyond windows/dailyTotals/hourlyTotals:
- `deltaReportedTotalTokens` — running sum, easy to cache additively.
- `finalTotalsBySession` — LATEST cumulative total per session
  (keyed by sessionID ?? path), picked via `isNewerThan` timestamp compare.
- `latestRateLimits` — single LATEST rate-limit snapshot across ALL
  files, also timestamp-compared.
Both "latest wins" fields need a per-file "latest so far" cached value
that then gets compared across files at combine time — not a pure sum.

## Plan
- [ ] Extract `CodexJSONLParser.parseFile` into a resumable form
      (FileHandle + byte offset, mirroring `ClaudeJSONLParser+Streaming.swift`)
      so grown files can resume instead of full re-read.
- [ ] Add `fileCache: [String: FileCacheEntry]` to `CodexJSONLParser` actor.
- [ ] Define `FileAggregate`: dailyUsage, hourlyTotals, deltaTotal sum,
      latestSessionFinalTotal (per session key), latestRateLimits.
- [ ] Unchanged file (mtime+size match) → reuse cached aggregate, skip parse.
- [ ] Grown file → resume from cached byte offset, merge incremental
      aggregate into cached one (sum deltas, update latest-wins fields
      only if newer).
- [ ] Rotated/truncated/first-sync → full parse, replace cache entry.
- [ ] Combine step: replay each file's cached aggregate into `UsageWindows`
      (reuse Claude's accumulate/merge/apply pattern), sum
      deltaReportedTotalTokens across files, sum per-session latest
      cumulative totals for `finalReportedTotalTokens`, pick global
      latest rate-limit snapshot across files' cached latest.
- [ ] `detectLatestModel` — leave untouched (separate read-only pass,
      not part of the CPU hotpath being fixed).
- [ ] Add `CodexJSONLParserTests` incremental-append test mirroring
      `testIncrementalParseResumesAppendedLogs`.

## Verify
- [ ] `xcodebuild test -scheme AIUsageDashboardCore` — full suite green,
      no regressions.
- [ ] Relaunch app, sample Activity Monitor post-first-sync: Codex's
      ~11% CPU contribution should drop toward ~0% on steady-state syncs.
