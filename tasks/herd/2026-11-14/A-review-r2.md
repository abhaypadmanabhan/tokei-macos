VERDICT: APPROVE

Review r2 of WP-A (branch `patch/2026-11-14/burn-engine`, head 526be36; checked `git diff e797548..HEAD`, commits 7d875a8 and
526be36). Reviewer: Claude Opus 5.5. Brief sha256 verified again (f9af59c2…12d7e). No blocker or should remains open. The
declined items are nits and their reasons are acceptable. Two new nits in the changed code are below; neither blocks the merge.

## Old ids

S1 [blocker] resolved. A record moment now needs the current day, week, month or live streak to beat a record stored from an
earlier period (`BurnEngine.isNewCurrentPeriod`). Growth inside the same period and re-pricing a past period stay silent. The
longest-streak date is now the run's first day, and the nudge key is `record|kind|achievedAt` with no value. My r1 repro on the
new code: refresh 1 gives `[record(bestDay), record(bestWeek)]` (the month record was already held by this month, so no month
moment), refresh 2 gives `[]`, day 2 gives `[]`, and day 2 now sends the Codex window nudge ("70% left, resets in 40 min")
instead of two "New record" alerts. Side effect, accepted: the very first record after an empty first run now seeds silently,
because there is no earlier record to beat (`testFirstUsageAfterAnEmptySeedSetsARecordSilently`).

S2 [should] resolved. Delivered window nudges are stored as `PredictiveQuotaWarning.Key` and checked with `suppresses`, so they
survive engine restarts, and old ledgers still decode (`decodeIfPresent`). My repro gives `notifications=1`. The author's test
covers 1 s and 10 min jitter, then the next real window.

S3 [should] resolved. Each series (provider, account, type, bucket) is sorted by reset, and resets within the 10 min tolerance
merge into one instance; the latest reset wins. My repro gives `recentWindows=1 finals=[95.0] leftOnTable=5.0`.

S4 [should] resolved. The view model passes `hiddenProviders` to the engine. My repro gives `recentWindows=[] leftOnTable=nil`
with Codex hidden. The author's VM test stores a real pre-reset sample.

S5 [nit] resolved. Burn now asks for `[.alert, .sound]`, and each burn request still sends `sound: false`.

S6 [nit] resolved. `notifyBurn` runs in its own Task, so refresh no longer waits on the permission prompt; the author's test
holds the prompt and checks that `isLoading` clears. This creates a new nit, S12.

S7 [nit] still open, declined as a follow-up (rare; reading only). Acceptable.

S8 [nit] still open, declined: Core/Maxxer is outside this lane, so the orchestrator follows up after merge. Acceptable.

S9 [nit] still open, by design: a note for WP-C to label today's value as plan burn, not the Cost number. Acceptable.

S10 [nit] resolved. The view model skips republishing when only `generatedAt` changed (`hasSameContent`). This creates a new
nit, S13.

S11 [nit] resolved. The timing test bound is now < 250 ms and it still prints the measured value: 0.0236 s in my rerun.

## New (changed code only)

S12 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel+Burn.swift:44 Notify Tasks are no longer serialized
by the burn task, so two can overlap. The later one then returns at once from the `!isEvaluatingBurn` guard
(NotificationEngine.swift:121). Moments only exist in one evaluation, so its badge or record alert is lost. This needs a refresh
to land while an earlier delivery is in flight, which in practice means while a first permission prompt is unanswered (reading;
rare). Fix (follow-up): keep the previous notify Task and await it inside the new one, or have `evaluateBurn` queue instead of
drop.

S13 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel+Burn.swift:32 Because of the S10 skip, the published
`burn.generatedAt` now means "last content change", not "last evaluation". Note for WP-C: do not render it as an "updated at"
time; use `lastSyncedAt`.

## Commands run (exit codes)

1. `shasum -a 256 /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/A-review.brief.md` -> exit 0, matches f9af59c2…12d7e.
2. `git log --oneline e797548..HEAD` and `git diff e797548..HEAD` (worktree) -> exit 0; 2 commits, 11 files.
3. `cd AIUsageDashboard && xcodegen generate` (worktree) -> exit 0.
4. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-a -only-testing:AIUsageDashboardCoreTests/{BurnBadgeTests,BurnEligibilityTests,BurnEngineTests,BurnStateStoreTests,ExpiringHeadroomTests,BurnNotificationTests,NotificationEngineTests,NotificationReviewTests,PredictiveNotificationTests,BurnViewModelTests,LowPowerSyncTests,DashboardViewModelAnalyticsTests,DashboardViewModelUtilizationTests,QuotaPaceTests,TightestEligibleReadingTests,UtilizationCacheTests,UtilizationEngineTests,MaxxerChipStatTests,MaxxerLifetimeTests,MaxxerMathTests,MaxxerValueEngineTests,PlanPresetTests,WP1MaxxerTests,OverviewCostTests} test` (one invocation, 24 `-only-testing` flags) -> exit 0, `Executed 225 tests, with 0 failures`, `BURN_TIMING 92 days x 8 providers: 0.023562084 seconds`.
5. The r1 repro file (appendix of A-review-r1.md), run in a scratch copy of the new code under `/private/tmp/claude-501/-Users-abhayp-src-tokei-worktrees-2026-11-14-burn-engine/1153481f-4c2b-4dad-b7fb-576b5d44fa15/scratchpad/repro/`: `xcodegen generate` -> exit 0; `xcodebuild … -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-a-repro -only-testing:AIUsageDashboardCoreTests/ReviewReproTests test` -> exit 0, `Executed 4 tests, with 0 failures`. The REPRO lines are quoted above.
6. `git status --short` (worktree) -> exit 0, clean. Nothing edited, committed or pushed; the app was not launched or copied.

Not checked, since these need the built app: a real nudge and the first permission prompt, the in-app moment celebrations, the
Settings switch, and whether WP-C reads `generatedAt` (S13).
