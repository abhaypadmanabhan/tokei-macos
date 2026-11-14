VERDICT: CHANGES

Review r1 of WP-A (branch `patch/2026-11-14/burn-engine`, head e797548, base a4a8894). Reviewer: Claude Opus 5.5.
Brief sha256 verified (f9af59c2…12d7e). Author's 216 targeted tests pass for me too; the findings below are cases those
tests do not cover. Repros ran in a scratch copy of `AIUsageDashboard/` outside the repo (source in the appendix).

## Findings

S1 [blocker] AIUsageDashboard/AIUsageDashboardApp/Core/Game/BurnEngine.swift:46 A record held by the current day, week or month fires `.record` again on every refresh that grows it. Today's value, this week's total and this month's multiple go up all day, so on a record day every refresh is a new "New record" moment. The nudge key at BurnNudges.swift:67 includes the value, so each one is a new notification. On a record day the two "New record" notifications use up the daily cap of 2. On a record week or month they use it up every day until the period ends, so the use-it-or-lose-it nudge, the main nudge, never gets a slot (AC4 "emits one moment once", AC9, answer 3 "quiet"). The same path fires for past days when a pricing-table update re-prices history. Fix: emit `.record(kind)` only when the candidate's period is the current one (today, this week, this month, the live streak) and the stored record's `achievedAt` is an earlier period. Growth within the same period updates the value silently. For `longestStreak`, set `achievedAt` to the run's first day (BurnAchievements.swift:46) so one run gives one moment. Key the nudge as `record|kind|achievedAt` without the value. Update `testRecordsSeedSilentlyBeatOnceAndKeepTheirDates` and `testSavedComputesWithoutMomentsNudgesOrChangingDurableStateThenLiveUpdates`: both "beat" a record that today itself seeded, so beat an earlier day instead, and add a growth-in-same-period → no moment case.
  Repro: `xcodebuild … -only-testing:AIUsageDashboardCoreTests/ReviewReproTests` (scratch copy) ->
  `REPRO_S1 refresh1 moments=[record(bestDay), record(bestWeek), record(bestMonthMultiple)]`
  `REPRO_S1 refresh2 moments=[record(bestDay), record(bestWeek), record(bestMonthMultiple)]` (today 2.5M → 2.6M tokens)
  `REPRO_S1 day2 todayUSD=Optional(0.2) moments=[record(bestWeek), record(bestMonthMultiple)]`
  `REPRO_S1 day2 notifications=["New record: Best week. …", "New record: Best month. …"]` (a 62%-unused Codex window resetting in 40 min, evaluated an hour later that day, is not sent)

S2 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Notifications/BurnNudges.swift:24 The once-per-window key is `ExpiringHeadroom.id`, which contains the reset time in whole seconds. Reset times jitter between readings: CodexJSONLParser.swift:840 falls back to event time + `resets_in_seconds`, and commit 7c62da0 ("Warn once per quota window despite reset-time jitter") fixed the same thing for predictive warnings. A one-second jitter makes the same window a new instance, so it is nudged twice and uses up the cap (AC9 "once per window instance"). Fix: reuse `PredictiveQuotaWarning.Key` and its `suppresses(_:now:)`, keyed by provider, account and bucket, with the stored reset honoured while it is still in the future or within `resetTolerance`. Add a test with 1 s and 10 min jitter → one nudge, and the next real window → one more.
  Repro: same command -> `REPRO_S2 notifications=2 ["Codex 5-hour window: 62% left, resets in 41 min. …", "Codex 5-hour window: 62% left, resets in 37 min. …"]`

S3 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Game/BurnWindowOutcomes.swift:20 Outcomes are grouped by the exact reset `Date`, so the same jitter splits one window into one "outcome" per reading. Each of those has an early reading as its "final" used %. This inflates `recentWindows` and `leftOnTablePercent`, and keeps Nothing left locked: its minimum over the week always sees an early low reading (AC6, AC7). Fix: within one series (provider, account, type, bucket), merge samples whose resets are within `PredictiveQuotaWarning.Key.resetTolerance` into one instance. The latest reset wins, and the final reading is the last sample before it. Add the repro below as a test → 1 outcome at 95%.
  Repro: same command -> `REPRO_S3 recentWindows=3 finals=[10.0, 50.0, 95.0] leftOnTable=Optional(48.33)` for one window that ended at 95% (expected 1 outcome, 5% left)

S4 [should] AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel+Burn.swift:26 The view model never passes `hiddenProviders`. The engine therefore keeps quota samples of providers hidden in Overview: a hidden Codex still feeds `recentWindows`, the left-on-table share, and the Ran it dry / Full week / Nothing left badges, while today, the leaderboard and expiring correctly drop it. Fix: pass `hiddenProviders: hiddenProviders` (make that property internal) and add a VM test with a hidden provider's samples.
  Repro: same command -> `REPRO_S4 hiddenCodex leaderboard=["claude_code"] recentWindows=["codex"] leftOnTable=Optional(80.0)`

S5 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Notifications/NotificationEngine.swift:129 Burn asks for authorization with `[.alert]` only; threshold and predictive warnings ask for `[.alert, .sound]` and send sound. If a new user's first prompt comes from burn, later warnings may arrive silent: the system prompts only once, and how it handles options added later is unverified here (reading). Fix: request `[.alert, .sound]`; burn stays quiet through `sound: false` on each request.

S6 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel+Burn.swift:42 `refresh()` and the auto-sync `for await` loop now wait for the whole burn task, including `notifyBurn`. While a first-time notification permission prompt is unanswered, `isLoading` (the menu-bar spinner) stays on and later live updates queue behind it. SyncEngine.refreshAll already awaits the threshold prompt the same way, so this is a nit (reading). Fix: after publishing and saving, start `notifyBurn` in its own Task that `applyLive` does not await.

S7 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel+Burn.swift:38 If a newer refresh lands between `save` and `notifyBurn`, the stored state already holds the new badge or record. The newer evaluation then has no moment, so that notification is lost (reading; rare). Fix: once `save` has succeeded, notify that evaluation's moments regardless of the generation check.

S8 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Analytics/UsageAnalytics+BurnValue.swift:7 This file is a second copy of Maxxer's month-value rule, including its hard-coded legacy reference models, and BurnEngine.swift `tier(for:)` copies `MaxxerValueEngine.tier`. Parity tests hold them together today, but two copies will drift. Fix (orchestrator, after merge; Core/Maxxer was outside this lane): make Maxxer's helpers internal and call them from here.

S9 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Game/BurnHistory.swift:33 Under §7, Burn's today USD is the Cost view's today over plan providers only. AC2's "never disagree" no longer holds whenever Cline, opencode or Gemini, or an unplanned provider once some plans are set, has usage today. That is intended. Note for WP-C and the orchestrator: label it as plan burn, never as the Cost number.

S10 [nit] AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel+Burn.swift:30 `burn` is reassigned on every refresh even when only `generatedAt` changed. That is one extra `objectWillChange` and render pass on the main actor per refresh. Fix: skip the assignment when the snapshot is equal apart from `generatedAt`.

S11 [nit] AIUsageDashboard/Tests/GameTests/BurnEngineTests.swift:176 The timing test asserts the 50 ms budget itself in a Debug build: the author measured 24 ms, I measured 36 ms while other lanes were building. That risks a flaky failure in the integration full suite; §5 AC11 asked for "a generous bound". Fix: assert something like < 250 ms and keep printing the measured value.

Checked and fine: purity and fixed-clock UTC/LA DST tests, streak gap / at-risk / Feb–Mar boundary, token-median window (30 days,
today excluded), first-run seeding (no moments, saved path neither saves nor notifies), the persisted 2-per-day cap and per-key
delivery across engine restarts, burn and master switches (unset = on), no credit/overage wording, horizons 60 min / 6 h and
the ≥40% threshold, BurnStateStore 0600 + changed-bytes-only + corrupt/future-version quarantine without overwrite, heavy work
in `Task.detached`, eligibility applied before history, quota outcomes and plan sums (§7 fallback set exact), tier thresholds
equal to Maxxer's.

## Commands run (exit codes)

1. `shasum -a 256 /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/A-review.brief.md` -> exit 0, matches f9af59c2…12d7e.
2. `cd AIUsageDashboard && xcodegen generate` (worktree) -> exit 0.
3. `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-a -only-testing:AIUsageDashboardCoreTests/{BurnBadgeTests,BurnEligibilityTests,BurnEngineTests,BurnStateStoreTests,ExpiringHeadroomTests,BurnNotificationTests,NotificationEngineTests,NotificationReviewTests,PredictiveNotificationTests,BurnViewModelTests,LowPowerSyncTests,DashboardViewModelAnalyticsTests,DashboardViewModelUtilizationTests,QuotaPaceTests,TightestEligibleReadingTests,UtilizationCacheTests,UtilizationEngineTests,MaxxerChipStatTests,MaxxerLifetimeTests,MaxxerMathTests,MaxxerValueEngineTests,PlanPresetTests,WP1MaxxerTests,OverviewCostTests} test` (one invocation, 24 `-only-testing` flags) -> exit 0, `Executed 216 tests, with 0 failures`, `BURN_TIMING 92 days x 8 providers: 0.036299 seconds`.
4. `BASE_REF=dev bash .claude/gates/run-all.sh fast` (worktree root) -> exit 0, ALL GATES GREEN. format and lint print SKIP (tools not installed) but the summary counts them as PASS; that was already so before this branch.
5. Scratch repro: `rsync` of `AIUsageDashboard/` (without the xcodeproj) plus `THIRD_PARTY_NOTICES.md` into `/private/tmp/claude-501/-Users-abhayp-src-tokei-worktrees-2026-11-14-burn-engine/1153481f-4c2b-4dad-b7fb-576b5d44fa15/scratchpad/repro/`, appendix file added as `Tests/GameTests/ReviewReproTests.swift`, `xcodegen generate` -> exit 0, `xcodebuild … -derivedDataPath ~/Library/Developer/TokeiWork/dd-review-a-repro -only-testing:AIUsageDashboardCoreTests/ReviewReproTests test` -> exit 0, `Executed 4 tests, with 0 failures` (the repros print rather than assert; the REPRO lines are quoted above).
6. `git status --short` (worktree) -> exit 0, clean. Nothing edited, committed or pushed; the app was not launched or copied.

Not checked, since these need the built app: on-screen moment celebrations (whether S1 shows "New record" on every refresh in the Burn
view), a real notification and the first permission prompt (S5, S6), the Settings switch, and the menu-bar spinner while a prompt is open.

## Appendix: repro tests (scratch only, never in the repo)

```swift
import XCTest
import os
import UserNotifications
@testable import AIUsageDashboardCore

final class ReviewReproTests: XCTestCase {
    func testS1RecordRefiresAsCurrentPeriodGrows() async throws {
        let f = BurnFixtures() // Mon 2026-03-09 15:00 UTC, plan Codex $31 -> goal $1/day.
        let seed = f.evaluate([f.snapshot(days: [-3: 2_000_000])])
        let a = f.evaluate([f.snapshot(days: [-3: 2_000_000, 0: 2_500_000])], state: seed.state)
        let b = f.evaluate([f.snapshot(days: [-3: 2_000_000, 0: 2_600_000])], state: a.state)
        print("REPRO_S1 refresh1 moments=\(a.snapshot.moments)")
        print("REPRO_S1 refresh2 moments=\(b.snapshot.moments)")
        let g = BurnFixtures(day: 10)
        let day2 = g.evaluate([g.snapshot(days: [-4: 2_000_000, -1: 2_600_000, 0: 200_000])], state: b.state)
        print("REPRO_S1 day2 todayUSD=\(String(describing: day2.snapshot.today.valueUSD)) moments=\(day2.snapshot.moments)")
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = ReproClock(g.now)
        let center = ReproCenter()
        let engine = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        await engine.evaluateBurn(day2.snapshot, calendar: g.calendar)
        clock.set(g.now.addingTimeInterval(3_600))
        let window = ExpiringHeadroom(providerID: .codex, providerName: "Codex", windowType: .fiveHour, bucketKey: "five",
                                      usedPercent: 30, resetAt: clock.now().addingTimeInterval(40 * 60),
                                      observedAt: clock.now(), confidence: .providerReported)
        await engine.evaluateBurn(with(day2.snapshot, expiring: [window], moments: []), calendar: g.calendar)
        print("REPRO_S1 day2 notifications=\(await center.bodies)")
    }

    func testS2JitteredResetNudgesTheSameWindowTwice() async throws {
        let f = BurnFixtures()
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = ReproClock(f.now)
        let center = ReproCenter()
        let engine = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        let reset = f.now.addingTimeInterval(41 * 60)
        func window(_ reset: Date) -> ExpiringHeadroom {
            ExpiringHeadroom(providerID: .codex, providerName: "Codex", windowType: .fiveHour, bucketKey: "five",
                             usedPercent: 38, resetAt: reset, observedAt: clock.now(), confidence: .providerReported)
        }
        let empty = BurnSnapshot.empty(now: f.now, calendar: f.calendar)
        await engine.evaluateBurn(with(empty, expiring: [window(reset)], moments: []), calendar: f.calendar)
        clock.set(f.now.addingTimeInterval(5 * 60))
        await engine.evaluateBurn(with(empty, expiring: [window(reset.addingTimeInterval(1))], moments: []), calendar: f.calendar)
        let sent = await center.bodies
        print("REPRO_S2 notifications=\(sent.count) \(sent)")
    }

    func testS3JitteredResetSplitsOneWindowIntoManyOutcomes() {
        let f = BurnFixtures()
        let reset = f.day(-1)
        let samples = [
            f.sample(used: 10, reset: reset, sampledAt: reset.addingTimeInterval(-4 * 3_600)),
            f.sample(used: 50, reset: reset.addingTimeInterval(1), sampledAt: reset.addingTimeInterval(-2 * 3_600)),
            f.sample(used: 95, reset: reset.addingTimeInterval(2), sampledAt: reset.addingTimeInterval(-600))
        ]
        let result = f.evaluate([f.snapshot(days: [0: 1_000_000])], samples: samples).snapshot
        print("REPRO_S3 recentWindows=\(result.recentWindows.count) finals=\(result.recentWindows.map(\.finalUsedPercent)) " +
              "leftOnTable=\(String(describing: result.leftOnTablePercent))")
    }

    @MainActor
    func testS4HiddenProviderWindowsStillCountInTheViewModel() async throws {
        let f = BurnFixtures()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = directory.appendingPathComponent("preferences").path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sampleClock = OSAllocatedUnfairLock(initialState: f.now.addingTimeInterval(-2 * 3_600))
        let output = directory.appendingPathComponent("output")
        let quota = QuotaSeriesStore(now: { sampleClock.withLock { $0 } }, directory: output)
        let ended = QuotaWindow(providerID: .codex, type: .fiveHour, used: 20, limit: 100,
                                resetAt: f.now.addingTimeInterval(-3_600), confidence: .providerReported,
                                source: "repro", bucketKey: "five")
        await quota.append(from: [f.snapshot(.codex, days: [0: 1_000_000], windows: [ended])])
        let store = UsageStore(directory: output)
        let sync = SyncEngine(registry: ProviderRegistry(providers: []), store: store, quotaSeriesStore: quota,
                              agentSnapshotWriter: AgentSnapshotWriter(directory: output),
                              watcher: FileWatcher(paths: [directory.appendingPathComponent("input")]),
                              evaluateThresholds: { _ in })
        let model = DashboardViewModel(syncEngine: sync, store: store, calendar: f.calendar, now: { f.now },
                                       burnStateStore: BurnStateStore(directory: output), quotaSeriesStore: quota,
                                       burnDefaults: defaults, burnPricing: { f.pricing }, notifyBurn: { _, _ in })
        defaults.set(true, forKey: "provider_hidden_codex")
        model.snapshots = [f.snapshot(.codex, days: [0: 1_000_000]), f.snapshot(.claudeCode, days: [0: 1_000_000])]
        await model.recomputeBurn(saved: false)
        print("REPRO_S4 hiddenCodex leaderboard=\(model.burn.leaderboard.map(\.providerID.rawValue)) " +
              "recentWindows=\(model.burn.recentWindows.map(\.providerID.rawValue)) " +
              "leftOnTable=\(String(describing: model.burn.leftOnTablePercent))")
    }

    private func with(_ s: BurnSnapshot, expiring: [ExpiringHeadroom], moments: [BurnMoment]) -> BurnSnapshot {
        BurnSnapshot(generatedAt: s.generatedAt, today: s.today, streak: s.streak, expiring: expiring, records: s.records,
                     leaderboard: s.leaderboard, badges: s.badges, recentWindows: s.recentWindows, tier: s.tier,
                     monthValueMultiple: s.monthValueMultiple, moments: moments)
    }
}

private final class ReproClock: Clock, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date())
    init(_ date: Date) { lock.withLock { $0 = date } }
    func set(_ date: Date) { lock.withLock { $0 = date } }
    func now() -> Date { lock.withLock { $0 } }
}

private actor ReproCenter: UserNotificationCenter {
    private(set) var bodies: [String] = []
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func add(request: NotificationRequest) async throws { bodies.append(request.body) }
}
```
