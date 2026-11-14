STATUS: READY

# WP-A result — burn engine and nudges

All 11 numbered acceptance-check groups and the §7 Burn eligibility decision pass. Seven implementation commits are final on `patch/2026-11-14/burn-engine`; the worktree is clean. Final targeted run: 225 tests, zero failures. Security scan: VERDICT: PASS, no FLAG/GAP lines.

## §7 decision implemented

Read the orchestrator’s 01:08 Burn eligibility decision from the MAIN checkout at `/Users/abhayp/src/tokei-macos/tasks/patch-bibles/2026-11-14.md`, as explicitly requested. The original attribution blocker is resolved by that decision.

`BurnEligibility(monthlyPlanUSD:)` is the single shared boundary. Finite positive configured monthly costs define the eligible provider set. If none are configured, exactly `claudeCode`, `codex`, `cursor`, `antigravity`, and `copilot` count. Cline, OpenCode and Gemini do not count without an explicit plan. Any provider with an explicit plan counts, as requested. Hidden or absent configured providers never reactivate fallback eligibility.

BurnEngine applies this boundary before building daily history or reading quota outcomes. Today USD/tokens, goals, token-median fallback, streak, records, tier/multiple, leaderboard, every badge (including Fleet), recent windows and expiring opportunities all use that same eligible set. The badge-specific first-burn provider rule was removed. Pricing itself still uses the Cost view path, now over the eligible visible provider subset prescribed by §7.

Accepted limit from §7: Claude extra-usage tokens cannot be split out of Claude Code daily totals. Burn nudges still name only plan windows with unused capacity and never encourage paid overage. UI/release-note wording for this accepted limit belongs to the orchestrator/UI lane; this lane changed no UI or release files.

## Brief and scope

Original brief hash verified before reading:
```text
79b1d7547e048b10338e03af5b76ac72140dbd12d0042505f2a2d32af5a4bb2e  /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/A-burn-engine.brief.md
```

All code/test writes stay inside the assigned worktree and WP-A ownership. This result file is the brief’s only checkout-write exception. No provider, parser, UI, CLI, network or agent files were changed.

Build preparation (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodegen generate
```
```text
Created project at /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-engine/AIUsageDashboard/AIUsageDashboard.xcodeproj
```

Each AC repeats the same exact final invocation. It ran ONCE after the Review r1 fixes across all Game/Notification/Sync/Utilization/Maxxer test classes plus OverviewCostTests. The exact argv is retained in `.scratch/r1-final-command.txt`, output in `.scratch/burn-r1-final.log`. No whole-suite or real-provider-log run was used.

## AC 1 — Pure evaluation

BurnEngine takes value inputs, an explicit clock, calendar, pricing table, quota samples and durable state. No preferences, disk access or notification delivery occur inside the evaluator. UTC and America/Los_Angeles fixtures cross the spring DST change.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testPureFixedClockUTCAndDSTAndCostViewParity]' passed (0.002 seconds).
```

## AC 2 — Goal and today

Apply BurnEligibility and the Overview hidden set first. Eligible visible monthly plan costs are summed and divided by this calendar month’s length. Today USD uses UsageAnalytics.costSummary over that same subset; unknown pricing stays unknown. With no configured plan, the token target is the median positive eligible day in the preceding 30 calendar days, excluding today; no eligible history means no goal. Progress is burned / target. Direct tests prove excluded API providers cannot affect today, goal, fallback history or the Cost-parity fixture.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testMissingPricesStayUnknown]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testPureFixedClockUTCAndDSTAndCostViewParity]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testTokenMedianExcludesTodayZerosOldHistoryAndHiddenProviders]' passed (0.001 seconds).
```

## AC 3 — Streak

Compute consecutive goal-hit calendar days ending today when hit, otherwise yesterday. A gap stops the run. Use each historical month’s day count for dollar goals; keep the maximum stored longest streak. Covers at-risk state and February/March boundary.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testStreakGapAtRiskMonthBoundaryAndPersistedLongest]' passed (0.001 seconds).
```

## AC 4 — Records

Best day, calendar week, month multiple and longest streak persist with their achievement dates. First evaluation seeds silently. A record moment requires a current period beating a record from an earlier period; same-period growth and historical repricing update values silently. Longest-streak achievement dates are the run’s first day. Units reseed silently when changing between tokens and dollars. Sorted summation prevents floating-point order from inventing a beat.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testBestWeekUsesCalendarWeekAndTokenFallback]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testFirstUsageAfterAnEmptySeedSetsARecordSilently]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testFractionalMultiProviderRecordsDoNotRefireOrRewriteOnIdenticalInputs]' passed (0.085 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testRecordsSeedSilentlyBeatOnceAndKeepTheirDates]' passed (0.002 seconds).
```

## AC 5 — Leaderboard

Use this calendar’s week boundary, BurnEligibility plus the Overview hidden-provider set, descending USD then tokens and stable provider tie-breaks. Unpriced usage keeps nil USD. Explicit-plan fixtures and fallback fixtures both prove excluded providers never enter the leaderboard.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testLeaderboardUsesCalendarWeekVisibleProvidersUSDThenTokens]' passed (0.001 seconds).
```

## AC 6 — Window outcomes

Add an all-account quota-series read API. Group by provider, account, type and bucket, merging reset estimates within PredictiveQuotaWarning.Key.resetTolerance (ten minutes). The latest reset estimate wins; retain the final sample strictly before that reset. Recent outcomes use the last seven calendar days; paid credits, per-model and lifetime windows never qualify. Legacy nil-account rows cannot become an extra account when owned rows exist.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testWindowOutcomesLastReadingBeforeResetNeverMixAccountsOrPaidWindows]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnStateStoreTests testAllQuotaSamplesIncludesBothAccountsInsteadOfOnlyHeadline]' passed (0.003 seconds).
```

## AC 7 — Badges

Table-test all 13 rules at the threshold and immediately below, persisted first-unlock timestamps, no re-locking and no first-run moments. Every badge consumes the already-eligible history, including First burn, token-day badges and Fleet. First burn now uses the same plan-provider fallback decision as all other burn values; there is no quota/price-specific second eligibility rule. Session windows count as five-hour windows. Nothing left needs a nonempty completed calendar week and every observed account/window at least 80%.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnBadgeTests testBadgeUnlockMomentOnceAndTimestampSurvivesHistoryLoss]' passed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnBadgeTests testEveryBadgeAtItsRuleBoundaryAndJustBelow]' passed (0.008 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnBadgeTests testNothingLeftNeedsACompletedNonemptyWeekAndAllAccounts]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnBadgeTests testSessionIsAFiveHourWindowAndFirstBurnNeedsAPlanNotItsPrice]' passed (0.001 seconds).
```

## AC 8 — Tier

Use Maxxer’s paired-provider value rule and existing pricing/reference-model baselines through a value-only Analytics helper. Test all tier boundaries against MaxxerValueEngine.scorecard; tier-up moments require an increase within the same stored month, never first run or a month rollover.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testTierMatchesMaxxerAndOnlyRisesWithinSameMonth]' passed (0.005 seconds).
```

## AC 9 — Nudges

NotificationEngine.evaluateBurn prioritizes one expiring plan window, then badge/record moments; all share a persisted cap of two per local day. Default-on burn and master switches are both honored. Once per provider/account/bucket window instance using PredictiveQuotaWarning.Key.suppresses for jitter tolerance. Record notification identity is kind + achievedAt, without the growing value. Authorization asks for alert and sound together; each burn delivery remains silent. Authorization denial/failure does not consume the cap. No credit/overage wording. No live notification was sent; the orchestrator owns that proof.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testBadgeAndRecordEachNotifyOnceWithinCap]' passed (0.005 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testBurnAndMasterSwitchesSuppressWithoutAuthorizationAndUnsetEnables]' passed (0.007 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testConcurrentEvaluationsCannotExceedCap]' passed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testDenialAndFailedDeliveryDoNotConsumeCap]' passed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testExactHorizonAndUnusedThresholdsAndPaidWindowsNeverNotify]' passed (0.011 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testExpiringFirstThenBadgeInsideOneQuietCapAndNoDuplicatesAfterRestart]' passed (0.005 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testPerWindowInstanceIncludesAccountBucketAndReset]' passed (0.006 seconds).
```

## AC 10 — Persistence

BurnStateStore writes versioned burn-state.json through SecureFileWriter. Permission 0600 is verified. Identical bytes do not replace the inode or modification date. Corrupt/future-version bytes move to .corrupt; existing quarantines are preserved. If quarantine fails, writes pause rather than overwrite the bad file.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnStateStoreTests testCorruptAndFutureVersionArePreservedThenStartFresh]' passed (0.005 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnStateStoreTests testDoesNotReplaceAnOlderCorruptFile]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnStateStoreTests testRoundTripPrivateModeAndUnchangedBytesDoNotWrite]' passed (0.003 seconds).
```

## AC 11 — Wiring and cost

Both applyLive paths (manual and automatic refresh) and loadSavedSnapshots set burn. Saved evaluation emits no moments, sends no nudges and cannot change durable achievements. Heavy evaluation/pricing runs in Task.detached; a test observes the pricing callback off the main thread. Evaluations serialize with writes, and a generation guard rejects superseded work. The 92-day/eight-provider measured evaluation prints its elapsed time. Per accepted S11, its Debug assertion is below 250 ms. Hidden providers are passed explicitly for quota history. Notification delivery runs in a separate Task; equal content apart from generatedAt does not republish burn.

Check command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testNinetyTwoDaysEightProvidersWithinGenerousTimingBound]' passed (0.051 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testAutoSyncUpdateAlsoSetsBurn]' passed (0.021 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testHiddenProviderMatchesOverviewAndNoSavedTodayInvented]' passed (0.012 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testRefreshSetsBurnAndPersistsOffMainAndNotifiesFromLive]' passed (0.007 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testSavedComputesWithoutMomentsNudgesOrChangingDurableStateThenLiveUpdates]' passed (0.010 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testSupersededEvaluationCannotSeedStateOrNotifyOldData]' passed (0.030 seconds).
BURN_TIMING 92 days x 8 providers: 0.024995333 seconds
```

## §7 eligibility regression proof

Before the rule was changed, the six behavior tests reproduced the issue with 95 failing assertions. The first two rule-shape tests were added after the shared type existed. After the implementation, all eight eligibility tests pass. Comparing whole BurnSnapshots proves excluded usage cannot alter any number; a refresh also asserts unchanged durable state and no new moments. Explicit-plan acceptance is exercised for every ProviderID.

Before command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests test
```
Exact failure lines (`.scratch/burn-eligibility-before.log`):
```text
	 Executed 6 tests, with 95 failures (0 unexpected) in 1.108 (1.110) seconds
	 Executed 6 tests, with 95 failures (0 unexpected) in 1.108 (1.111) seconds
** TEST FAILED **
```

Final command:
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact pass lines:
```text
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testAConfiguredPlanMakesEachProviderCountAndReplacesTheFallback]' passed (0.005 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testCostParityUsesTheSameEligibleProviderSubset]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testFleetAndTokenBadgesCountOnlyEligibleProviders]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testHiddenOrMissingConfiguredProviderDoesNotReenableFallback]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testNoConfiguredPlanUsesExactlyTheFiveSubscriptionProducts]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testOnlyFinitePositivePlanCostsConfigureEligibility]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testUnplannedAPIProvidersCannotChangeAnyBurnNumber]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEligibilityTests testUnplannedAPIProvidersCannotSupplyTokenFallbackHistory]' passed (0.001 seconds).
```

## Final verification

```text
	 Executed 225 tests, with 0 failures (0 unexpected) in 1.000 (1.059) seconds
	 Executed 225 tests, with 0 failures (0 unexpected) in 1.000 (1.059) seconds
** TEST SUCCEEDED **
```

Fast gates (assigned worktree root; `.scratch/r1-fast-gates.log`):
```sh
BASE_REF=dev bash .claude/gates/run-all.sh fast
```
```text
PASS  preflight
PASS  no-secret
PASS  no-large-artifact
PASS  no-uncommitted
PASS  cli-version-sync
PASS  format
PASS  lint
[run-all] ALL GATES GREEN
```

Formatting and lint tools are absent; those gates explicitly skipped. No dependency was installed. The follow-up target compile has no warning naming a new Burn source/test or changed DashboardViewModel/Analytics source. No claim of a warning-free whole project is made.

Security scan:
```sh
/Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-engine
```
```text
VERDICT: PASS
repo 2026-11-14-burn-engine head 526be3668dc1 base origin/dev (3fd3e98fd95c): 8 commits, 0 uncommitted paths
report: /Users/abhayp/src/tokei-macos/.git/secscan/526be3668dc1b0c56c33aba4b80753b1d81842a7.txt
```
No FLAG or GAP lines were emitted.

## Commits

```sh
git log --oneline dev..HEAD
```
```text
526be36 fix: keep burn refresh independent of notification delivery
7d875a8 fix: announce burn records and jittered windows once
e797548 fix: apply shared plan eligibility to every burn calculation
1395928 feat: update burn state after saved and live dashboard refreshes
a16089e fix: keep burn records stable and honor plan badge boundaries
f718428 feat: persist burn achievements and send capped quiet nudges
3448f29 feat: compute burn goals, streaks and achievements from local history
```

## Additive APIs and contract notes

- No existing BurnSnapshot/BurnDay/BurnBadge/ExpiringHeadroom declaration was renamed, removed or edited.
- New public `BurnEligibility(monthlyPlanUSD:)` with immutable `providers` and validated `monthlyPlanUSD` values. This shared rule has no preferences or clock access and can be used by other burn consumers.
- New public `BurnEngine.evaluate(snapshots:monthlyPlanUSD:quotaSamples:state:now:calendar:pricing:hiddenProviders:emitMoments:) -> (snapshot: BurnSnapshot, state: BurnState)`; all inputs are values.
- New public `BurnState` and versioned Codable record representation; new `BurnStateStore` actor with `load()` and changed-byte `save(_:)`.
- New public `QuotaSeriesStore.allSamples(since:)` preserves all account identities; existing headline chart reads are unchanged.
- New public `NotificationEngine.evaluateBurn(_:calendar:)`; burn delivery keys/count persist under `burnNotificationState` in the injected defaults store.
- DashboardViewModel initializer gains defaulted injections for burn state/series stores, preferences, pricing and delivery, preserving existing call sites.
- A pure monthly-value Analytics helper mirrors Maxxer because its existing helpers are private and its public scorecard takes a defaults-backed non-Sendable store outside this lane’s edit scope. Direct parity tests compare tier and multiple against Maxxer on the same eligible snapshots. A separately scoped centralization can remove that duplication.

## Constraints added

- One eligibility boundary before all burn history/quota processing; eight tests cover subscription fallback, explicit plans, invalid costs, hidden/missing configured providers, all-number equality, Fleet/token badges, token-goal history and Cost parity.
- Stable provider/model/day summation prevents floating-point order from inventing record beats; repeat evaluation is checked 50 times. The earlier red/green logs remain in `.scratch/burn-edge-before.log` and `.scratch/burn-edge-after.log`.
- An unpriced leaderboard entry stays nil rather than a made-up zero; its original failure remains in `.scratch/burn-leader-before.log`.
- Saved snapshots cannot write achievements or send nudges; serialization and generation guards reject stale evaluation.

## Review r1 fixes

Author fixes are READY for re-review. Read the main-checkout `A-fix-r1.md` and full `A-review-r1.md`; addressed exactly S1, S2, S3, S4, S5, S6, S10 and S11. S7 (rare delivery race), S8 (Maxxer dedupe outside scope), and S9 (WP-C wording) remain declined/follow-up items as instructed. The S7 generation guard remains in place.

Failing-first proof: the nine focused behavior regressions were added before source changes; all nine failed against e797548, with 22 assertions. S11 changes only the accepted bound on the existing measurement.

Before command (cwd: assigned worktree `AIUsageDashboard/`):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnEngineTests/testRecordGrowthWithinCurrentPeriodsAndHistoricalRepricingStaySilent -only-testing:AIUsageDashboardCoreTests/BurnEngineTests/testLongestStreakRecordUsesRunStartAndCelebratesOnlyANewRun -only-testing:AIUsageDashboardCoreTests/BurnEngineTests/testJitteredResetSamplesProduceOneFinalOutcome -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests/testRecordNudgeIsOncePerPeriodDespiteValueGrowth -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests/testResetJitterSuppressesNudgesAcrossRestartButNextWindowCanNotify -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests/testBurnAuthorizesAlertAndSoundButDeliversSilently -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests/testHiddenProviderQuotaSamplesCannotAffectBurnWindowsOrBadges -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests/testNotificationPermissionCannotHoldRefreshSpinner -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests/testOnlyGeneratedAtChangeDoesNotPublishBurnAgain test
```
Exact red summary (`.scratch/burn-r1-before.log`):
```text
	 Executed 9 tests, with 22 failures (0 unexpected) in 3.109 (3.113) seconds
** TEST FAILED **
```

After command (same cwd; all targeted classes run ONCE after fixes):
```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-burn-engine -only-testing:AIUsageDashboardCoreTests/BurnBadgeTests -only-testing:AIUsageDashboardCoreTests/BurnEligibilityTests -only-testing:AIUsageDashboardCoreTests/BurnEngineTests -only-testing:AIUsageDashboardCoreTests/BurnStateStoreTests -only-testing:AIUsageDashboardCoreTests/ExpiringHeadroomTests -only-testing:AIUsageDashboardCoreTests/BurnNotificationTests -only-testing:AIUsageDashboardCoreTests/NotificationEngineTests -only-testing:AIUsageDashboardCoreTests/NotificationReviewTests -only-testing:AIUsageDashboardCoreTests/PredictiveNotificationTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelAnalyticsTests -only-testing:AIUsageDashboardCoreTests/DashboardViewModelUtilizationTests -only-testing:AIUsageDashboardCoreTests/QuotaPaceTests -only-testing:AIUsageDashboardCoreTests/TightestEligibleReadingTests -only-testing:AIUsageDashboardCoreTests/UtilizationCacheTests -only-testing:AIUsageDashboardCoreTests/UtilizationEngineTests -only-testing:AIUsageDashboardCoreTests/MaxxerChipStatTests -only-testing:AIUsageDashboardCoreTests/MaxxerLifetimeTests -only-testing:AIUsageDashboardCoreTests/MaxxerMathTests -only-testing:AIUsageDashboardCoreTests/MaxxerValueEngineTests -only-testing:AIUsageDashboardCoreTests/PlanPresetTests -only-testing:AIUsageDashboardCoreTests/WP1MaxxerTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests test
```
Exact green summary (`.scratch/burn-r1-final.log`):
```text
	 Executed 225 tests, with 0 failures (0 unexpected) in 1.000 (1.059) seconds
	 Executed 225 tests, with 0 failures (0 unexpected) in 1.000 (1.060) seconds
** TEST SUCCEEDED **
BURN_TIMING 92 days x 8 providers: 0.024995333 seconds
```

| Finding | Commit | Result |
| --- | --- | --- |
| S1 | `7d875a8; 526be36 (VM test)` | Record moments require a current day/week/month/live streak beating an earlier period. Same-period growth and repriced past periods stay silent. Longest streak achievedAt is the run’s first day. A missing earlier record seeds silently. Record nudge keys omit the value. Both named tests now seed an earlier day/month. |
| S2 | `7d875a8` | Persist and reuse PredictiveQuotaWarning.Key and suppresses. One-second and ten-minute reset jitter do not repeat a nudge across engine restarts; the next real window can notify. Adding the window-key field uses decodeIfPresent so prior daily counts are preserved. |
| S3 | `7d875a8` | Merge nearby reset estimates within a provider/account/type/bucket series. Latest reset wins; final sample before it wins. The reviewer’s three-sample repro is one 95% outcome, 5% left, with Nothing left unlocked. |
| S4 | `526be36` | Expose hiddenProviders internally and pass the captured set to BurnEngine. A hidden Codex has a real stored pre-reset sample in the VM fixture, but contributes no outcome, left-on-table number or Ran it dry badge. |
| S5 | `7d875a8` | Request [.alert, .sound] authorization. Each burn notification still has sound: false. |
| S6 | `526be36` | Start notifyBurn in its own Task after publish/save. Refresh and applyLive do not await a held notification prompt. Tests wait for their asynchronous callbacks before teardown. |
| S10 | `526be36` | Skip burn assignment when all content except generatedAt matches, while still allowing real moment/value changes to publish. The Combine subscriber receives the initial value and first refresh only. |
| S11 | `7d875a8` | Keep the measured timing line; change the existing Debug assertion to < 250 ms as accepted. This is a bound adjustment, not a deliberately slowed failing performance fixture. |

Exact per-finding test output:

### S1 — 7d875a8; 526be36 (VM test)

```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testRecordsSeedSilentlyBeatOnceAndKeepTheirDates]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testRecordGrowthWithinCurrentPeriodsAndHistoricalRepricingStaySilent]' passed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testLongestStreakRecordUsesRunStartAndCelebratesOnlyANewRun]' passed (0.001 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testRecordNudgeIsOncePerPeriodDespiteValueGrowth]' passed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testSavedComputesWithoutMomentsNudgesOrChangingDurableStateThenLiveUpdates]' passed (0.010 seconds).
```

### S2 — 7d875a8

```text
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testResetJitterSuppressesNudgesAcrossRestartButNextWindowCanNotify]' passed (0.007 seconds).
```

### S3 — 7d875a8

```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testJitteredResetSamplesProduceOneFinalOutcome]' passed (0.001 seconds).
```

### S4 — 526be36

```text
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testHiddenProviderQuotaSamplesCannotAffectBurnWindowsOrBadges]' passed (0.008 seconds).
```

### S5 — 7d875a8

```text
Test Case '-[AIUsageDashboardCoreTests.BurnNotificationTests testBurnAuthorizesAlertAndSoundButDeliversSilently]' passed (0.003 seconds).
```

### S6 — 526be36

```text
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testNotificationPermissionCannotHoldRefreshSpinner]' passed (0.018 seconds).
```

### S10 — 526be36

```text
Test Case '-[AIUsageDashboardCoreTests.BurnViewModelTests testOnlyGeneratedAtChangeDoesNotPublishBurnAgain]' passed (0.009 seconds).
```

### S11 — 7d875a8

```text
Test Case '-[AIUsageDashboardCoreTests.BurnEngineTests testNinetyTwoDaysEightProvidersWithinGenerousTimingBound]' passed (0.051 seconds).
```

R1 API/storage notes: no public contract declaration changed. Added internal BurnSnapshot.hasSameContent(as:); the notification defaults ledger gains an optional jitter-tolerant window-key set. burn-state.json schema remains version 1.

R1 gates and scan: `BASE_REF=dev bash .claude/gates/run-all.sh fast` exited 0 (format/lint explicitly SKIP because tools are absent). Security command and exact output:
```sh
/Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-engine
```
```text
VERDICT: PASS
repo 2026-11-14-burn-engine head 526be3668dc1 base origin/dev (3fd3e98fd95c): 8 commits, 0 uncommitted paths
report: /Users/abhayp/src/tokei-macos/.git/secscan/526be3668dc1b0c56c33aba4b80753b1d81842a7.txt
```
No FLAG or GAP lines were emitted. No app launch or live notification was attempted.

## Remaining proof and accepted limits

- No implementation blocker remains after the orchestrator’s §7 decision.
- Accepted §7 limit: Claude extra-usage tokens cannot be separated from Claude Code daily totals. The orchestrator/UI lane must state that limit in UI copy and release notes. No claim of per-request billing attribution is made.
- Orchestrator owns the r1 fix re-review, integration/full suite and one real notification on the built app. Tokei was never launched by this lane, as instructed.
- Historical month records use currently configured monthly costs; the contract has no plan-price history. Nothing left evaluates recorded windows in a completed calendar week; unobserved resets cannot be reconstructed.
- Quota-series retention bounds historical window evidence. No new collection/network behavior was added.
- No UI profiling, release build, deployment, signing, push or merge was attempted.
- Local proof logs stay under the assigned worktree `.scratch/`; Xcode artifacts use `~/Library/Developer/TokeiWork/dd-burn-engine`.
- No server was started; test watchers were stopped. Listener cleanup is checked before the completion marker.
- Work-log/global lesson writes remain outside this brief’s write scope. The regression tests are the lasting checks for the eligibility correction.

Rollback: leave the lane unmerged, or have the orchestrator revert its eventual A merge with `git revert -m 1 <A-merge>`. The eligibility follow-up alone is `e797548`; r1 fixes are `7d875a8` and `526be36`. No schema migration/external resource change needs undoing.

Waits on: the orchestrator for r1 fix re-review, accepted-limit wording and live notification proof.
