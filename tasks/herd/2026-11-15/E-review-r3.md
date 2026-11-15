VERDICT: APPROVE

# WP-E integration fixes · review round 3, final (Claude Opus 5.5)

Fix round `b623ef4..d002dc2` (`782a67b`, `d002dc2`). Review only; the worktree is clean at `d002dc2`. Probes ran in a
disposable copy under the session scratchpad (`dd-review-fix-probe`).

## Round 2 findings

- S7 fixed. `ExpiringHeadroomFinder.headroom` now rejects `isCodexIndividualLimit` before it looks at the type. That
  one boundary covers all three `find` callers (RoutePlan.priority, BurnEngine, AgentSnapshotWriter), whatever type
  the cap was rebuilt with. Historical burn outcomes read the stored `.credits` sample type, which has no horizon, so
  they are also unaffected. Probe at `d002dc2`: the row, the plan, the policy and the exported snapshot all pick
  `claude_code`, and no expiry is invented:
  `PROBE S7 plan.rec: claude_code policy.routeTo: claude_code snapshot.rec: claude_code | route to Claude Code (tightest window 30%)`.
- S8 fixed. Each "; "-separated clause is checked at 160 scalars, with at most 9 clauses. Avoid and excluded clauses
  are disjoint per provider, so 8 providers plus the target clause is the real maximum. Probe: the 247-scalar,
  five-provider reason now passes byte for byte through `plainReason`.
- Earlier probes still pass: S1 (the snapshot agrees with the plan and Codex is in avoid), S2 (a cap-only reading
  gets no row and no recommendation), S4 (the Indic, Thai, Arabic and NFD labels pass; the mark flood and U+202E are
  rejected).

## New findings

S9 [nit] AIUsageDashboardApp/Core/Agent/AgentRecommendationEngine.swift:136 (target clause) The clause
" account \(label)" uses the raw account label, which comes from the config directory name
(`.codex-<name>` / `.claude-<name>`). If that name contains a character outside the allowlist, such as `@`, `#` or
`~`, the whole genuine reason falls back to "Routing details are unavailable." in `get_recommendation` and
`tokei status`. `routeTo` and `target` are still correct. It fails safe and is rare.
Repro (probe `testProbeTargetAccountLabel`): Codex accounts `me@work` (10%) and `default` (60%), Claude 90%:
`reason: Claude Code weekly 90% used, resets in 48h; route to Codex account me@work (tightest window 10%)` →
`plainReason: Routing details are unavailable. Refresh Tokei before choosing work.`
Fix (follow-up is fine): apply RoutePlan's `plainAccountLabel` rule (fall back to "account N") to that clause.

S6 stays deferred (a known gap): no gate runs `test-perf-bench.sh`.

## Commands

| Command | Exit |
|---|---|
| `cd AIUsageDashboard && xcodegen generate` (worktree) | 0 |
| `xcodebuild test … -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-fix` with the author's 37 `-only-testing:` classes → `Executed 361 tests, with 0 failures (0 unexpected)`, `** TEST SUCCEEDED **` (log `~/Library/Developer/TokeiWork/E-review-r3-tests.log`) | 0 |
| Probes `ReviewProbeTests` (6 tests: S1, S2, S7, S8, labels, S9) in a scratch copy at `d002dc2` | 0 |
| `ls ~/Library/Preferences \| grep -c 'tokei\.perf\.\|tokei\.launch-test\.'` → 0 | — |

Not checked: the full suite, the fast gate, secscan (the author reports PASS for both), a Release build or perf run at
the final head, the launch mode of `test-perf-bench.sh`. I did not launch the installed app.
