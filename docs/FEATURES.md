# Feature map

Core verification uses the existing XcodeGen `AIUsageDashboardCore` scheme (`.claude/gates/test.sh`). Under the 2026-10-29 TCC addendum, generate/test in a disposable worktree outside Downloads with the lane's DerivedData path. The [WP-5 result](../tasks/reports/2026-10-29-wp5.result.md) records commands and measured limits.

| Feature | How to reach it | Expected result | Key files | Verification |
| --- | --- | --- | --- | --- |
| Codex compressed session usage | `CodexProvider.fetchSnapshot()` discovers regular `~/.codex/sessions/**/*.jsonl.zst` alongside plain logs | Both formats contribute; plain duplicate wins; invalid compressed files yield one info warning and no partial usage; unchanged fingerprints decode once per process | `Core/Providers/CodexProvider.swift`; `Core/Parsing/CodexJSONLParser.swift`, `CodexJSONLFramer.swift`, `CodexCompressedLogCache.swift`, `CodexRolloutFiles.swift`; `Core/Parsing/Zstd/` | Core scheme: `CodexCompressedRolloutTests`, `ZstdDecoderTests` and existing Codex parser/provider/cost/tier tests. Opt-in `CodexCompressedRealLogsTests` compares independent totals and retains the failing 15-second target. |

Core paths are relative to `AIUsageDashboard/AIUsageDashboardApp/`. Native app navigation and release behavior were not verified in WP-5.
