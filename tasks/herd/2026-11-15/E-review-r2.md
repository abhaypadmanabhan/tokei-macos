VERDICT: CHANGES

# WP-E integration fixes · review round 2 (Claude Opus 5.5)

Fix round `4687721..b623ef4` (`78c7ffa`, `1898d91`, `b623ef4`). Review only; the worktree is clean at `b623ef4`.
Probes ran in a disposable copy under the session scratchpad (`dd-review-fix-probe`).

## Round 1 findings

- S1 fixed. All four call sites now use one `Utilization(window:providerID:)`, and `bucketKey` survives the rebuild
  inside the policy. Probe: route row, plan and exported snapshot all pick `claude_code`, with Codex in `avoid`.
- S2 fixed. A provider with only the cap gets no row and no recommendation in the plan or the snapshot. The probe
  ran with Claude set to avoid, the case where an extra row would have won.
- S3 fixed for tampered text (control characters and newlines get the fixed fallback; `reasonCode` uses an
  allowlist). See S8 below for a regression on long untampered text.
- S4 fixed. Devanagari, Thai, vowelled Arabic, Malayalam and NFD "Café" now pass. A letter plus 100,000 marks is
  rejected. U+202E (a bidi override character) is still rejected.
- S5 fixed. The JSON reason uses `compactDuration`, so it matches the app's row sentence.
- S6 deferred by t1d; a known gap.

## New findings

S7 [blocker] AIUsageDashboardApp/Core/Agent/RouteTargetPolicy.swift:155 with Core/Utilization/RoutePlan.swift:79-80.
Inside the policy, the cap is rebuilt as a `.monthly` window (from `Utilization.window`). `RoutePlan.priority` then
passes it to `ExpiringHeadroomFinder`, which reads `window.type` and treats it as monthly plan capacity that resets
unused within 3 days. When the spending cap resets within 3 days with at least 25% unspent, the policy ranks Codex
first as "expiring". Expiry also skips the 15-point spread rule. The route row is built from the stored `.credits`
window, sees no expiry and recommends another plan. The result: the chip, `get_recommendation` and `tokei status` say
to send work to Codex because its spending cap is about to reset, which points at overage. The row says otherwise.
This was already latent for the chip in round 1 (I missed it); this round's fix extended it to the agent recommendation.
Repro (probe `testProbeCapResetSoonOrdering`, exit 65): Codex weekly 50% (resets in 5 d) with the cap 10% used
(resets in 2 d); Claude weekly 30% (resets in 5 d):
```
PROBE S7 rows: ["claude_code ready 70.0 exp=nil", "codex ready 50.0 exp=nil"]
PROBE S7 plan.rec: claude_code policy.routeTo: codex snapshot.rec: codex | route to Codex (tightest window 50%)
PROBE S7 expiring finder: []
XCTAssertEqual failed: ("Optional(...codex)") is not equal to ("Optional(...claudeCode)")
```
Fix: in `ExpiringHeadroomFinder.headroom` (ExpiringHeadroom.swift:147), add `guard !window.isCodexIndividualLimit`.
That makes the cap ineligible for expiry on every path, whatever type it was rebuilt with. Add this probe as a test
that checks the row, the policy, the chip and the exported recommendation.

S8 [should] AIUsageDashboardApp/Core/Agent/AgentSnapshot.swift:351 (`plainReason`) The 160-scalar limit is shorter than
the reasons the app itself writes. With four or five providers, a genuine reason runs past 160, and
`get_recommendation` and `tokei status` replace it with "Routing details are unavailable." This breaks the fix brief's
requirement that untampered output stays byte-identical. The byte-identity test uses a short reason, so it misses this.
Repro (probe `testProbeLongGeneratedReason`, 5 providers):
```
PROBE S8 reason (247 scalars): Cursor monthly 95% used, resets in 72h; Claude Code weekly 92% used, resets in 2h; Antigravity excluded from routing (local estimate, not a confirmed reading); Gemini excluded from routing (reading is 45m old); route to Codex (tightest window 20%)
PROBE S8 plainReason: Routing details are unavailable. Refresh Tokei before choosing work.
```
Fix: split on "; " and check each clause with `isPlainText(_, 160)`. Cap the clause count at the provider count plus
one (8 providers today gives 9, about 1,500 scalars at most). Fall back only if a clause fails. Add a test with an
eight-provider generated reason that must stay byte-identical.

## Commands

| Command | Exit |
|---|---|
| `cd AIUsageDashboard && xcodegen generate` (worktree) | 0 |
| `xcodebuild test … -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-fix` with the author's 27 `-only-testing:` classes → `Executed 265 tests, with 0 failures (0 unexpected)`, `** TEST SUCCEEDED **` (log `~/Library/Developer/TokeiWork/E-review-r2-tests.log`) | 0 |
| Probes `ReviewProbeTests` (5 tests, scratch copy at `b623ef4`): S1, S2 and label probes pass; S7 and S8 fail as quoted | 65 (expected: shows S7, S8) |

Not checked: the full suite, the fast gate, secscan, a Release build or perf run, the launch mode of `test-perf-bench.sh`.
I did not launch the installed app.
