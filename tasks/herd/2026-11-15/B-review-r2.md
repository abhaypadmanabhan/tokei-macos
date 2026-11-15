VERDICT: APPROVE

Reviewer: Claude Opus 5.5, round 2. Read-only: no edits to the worktree. Reviewed `git diff 4c3960f..HEAD` (a4f41fc, 1bff7ff,
46bb33c). Probes ran in a fresh `git archive HEAD` copy in the session scratchpad with DerivedData
`~/Library/Developer/TokeiWork/dd-review-route-probe`.

## Round 1 findings

S1 [blocker] fixed. Every score is now `elapsed - used`, and an unknown pace counts as zero elapsed. Probe P1 (Cursor monthly 80% used vs Claude weekly 0% used) -> `rows=[claude_code 100% left, cursor 20% left] rec=claude_code agent.routeTo=claude_code human.routeTo=claude_code`. Shipped `get_route_recommendation` picks Claude again, as dev did. Locked by a table case and `testS1…`.

S2 [should] fixed. Expiry priority now needs at least 25% left in the binding window (the finder's own floor). Probe P2 (Claude session expiring + weekly 80% vs empty Codex) -> `rec=codex`, Claude second with "20% left in its tightest window". Tested at 24/25/26%.

S3 [should] fixed. One filter, `RoutePlan.bindingWindows` (plan windows plus per-model, Codex shell rule), drives rows, policy peaks, trust and account eligibility. Probe P3 (Claude per-model 95%) -> get_route `rec=codex`, Claude row `avoid`; policy `routeTo=codex avoid=[claude_code]`. The tools agree. The AC1 table now also asserts that avoid rows equal `policy.avoid` (minus unknowns), and that no ready row is in the avoid set, for both policies, including cases where the policy names no target.

S4 [should] fixed. `git diff dev...HEAD -- AIUsageDashboard/TokeiCLI/MCPServer+Instructions.swift` shows only a rename to `legacyInstructions`. The 0.12.0 text is unchanged, and one 4-sentence get_route paragraph is appended. The test pins the full dev text as a prefix on all three protocol revisions, and the addition stays under 400 characters. Nothing shipped was removed.

S5 [nit] fixed. With a fresh route block and no row or unknown entry for the requested provider, the advice is now "<agent> has no flat-rate plan to route to." The stale and legacy paths are unchanged, and so are the exit codes.

S6 [nit] fixed. `verify-app.sh` (called by build-app.sh on the staged Release bundle) now runs the version gate against `Contents/Helpers/tokei` before signing or launch checks. A test with a drifted fixture helper shows it stops there.

S7, S8 declined by the orchestrator; I accept.

S9 [nit] fixed. Account headline, priority and rows all use the same `bindingWindows` filter.

## New, round 2

S10 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Utilization/RoutePlan.swift:82 This comes from the cautious unknown-pace rule I suggested. A plan with no pace (Cursor monthly) now loses to any paced plan that is under pace, even a fairly full one. Probe P5: Cursor 10% used vs Claude weekly 50% used with 3 days left -> `rec=claude_code` (agent policy also Claude). On dev, the least-used rule picked Cursor. This is defensible ("no data is not headroom") and not worse than dev on any plan near exhaustion. Leave it for now. Revisit only if Cursor users report being starved. No fix needed in this lane.

Also noted, as designed and not a finding. P6: the expiring session still ranks first when the weekly window has 26% left (just above the 25% floor). That is the boundary the fix brief asked for.

## Other checks

- Tests were strengthened, not weakened. The only removed assertions are the whole-block `< 400` length check (replaced by the prefix-plus-addition check) and two lines widened into a table case plus avoid-set comparisons.
- AccountQuotaDecision: the replacement for `hasCompleteCoverage` keeps the known-observation-time rule (`requiresObservationTime: true`). The existing AccountQuotaDecision, AgentRecommendation*, ExtraUsageRouting and TightestEligibleReading tests pass untouched.
- Policy peaks now ignore providers with no plan window. The only non-plan quota windows I found that providers emit are Claude extra usage (excluded before), Codex credits (remaining only, never a utilization) and Cline credits (all nil). So `get_route_recommendation`'s avoid list changes only through per-model windows, which already counted.

## Commands run (exit codes)

1. `cd AIUsageDashboard && xcodegen generate` -> 0
2. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-route` with `-only-testing:` for RoutePlanTests, RouteTargetPolicyTests, AccountQuotaDecisionTests, AgentRouteSnapshotTests, AgentSnapshotWriterTests, AgentSnapshotAccountSchemaTests, RouteCommandTests, RouteMCPTests, MCPServerTests, MCPServerExchangeMatrixTests, CLIVersionProcessTests, MCPAccountContractTests, MCPServerProcessTests, BurnMCPTests, UtilizationCacheTests, UtilizationEngineTests, SnapshotReaderTests, AgentSnapshotStalenessTests, AgentRecommendationEngineTests, AgentRecommendationAccountTests, ExtraUsageRoutingTests, TightestEligibleReadingTests, then `test` -> 0. `Executed 195 tests, with 0 failures`, `** TEST SUCCEEDED **`
3. Probe copy of HEAD, `-only-testing:AIUsageDashboardCoreTests/ReviewProbeTests test` -> 0. P1-P6 output quoted above. The probe prints results without asserting.
4. `git diff dev...HEAD -- AIUsageDashboard/TokeiCLI/MCPServer+Instructions.swift` -> rename plus append only.
5. `bash .claude/gates/run-all.sh fast` (worktree root) -> 0, `ALL GATES GREEN`. swiftformat and swiftlint SKIP because they are not installed. Worktree clean.

## Not checked

- `verify-app.sh` on a real built Tokei.app (only its process test ran). No live-snapshot rerun. The installed app was not launched or touched.
- The full suite, secscan, prove-red and the work log belong to the orchestrator.
