VERDICT: CHANGES

# WP-E integration fixes · review round 1 (Claude Opus 5.5)

Branch `patch/2026-11-15/integration-fix` at `4687721`, diff `dev...HEAD` (dev = `78bdb03`). Review only; the
worktree is unchanged (`git status` clean). Probes ran in a disposable copy under the session scratchpad.

## Findings

S1 [blocker] AIUsageDashboardApp/Core/Agent/AgentSnapshotWriter.swift:79 The agent snapshot's `recommendation`
still ignores the Codex individual cap. The writer builds `Utilization(window: window.type)` (`.credits`), and
`RouteTargetPolicy.evaluate` (RouteTargetPolicy.swift:155) rebuilds `QuotaWindow`s without `bucketKey`, so
`routingWindowType` cannot see the cap and the binding filter drops it. The route row and the recommendation now
disagree. MCP `get_recommendation`, `tokei status` and `tokei guard` target selection all read that recommendation.
At `713cf93`, `evaluate` kept Codex credits readings, so this is still a 0.13.0 regression. The new test checks the
policy over `UtilizationEngine.utilizations` (which now says `.monthly`), not over the exported snapshot, so it passes.
Repro (probe test, scratch copy, exit 65): Codex weekly 20% plus cap 90%, Claude weekly 70%:
```
PROBE row codex: ["claude_code ready 30.0", "codex avoid 10.0"]
PROBE plan.recommendation: claude_code
PROBE snapshot.recommendation.routeTo: codex
PROBE snapshot.recommendation.reason: route to Codex (tightest window 20%)
XCTAssertEqual failed: ("Optional("codex")") is not equal to ("Optional("claude_code")")
```
Fix: use `window.routingWindowType` at AgentSnapshotWriter.swift:79. To prevent a fifth miss, give `Utilization` one
`init(window:providerID:)` that applies it, and call that from AgentSnapshotWriter:77, AccountQuotaDecision:31,
RoutePlan:131 and UtilizationEngine:61. In `testCodexIndividualLimitBinds…`, add asserts that
`exported.recommendation?.routeTo` and `.avoid` match the plan's.

S2 [should] AIUsageDashboardApp/Core/Utilization/RoutePlan.swift:97 (used by the guard at :144 and by
`hasTrustedCoverage` at :125) A Codex reading that has only the spending cap now counts as a flat-rate plan. The
parser appends the cap whether or not `primary` or `secondary` exist (CodexJSONLParser.swift:953). The result is a
ready row, "This plan has 80% left in its tightest window.", based only on a credit spend limit. Whenever every other
plan is set to avoid, that row becomes the recommendation, which means routing work to paid credits. Dev excluded
this row. Repro (probe, exit 0): Codex with only the cap at 20%, Claude weekly 70%:
`rows: [... "codex ready 80.0 monthly This plan has 80% left in its tightest window."]`.
Not verified: whether Codex really sends `spend_control` without rate windows (for example, credits-only workspaces).
Fix: let the cap bind (count it in `isBindingWindow` and when picking the peak), but require at least one non-cap plan
window before a provider or account becomes a row or counts as covered, both here and in the `evaluate` filter. Add a
test: cap only → no row and no recommendation.

S3 [should] TokeiCLI/MCPServer.swift:387 and TokeiCLI/StatusFormatting.swift:85 (also :128 `reasonCode`)
`get_recommendation` and `tokei status` still copy the snapshot's `recommendation.reason` (and the quota `reasonCode`)
to the agent or terminal word for word. This is the same tamper class 2b closed for `get_route`. It is outside the
file 2b named and was already on dev, but the review brief asks that no snapshot string reach an agent unsanitised.
Fix: rebuild the sentence from `routeTo`, `avoid` and `target`, or gate it through
`AgentBurnWindow.isPlainText(_, 160)` with a fixed fallback, and map `reasonCode` through a fixed allowlist. Reuse the
tampered-snapshot process test. This could go to a follow-up lane if the orchestrator prefers.

S4 [nit] AIUsageDashboardApp/Core/Agent/AgentSnapshot.swift:582 Rejecting combining marks makes valid labels in
scripts that need marks fail the check. Probe results: Devanagari "साप्ताहिक सीमा" false, Thai "สัปดาห์" false,
Gurmukhi and Tamil false, vowelled Arabic "أُسْبُوعِيّ" false, NFD "Café" false. Unvowelled Arabic, CJK, Hangul (NFC
and NFD), Vietnamese and precomposed "Café weekly" pass. Nothing is mangled: the check passes or fails the whole
label, so a failed label falls back to "account N" or the window-type name, never to partly stripped text.
Trade-off: the scalar bound alone already closes the 100,000-mark case; rejecting marks only adds protection against
stacked-mark (Zalgo) spoofing. If non-Latin account names matter, normalise to NFC first and allow at most two marks
in a row after a base letter. Fine to ship as is.

S5 [nit] TokeiCLI/RouteFormatting.swift:123 The rebuilt reason matches the app's sentences (RoutePlan.swift:157-165)
branch for branch, with the same rounding and the same avoid line at 15% or less left. Only the duration differs: the
CLI's `countdown` prints "42 min" or "2 d" and rounds up, while the app's row prints "42m" or "71h" (`compactDuration`,
which rounds down). So the JSON `reason` is not byte-equal to the app's sentence for the same row. Fix: make
`AgentSnapshot.compactDuration` public and use it in `reason()`; keep `countdown` for the rendered table.

S6 [nit] AIUsageDashboard/scripts/test-perf-bench.sh No gate or CI step runs it, so the 2c and 2d regressions are
locked in only when someone runs it by hand. Fix: run `test-perf-bench.sh <any path> python` (it launches no app)
from `.claude/gates/run-all.sh fast`, and put the `launch` mode on the release checklist.

## Confirmed as intended

- Purchasable credits stay out of routing: `bucketKey "credits"` keeps `.credits`, so no row can come from it, and the
  new test covers this.
- The cap never turns into "use it before reset" advice: ExpiringHeadroom.swift:147 and `QuotaSample` read the stored
  `.credits` type, so its horizon is nil. Burn, nudges and `expiringAt` are unaffected.
- Chips agree with the row: `gaugeUtilizations` comes from `UtilizationEngine` (now `.monthly`), so the cap survives
  the `!= .credits` filter.
- Probe guard: when the guard fails, launch falls to the `else` branch, which starts Sparkle. Window-close and
  Sparkle-off happen only in the fully isolated branch. Elsewhere the flag only writes `[perf]` lines to stderr,
  with no account data. The driver still exits non-zero when the `isolated` event is missing (perf-bench.sh:157-160).
- `-I`: every import in the driver is from the standard library. An invalid-path run reaches the driver's own
  validation, which shows the imports load.
- Sanitiser: the bound counts Unicode scalars; existing sanitiser tests pass.

## Commands

| Command | Exit |
|---|---|
| `cd AIUsageDashboard && xcodegen generate` (worktree) | 0 |
| `xcodebuild test … -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-fix` with the result's 20 `-only-testing:` classes → `Executed 189 tests, with 0 failures (0 unexpected)`, `** TEST SUCCEEDED **` (log `~/Library/Developer/TokeiWork/E-review-r1-tests.log`) | 0 |
| Probe `ReviewProbeTests` in a scratch copy (`dd-review-fix-probe`): S1 assert fails; S4 label table printed | 65 (expected: shows S1) |
| Probe `testProbeCapOnly` (S2) | 0 (prints the ready cap-only row) |
| `bash scripts/perf-bench.sh /nonexistent.app` → `perf-bench: expected a built Tokei.app` | 1 (expected) |
| `ls ~/Library/Preferences \| grep -c 'tokei\.perf\.\|tokei\.launch-test\.'` → 0 | — |

Not checked: a full `perf-bench.sh` run, `test-perf-bench.sh` launch mode (it launches app copies), the full suite,
the installed app (not launched).
