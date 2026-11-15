STATUS: READY

# WP-E integration fixes

Branch: `patch/2026-11-15/integration-fix`, started at `78bdb03`; final HEAD `4687721`.
Worktree: `/Users/abhayp/wt/lane1`. Four commits, clean working tree, no merge or push.
All requested lane checks passed. All evidence below is from actual commands, using synthetic data.

## 1. Codex quota regression

**Cause:** `a4f41fc` replaced AccountQuotaDecision's non-informational-window filter with RoutePlan's binding filter. The latter omitted `spend_control_individual_limit`, because the parser stores that monthly plan ceiling as `.credits`. The unchanged test therefore reported 80% headroom from the weekly window instead of the correct 10% from the individual ceiling.

**Base evidence:** before editing, switched this same worktree to detached `713cf93`, generated its Xcode project, ran the identical single test with `dd-fix`, then restored the assigned branch. No stash or extra worktree was used. The old release base passed; this is not a clock or load-dependent test failure. The existing test and its clock are unchanged.

**Fix commit:** `64c1f94 fix(route): preserve the Codex individual plan ceiling`.

- `Core/Utilization/UtilizationEngine.swift`: the known Codex individual ceiling projects to a monthly routing type, retaining the original stored quota shape.
- `Core/Utilization/RoutePlan.swift`: the shared binding filter and exported deciding window use that type. Purchasable credits still cannot become a route.
- `Tests/UtilizationTests/RoutePlanTests.swift`: a regression checks both ready and avoid cases, account headroom, policy ordering, CLI projection and exclusion of purchasable credits.

Actual red/base/green lines:

```text
E-quota-red.log (integration before changes):
XCTAssertEqual failed: ("Optional(80.0)") is not equal to ("Optional(10.0)")
Test Case '-[AIUsageDashboardCoreTests.CodexLiveQuotaTests testLiveWeeklyKeepsTighterLogIndividualLimit]' failed (0.650 seconds).
E-quota-base.log (713cf93):
Test Case '-[AIUsageDashboardCoreTests.CodexLiveQuotaTests testLiveWeeklyKeepsTighterLogIndividualLimit]' passed (0.015 seconds).
E-route-cap-red.log (new test, old implementation):
Executed 1 test, with 9 failures (0 unexpected)
E-quota-green.log:
Test Case '-[AIUsageDashboardCoreTests.CodexLiveQuotaTests testLiveWeeklyKeepsTighterLogIndividualLimit]' passed (0.006 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexIndividualLimitBindsAccountRoutePolicyAndCLIWithoutRoutingToPaidCredits]' passed (0.002 seconds).
Executed 52 tests, with 0 failures (0 unexpected)
```

The single-test command on integration and on `713cf93` was:

```sh
xcodebuild test -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore   -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-fix   -only-testing:AIUsageDashboardCoreTests/CodexLiveQuotaTests/testLiveWeeklyKeepsTighterLogIndividualLimit
```

## 2a. Scalar-bound label sanitizer

**Cause:** Character.count measured grapheme clusters, while CharacterSet.alphanumerics accepted combining marks. A letter followed by 100,000 marks was one character and passed the old limit.

**Fix commit:** `0d4d2e8 fix(agents): bound labels by Unicode scalars and reject marks`.

- `Core/Agent/AgentSnapshot.swift`: count Unicode scalars and subtract non-base characters from the allowlist.
- `Tests/AgentTests/AgentBurnSnapshotTests.swift`: reject short combining sequences and the 100,000-mark case, exercise the window-name fallback, preserve ordinary precomposed accented labels, and test the 48/49 boundary.

```text
E-agent-security-red.log:
Test Case '-[AIUsageDashboardCoreTests.AgentBurnSnapshotTests testPlainTextRejectsCombiningMarksAndBoundsUnicodeScalars]' failed (0.662 seconds).
E-agent-security-green.log:
Test Case '-[AIUsageDashboardCoreTests.AgentBurnSnapshotTests testPlainTextRejectsCombiningMarksAndBoundsUnicodeScalars]' passed (0.007 seconds).
```

The final run includes the existing burn and MCP sanitizer checks unchanged.

## 2b. Rebuild route prose at the CLI boundary

**Cause:** the character allowlist could reject terminal codes but could not distinguish an ordinary sentence from an instruction placed in the saved row's reason. The CLI and get_route MCP tool echoed that saved sentence.

**Fix commit:** `e59179c fix(cli): rebuild route advice from validated fields`.

- `TokeiCLI/RouteFormatting.swift`: generate reason from fixed sentences, validated disposition, remaining percentage, expiry and pace. Advice uses that generated reason; the saved reason is never read.
- `Tests/CLITests/RouteCommandTests.swift`: verify all sentence branches, a later evaluation clock, human output, JSON, and the real CLI/MCP helper processes against tampered saved prose.
- JSON keys remain unchanged. Its reason/advice values are now rebuilt; the byte-equality fixture deliberately changes only the expiry wording from `42m` to `42 min`. The existing byte-equality assertions remain.

```text
E-agent-security-red.log:
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testRealCLIAndMCPNeverEchoATamperedRouteReason]' failed (0.783 seconds).
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testRouteReasonAndAdviceAreRebuiltFromFieldsInsteadOfSavedProse]' failed (0.023 seconds).
E-agent-security-green.log:
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testRealCLIAndMCPNeverEchoATamperedRouteReason]' passed (0.258 seconds).
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testRouteReasonAndAdviceAreRebuiltFromFieldsInsteadOfSavedProse]' passed (0.001 seconds).
Executed 26 tests, with 0 failures (0 unexpected)
```

## 2c. Ordinary Release launches survive an inherited probe flag

**Cause:** setting TOKEI_PERF_PROBE=1 entered a fatalError branch when either the disposable bundle identity or synthetic-home marker was absent.

**Fix commit:** `4687721 fix(perf): keep ordinary launches safe and isolate Python`.

- `App/AIUsageDashboardApp.swift`: enter the window-closing benchmark setup only when the flag and both isolation checks pass; otherwise continue the ordinary startup path.
- `scripts/test-perf-bench.sh`: reusable regression checks run the actual Release binary in disposable copies, with network switches disabled and disposable preferences cleaned. Both an incorrect bundle identity and a missing home marker are tested.
- A separate fault-injection check omits the marker from a temporary copy of the benchmark driver and shortens only its hook deadline to five seconds. The real Release app is unchanged. The driver exits nonzero with its existing missing-hooks error, proving that ignoring the flag in the app does not silently make the benchmark succeed.

```text
E-perf-launch-red.log (original Release executable):
FAIL unisolated Release launch proceeds (wrong_bundle): Release app exited -5 before initial refresh
FAIL unisolated Release launch proceeds (missing_marker): Release app exited -5 before initial refresh
E-perf-guards-green.log (fixed Release executable):
PASS unisolated Release launch proceeds (wrong_bundle)
PASS unisolated Release launch proceeds (missing_marker)
PASS driver exits nonzero when isolation is missing
```

## 2d. Isolated Python invocation

**Cause:** the driver's ordinary `python3 -` could import an attacker-controlled standard-library replacement from the caller's current directory or PYTHONPATH.

**Fix commit:** `4687721` (same benchmark-boundary commit).

- `scripts/perf-bench.sh`: its only Python invocation is now `python3 -I -`.
- `scripts/test-perf-bench.sh`: supplies a poison json.py through both cwd and PYTHONPATH, then checks that the driver reaches its own expected invalid-app validation instead of loading that module. The test runner itself uses isolated Python.

```text
E-perf-python-red.log:
FAIL driver ignores Python modules from PYTHONPATH and cwd: loaded Python code from PYTHONPATH or cwd
E-perf-python-green.log / E-perf-guards-green.log:
PASS driver ignores Python modules from PYTHONPATH and cwd
```

Native/script regression command (exit 0):

```sh
bash scripts/test-perf-bench.sh ~/Library/Developer/TokeiWork/dd-fix/Build/Products/Release/Tokei.app
```

## Final verification

Project generation: `xcodegen generate` in `AIUsageDashboard/`.
Release build command (exit 0; `E-release-after.log` ends `** BUILD SUCCEEDED **`):

```sh
xcodebuild build -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp   -configuration Release -destination 'platform=macOS'   -derivedDataPath ~/Library/Developer/TokeiWork/dd-fix
```

Final targeted command (exit 0):

```sh
xcodebuild test -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore   -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-fix   -only-testing:AIUsageDashboardCoreTests/CodexLiveQuotaTests   -only-testing:AIUsageDashboardCoreTests/CodexRateLimitClientTests   -only-testing:AIUsageDashboardCoreTests/CodexProviderTests   -only-testing:AIUsageDashboardCoreTests/CodexJSONLParserTests   -only-testing:AIUsageDashboardCoreTests/AccountQuotaDecisionTests   -only-testing:AIUsageDashboardCoreTests/RouteTargetPolicyTests   -only-testing:AIUsageDashboardCoreTests/RoutePlanTests   -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests   -only-testing:AIUsageDashboardCoreTests/RouteCommandTests   -only-testing:AIUsageDashboardCoreTests/RouteMCPTests   -only-testing:AIUsageDashboardCoreTests/AgentBurnSnapshotTests   -only-testing:AIUsageDashboardCoreTests/AgentRouteSnapshotTests   -only-testing:AIUsageDashboardCoreTests/BurnMCPTests   -only-testing:AIUsageDashboardCoreTests/MCPAccountContractTests   -only-testing:AIUsageDashboardCoreTests/MCPServerMemoryTests   -only-testing:AIUsageDashboardCoreTests/MCPServerTests   -only-testing:AIUsageDashboardCoreTests/MCPServerErrorTests   -only-testing:AIUsageDashboardCoreTests/MCPServerProcessTests   -only-testing:AIUsageDashboardCoreTests/MCPServerExchangeMatrixTests   -only-testing:AIUsageDashboardCoreTests/WP4MCPTests
```

`E-targeted-final.log`:

```text
Test Suite 'Selected tests' passed at 2026-11-15 04:01:08.764.
Executed 189 tests, with 0 failures (0 unexpected) in 7.263 (7.321) seconds
** TEST SUCCEEDED **
```

Release performance command (exit 0):

```sh
bash scripts/perf-bench.sh ~/Library/Developer/TokeiWork/dd-fix/Build/Products/Release/Tokei.app
```

Actual `E-perf-final.log` metrics, against the unchanged `scripts/perf-budget.json`:

```text
average_cpu_percent                    0.518 %       1.000 % budget
physical_footprint_mb                  65.657 MB    200.000 MB budget
cold_launch_to_window_ms              556.400 ms   1500.000 ms budget
peak_footprint_mb                      70.126 MB
sample_seconds                       120.008
writes                               120
provider_refreshes                   claude_code=8; all seven others=0
budget_passed                        true
synthetic_home_verified               true
preferences_cleaned                   true
```

Ran `bash .claude/gates/run-all.sh fast` successfully, and after the performance run repeated it with `BASE_REF=78bdb03` so its diff checks cover all four lane commits. `E-gates-fast.log`:

```text
[no-secret] PASS no secrets detected
[no-uncommitted] PASS no uncommitted changes in /Users/abhayp/wt/lane1
[cli-version-sync] PASS helper version derives from MARKETING_VERSION (0.12.0)
[format] SKIP swiftformat not installed (brew install swiftformat)
[lint] SKIP swiftlint not installed (brew install swiftlint)
[run-all] ALL GATES GREEN
```

`~/agent-kit/bin/secscan /Users/abhayp/wt/lane1` returned exit 0 at final HEAD:

```text
VERDICT: PASS
repo lane1 head 468772155e9c base origin/dev (713cf93ca224): 34 commits, 0 uncommitted paths
```

No FLAG or GAP was reported. `git diff --check 78bdb03..HEAD` passed.

All evidence logs are under `/Users/abhayp/Library/Developer/TokeiWork/`, named above; no logs or personal usage entered git.

## Limits, risks and handoff

- Full suite, cross-model review, prove-red utility, work log and release integration remain with the orchestrator under worker.md. Manual old-implementation red failures and actual green runs are preserved above.
- SwiftFormat and SwiftLint were not installed; those optional fast gates skipped. Release compiler warnings have the same seven source locations in E-release-before.log and E-release-after.log, outside this fix. No new source warning location appeared.
- No customer data, live provider service, installed app state or UI appearance changes were tested. Release launch and performance proof used only disposable synthetic homes/bundles. No screenshot was needed for this logic-only lane.
- No persisted schema or JSON keys were added or removed. The known Codex individual limit projects as monthly for routing; its stored quota type remains credits. Route JSON prose is intentionally rebuilt at read time.
- No test was removed, disabled or relaxed. The existing Codex test is byte-for-byte unchanged.
- The repository still carries its integration version 0.12.0; the orchestrator owns the planned 0.13.0 release bump.
- All twelve hc command terminals started by this lane completed and were removed. Benchmark/test child apps terminated and their disposable preferences were verified removed. No proof server or watcher remains; listener inventory contained none started by this lane.
- Rollback: revert these four lane commits in reverse order before integration. No deployment or data migration occurred.
- Waits on t1d to review, rerun the lane gates and integrate the four commits.


# Fix round 1

STATUS: READY. Addressed the accepted findings in E-review-r1.md under E-fix-r1.md.
Final HEAD: `b623ef4`; the worktree is clean. No merge or push.
This section supersedes the original combining-mark rejection and JSON duration wording above.

## Changes and commits

- **S1 / S2 — `78c7ffa`**: added the canonical failable `Utilization(window:providerID:plan:)` initializer and used it in AgentSnapshotWriter, AccountQuotaDecision, RoutePlan and UtilizationEngine. The optional bucketKey survives internal utilization/cache encoding and policy reconstruction, so the individual cap cannot lose its identity after becoming monthly. Existing entries without the optional key still decode. No ProviderSnapshot field or public agent-snapshot key changed.
- **S1**: the exported snapshot's recommendation.routeTo and avoid are now asserted against RoutePlan, not only against the engine's utilization projection. The Codex 90% cap now produces 10% headroom and avoid consistently across the row and exported legacy recommendation.
- **S2**: a cap remains a binding constraint, but is not a genuine subscription window. Rows, account eligibility, policy coverage and aggregate coverage require a non-cap plan. New tests cover provider-level and account-level cap-only data, including the case where counting it would falsely satisfy the two-provider routing threshold.
- **S3 / S4 — `1898d91`**: legacy MCP recommendation and human status output use one bounded plain-text reason projection and fixed fallback. Generated semicolon-separated clauses retain their original bytes. Status reasonCode uses the fixed no_quota_reading/untrusted_reading allowlist. A real CLI/MCP process test catches control/newline and oversized saved prose; exact byte fixtures pass on both old and new code for ordinary input.
- **S4**: combining marks are legal again, while the Unicode-scalar length bound remains. Devanagari, Malayalam, Thai, vowelled Arabic and decomposed accented labels survive unchanged. One letter plus 100,000 marks remains rejected. This is the explicitly accepted correction to the original sanitization policy.
- **S5 — `b623ef4`**: one production line now calls AgentSnapshot.compactDuration for the JSON reason. That helper was already public through its public extension, so no visibility change was needed. The test checks 71h in JSON and 2 d in the human rendering. Original compact 42m JSON bytes are restored; human countdown wording remains unchanged.
- **S6 — deferred as instructed**: test-perf-bench.sh is still not run by a gate or CI. Its Python check and Release launch checks remain manual. No gate/checklist files were changed for this declined finding.

## Runtime red, then green

All accepted behavior changes were exercised against the current pre-round implementation before editing production code. Two earlier test-setup compile errors were corrected first and are not counted as red evidence.

Actual E-fix-r1-red.log lines (old implementation):

```text
Test Case '-[AIUsageDashboardCoreTests.AgentBurnSnapshotTests testPlainTextPreservesCombiningMarksAndBoundsUnicodeScalars]' failed (0.672 seconds).
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testRebuiltJSONReasonMatchesTheAppsCompactDuration]' failed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexCapAloneIsNeverPlanCoverageForProviderOrAccount]' failed (0.009 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexCapIdentitySurvivesUtilizationEncoding]' failed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexIndividualLimitBindsAccountRoutePolicyAndCLIWithoutRoutingToPaidCredits]' failed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.StatusFormattingTests testTamperedRecommendationAndReasonCodesUseFixedFallbacksInCLIAndMCP]' failed (0.355 seconds).
Test Case '-[AIUsageDashboardCoreTests.StatusFormattingTests testUntamperedRecommendationStatusAndMCPBytesStayIdentical]' passed (0.003 seconds).
```

Actual E-fix-r1-final.log lines (final implementation):

```text
Test Case '-[AIUsageDashboardCoreTests.AgentBurnSnapshotTests testPlainTextPreservesCombiningMarksAndBoundsUnicodeScalars]' passed (0.005 seconds).
Test Case '-[AIUsageDashboardCoreTests.RouteCommandTests testRebuiltJSONReasonMatchesTheAppsCompactDuration]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexCapAloneIsNeverPlanCoverageForProviderOrAccount]' passed (0.003 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexCapIdentitySurvivesUtilizationEncoding]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexIndividualLimitBindsAccountRoutePolicyAndCLIWithoutRoutingToPaidCredits]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.StatusFormattingTests testTamperedRecommendationAndReasonCodesUseFixedFallbacksInCLIAndMCP]' passed (0.348 seconds).
Test Case '-[AIUsageDashboardCoreTests.StatusFormattingTests testUntamperedRecommendationStatusAndMCPBytesStayIdentical]' passed (0.006 seconds).
Executed 265 tests, with 0 failures (0 unexpected) in 9.511 (9.599) seconds
** TEST SUCCEEDED **
```

The byte-equality control passed before and after the change. The cap identity test also verifies that decoding an older utilization without bucketKey remains valid.

## Checks and rerun commands

All xcodebuild runs used `-derivedDataPath ~/Library/Developer/TokeiWork/dd-fix` and `-destination 'platform=macOS'` with scheme AIUsageDashboardCore. Routing slice: 97 tests passed. Text slice: 59 tests passed.

Final targeted command, from AIUsageDashboard/ (exit 0):

```sh
e_classes="CodexLiveQuotaTests CodexRateLimitClientTests CodexProviderTests CodexJSONLParserTests AccountQuotaDecisionTests RouteTargetPolicyTests RoutePlanTests UtilizationEngineTests RouteCommandTests RouteMCPTests AgentBurnSnapshotTests AgentRouteSnapshotTests BurnMCPTests MCPAccountContractTests MCPServerMemoryTests MCPServerTests MCPServerErrorTests MCPServerProcessTests MCPServerExchangeMatrixTests WP4MCPTests StatusFormattingTests AgentSnapshotWriterTests AgentSnapshotAccountSchemaTests GuardProcessTests ReviewSingleProviderGuardTests UtilizationCacheTests AgentRecommendationEngineTests"
set --
for e_class in $e_classes; do set -- "$@" "-only-testing:AIUsageDashboardCoreTests/$e_class"; done
xcodebuild test -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-fix "$@"
```

Fast gate, from the worktree root (exit 0):

```sh
BASE_REF=4687721 bash .claude/gates/run-all.sh fast
```

E-fix-r1-fast.log ends `[run-all] ALL GATES GREEN`; no-secret scanned the three round commits and passed; the worktree is clean. SwiftFormat and SwiftLint remain unavailable and their optional gates skipped.

Final secscan: `VERDICT: PASS`, HEAD `b623ef4b2cdb`, 0 uncommitted paths; no FLAG or GAP. Full log: E-fix-r1-secscan-final.log. `git diff --check 4687721..HEAD` passed. All logs remain under `/Users/abhayp/Library/Developer/TokeiWork/`.

Not rerun this round: the full suite, the native Release build/performance sample, cross-model review and release integration; the orchestrator owns those gates. The earlier performance numbers above belong to 4687721 and are not new measurements of b623ef4. The accepted S3 protection is a syntax/length gate, not semantic regeneration of legacy prose.

All six hc command terminals started in this round completed and were removed. Real helper processes terminated normally; no proof server or watcher remains. Lessons recorded for exported-recommendation coverage and Unicode-mark compatibility.

Waits on t1d to review the three new commits and integrate the lane.


# Fix round 2

STATUS: READY. Addressed S7 and S8 in E-review-r2.md under E-fix-r2.md.
Final HEAD: `d002dc2`; clean worktree. No merge or push.
This section supersedes round 1's whole-reason 160-scalar limit.

## S7: a spending cap can never become expiring plan capacity

**Cause:** policy reconstruction legitimately projected the Codex individual cap to monthly for routing. The expiry finder then classified that cap using only its reconstructed window type, granting it priority as unused plan capacity. That could make the chip and exported recommendation prefer Codex while the stored-credit-based row preferred Claude.

**Commit:** `782a67b fix(burn): exclude individual spending caps from expiring capacity`.

- `Core/Game/ExpiringHeadroom.swift`: the common headroom boundary now rejects isCodexIndividualLimit before evaluating any type horizon. The cap still constrains quota; it simply cannot supply expiring capacity.
- `Tests/UtilizationTests/RoutePlanTests.swift`: reproduces the reviewer's weekly-Codex-50%, cap-10%-reset-in-two-days, weekly-Claude-30% case. Tests both stored credits and rebuilt monthly types. The route row, policy, chip input and exported legacy recommendation all select Claude, with no fabricated expiry and no avoid entry.
- `Tests/GameTests/ExpiringHeadroomTests.swift`: tests all eight window types through both provider-level and account-level inputs, plus an end-to-end burn test with a real Claude plan as a positive control. The Codex cap is excluded while the genuine plan survives.

### Consumer search and proof

A repository search found three calls to ExpiringHeadroomFinder.find: RoutePlan.priority, BurnEngine.evaluate and AgentSnapshotWriter.buildSnapshot. All now share the same cap rejection. Downstream consumers were read as follows:

- **Burn nudges:** BurnEngine's expiring list reaches NotificationEngine.evaluateBurn, which calls BurnNudge.candidates. The integration regression runs BurnEngine and BurnNudge.candidates and asserts the only window nudge is the legitimate Claude plan. Existing BurnNotificationTests also pass. No real notification was sent.
- **tokei burn:** AgentSnapshotWriter independently projects the finder output to AgentBurn. BurnFormatting renders AgentBurn.opportunities. The regression launches the actual CLI with a generated snapshot, requires the Claude plan in the output and rejects Codex.
- **get_burn_opportunities:** MCPServer uses the same AgentBurn.opportunities method. The regression launches the actual MCP helper, calls this tool and asserts its expiring array contains only claude_code.
- **Burn tab's use-it-or-lose-it list:** BurnView passes BurnBoard.snapshot.expiring directly to ExpiringSection. The regression constructs BurnBoard from the real BurnEngine result and asserts this exact input list contains only Claude. This proves the data input; no visual screenshot or UI layout claim is made.
- **Burn strip:** it also reads the same snapshot.expiring list, so it receives the same exclusion. No separate expiry calculation was found in either Burn view.

The separate historical BurnWindowOutcomes helper uses horizon policy for past quota samples, rather than consuming expiring headroom. Its stored credit sample behavior was not changed; the current expiring-cap regression is closed in the finder itself.

## S8: preserve real multi-provider reasons without accepting malformed clauses

**Cause:** one valid reason can contain the app's clause for each provider and exceed 160 scalars. Applying that bound to the whole explanation replaced valid generated prose with the fallback.

**Commit:** `d002dc2 fix(agents): preserve bounded multi-provider explanations`.

- `Core/Agent/AgentSnapshot.swift`: split generated clauses on "; ", admit at most nine clauses (eight providers plus a target clause), and apply the existing 160-scalar plain-text check to each clause. Return the original reason byte for byte only when every clause passes.
- `Tests/CLITests/StatusFormattingTests.swift`: generates a real eight-provider explanation with AgentRecommendationEngine, confirms that it exceeds the old total limit, and verifies byte identity through plainReason, the actual status CLI and the actual recommendation MCP helper. A malformed/control-containing clause, an oversized clause and ten clauses all receive the fixed fallback; the nine-clause boundary is admitted.

## Runtime red, then green

The four new tests compiled and ran against `b623ef4` before production edits. Every test failed for the reported behavior.

E-fix-r2-red.log:

```text
Test Case '-[AIUsageDashboardCoreTests.ExpiringHeadroomTests testIndividualCapNeverExpiresRegardlessOfRebuiltWindowType]' failed (0.603 seconds).
Test Case '-[AIUsageDashboardCoreTests.ExpiringHeadroomTests testIndividualCapNeverReachesBurnNudgesBoardCLIOrMCP]' failed (0.177 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexCapResetSoonCannotChangePlanPolicyChipOrExportedOrdering]' failed (0.007 seconds).
Test Case '-[AIUsageDashboardCoreTests.StatusFormattingTests testEightProviderGeneratedReasonStaysByteIdenticalAndTamperedClauseFallsBack]' failed (0.171 seconds).
```

E-fix-r2-final.log:

```text
Test Case '-[AIUsageDashboardCoreTests.ExpiringHeadroomTests testIndividualCapNeverExpiresRegardlessOfRebuiltWindowType]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.ExpiringHeadroomTests testIndividualCapNeverReachesBurnNudgesBoardCLIOrMCP]' passed (0.172 seconds).
Test Case '-[AIUsageDashboardCoreTests.RoutePlanTests testCodexCapResetSoonCannotChangePlanPolicyChipOrExportedOrdering]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.StatusFormattingTests testEightProviderGeneratedReasonStaysByteIdenticalAndTamperedClauseFallsBack]' passed (0.166 seconds).
Executed 361 tests, with 0 failures (0 unexpected) in 10.351 (10.458) seconds
** TEST SUCCEEDED **
```

The first slice run also passed 72 targeted tests. Native helper proof uses temporary synthetic snapshots and cleans up its processes and files.

## Final gates and rerun command

From AIUsageDashboard/ (exit 0):

```sh
e_classes="CodexLiveQuotaTests CodexRateLimitClientTests CodexProviderTests CodexJSONLParserTests AccountQuotaDecisionTests RouteTargetPolicyTests RoutePlanTests UtilizationEngineTests RouteCommandTests RouteMCPTests AgentBurnSnapshotTests AgentRouteSnapshotTests BurnMCPTests MCPAccountContractTests MCPServerMemoryTests MCPServerTests MCPServerErrorTests MCPServerProcessTests MCPServerExchangeMatrixTests WP4MCPTests StatusFormattingTests AgentSnapshotWriterTests AgentSnapshotAccountSchemaTests GuardProcessTests ReviewSingleProviderGuardTests UtilizationCacheTests AgentRecommendationEngineTests ExpiringHeadroomTests BurnEngineTests BurnEligibilityTests BurnNotificationTests BurnViewModelTests BurnBoardTests BurnCopyTests MaxxerMathTests AgentRecommendationAccountTests AgentRecommendationReasonTests"
set --
for e_class in $e_classes; do set -- "$@" "-only-testing:AIUsageDashboardCoreTests/$e_class"; done
xcodebuild test -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-fix "$@"
```

From the worktree root (exit 0):

```sh
BASE_REF=b623ef4 bash .claude/gates/run-all.sh fast
```

E-fix-r2-fast.log ends `[run-all] ALL GATES GREEN`. Both round-2 commits were inspected by the diff gates; working tree clean. SwiftFormat and SwiftLint remain unavailable and their optional gates skipped.

Final security scan: `VERDICT: PASS`, HEAD `d002dc2dbb77`, 0 uncommitted paths, no FLAG or GAP. Log: E-fix-r2-secscan-final.log. `git diff --check b623ef4..HEAD` passed. All logs are under `/Users/abhayp/Library/Developer/TokeiWork/`.

No public schema, cache field, provider API, UI layout or dependency changed this round. S6 remains deferred as instructed. Full suite, Release build/performance remeasurement, cross-model review and release integration remain with the orchestrator. Earlier performance numbers are not measurements of this final HEAD.

All three command terminals from round 2 completed and were removed. Listener inspection found no remaining Tokei/test/proof listeners. Lessons recorded for identity-based expiry exclusion and per-clause explanation bounds.

Waits on t1d to review and integrate the two round-2 commits.
