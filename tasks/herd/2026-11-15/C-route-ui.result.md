STATUS: READY

# WP-C route UI and demo data · result (Claude Opus, lane2, branch patch/2026-11-15/route-ui)

Proof media root: `~/Library/Developer/TokeiWork/proof/route-ui/` (not in git). Rig scripts in `rig/`.
Captures ran on a copy of my Debug build re-identified as `ai.padzy.tokei.demo` (own preferences, own pid);
the installed `/Applications/Tokei.app` (pid 94891) was never launched, quit or touched.

## AC 2 · Demo data (done first)
- `App/DemoFixture.swift` (`#if DEBUG`): `-TokeiProofFixture demo` builds the view model on a demo `SyncEngine`
  whose four providers (Claude Code, Codex, Cursor, Gemini) return fictional snapshots (90 days of daily, hourly and
  per-model usage; quota windows with pace). Store, quota series, burn state and agent snapshot live in
  `$TMPDIR/tokei-demo-<pid>`, so Sync now or a retry shows the demo again and nothing real is read or written.
  Settings (plan prices $100/$20/$20, visibility, live-quota toggles) go into the argument domain (never saved).
  Burn uses `BurnSnapshot.sample`; the popover pace notch uses fixed baselines.
- `-TokeiProofWindowSize WxH` fixes the dashboard frame and moves it off the pointer (hover readouts).
- Check: `DemoFixtureTests` (5): no home path, `/Users/`, `@` or user name anywhere in the fixture (reflection walk
  over every string); every screen's inputs present; route shows recommendation, runner-up and an avoid; a refresh
  stays demo; installing defaults leaves the persistent domain alone. Every proof route rendered (captures below).
- Release: `xcodebuild … -scheme AIUsageDashboardApp -configuration Release CODE_SIGNING_ALLOWED=NO build` → BUILD
  SUCCEEDED; `strings` on the Release binary: DemoFixture 0, TokeiProofFixture 0, TokeiDemoRoute 0,
  TokeiProofTickReport 0, TokeiProofRouteExpanded 0, "demo fixture" 0 (control: SecondTicker 4, RouteSuggestion 2).

## AC 3 · Website captures
`site-captures/` (index `snapshots.md`), 2x, dark, active windows, demo only; each as whole window and `-content`
(title bar cropped): popover, popover-route (open), overview-usage, overview-usage-tall (1100x940: chart, route row and
tiles; best single shot), overview-route, overview-quota, burn, value, agents, provider-claude-code,
provider-codex-route-chip. Pass 1 was sent at ~03:05 ("C captures ready"); pass 2 replaced it with the route row.

## AC 1 · "Send work here next"
- `UI/Components/RouteCopy.swift` (`RouteSuggestion`, pure, view-side helper over `RoutePlan`; no Core type changed):
  states recommend / onlyOne / none / waiting (stale) / allNearlyUsedUp, each with real copy; next two runners-up;
  spoken label. Names the window the reason is about (Codex's row carries weekly as tightest while its reason is the
  5-hour reset; helper looks the expiring window up by reset time).
- `UI/Components/RouteNextView.swift`: popover (under today's tokens) and Overview (under the chart, every lens);
  "Show the next 2"; VoiceOver reads "Send work here next: Codex, 5-hour window. Use this plan…"; Reduce Motion drops
  the disclosure animation; plain ink, no new accent.
- Chips: Overview tile ("Most room" → "Send here next") and drill-in chip ("Route work here" → "Send work here next")
  now read `viewModel.routeSuggestion.target`, i.e. RoutePlan's recommendation, so chip, row and `get_route` agree.
  The two `visibleUtilizations` helpers that only fed the old human-policy chip were removed. Behaviour change to flag:
  the chip now shows whenever the row recommends (no 15-point spread gate).
- Check: `RouteSuggestionTests` (12). Red on old logic: with the window lookup undone,
  `testTheRowNamesTheWindowItsReasonIsAbout` fails `("Optional("Weekly")") is not equal to ("Optional("5-hour")")`.
  Captures: `route/` (index `snapshots.md`) incl. every state.

## AC 4 · Nothing ticks when hidden
- Found: the strip's `Timer.publish(…).autoconnect()` fired every second for the app's life (only its effect was
  gated), and "visible" was app-wide, so with only the popover open the closed dashboard's retained graph kept the
  strip clock and the drill-in's 1 Hz `TimelineView` countdown running.
- Fix: `WindowVisibilityMonitor.dashboardOnScreen` (the dashboard window's own occlusion; re-read on occlusion
  change, close and become-key; starts true so it can never strand a blank dashboard); `SecondTicker` owns a Timer only
  while visible; drill-in countdown static while hidden. Burn's `.everyMinute` timelines were already gated.
- Check: `SecondTickerTests` (3). Measured on the built Debug app (`rig/tick-report.sh`, `timers/tick-report-after.txt`):
  ```
  dashboard-open seconds=5 fires=5 dashboardVisible=true popoverOpen=true appVisible=true
  dashboard-hidden-popover-open seconds=10 fires=0 dashboardVisible=false popoverOpen=true appVisible=true
  dashboard-back seconds=5 fires=4 dashboardVisible=true popoverOpen=true appVisible=true
  dashboard-closed seconds=5 fires=0 dashboardVisible=false popoverOpen=true appVisible=true
  dashboard-reopened seconds=5 fires=5 dashboardVisible=true popoverOpen=true appVisible=true
  ```
  (fires>0 after reopen also proves the dashboard rebuilt rather than staying on its hidden fill.) Not run on WP-A's
  harness: it measures with no window open, where the shell was already collapsed; the gain is in the popover-open case.

## AC 5 · Light/dark, Reduce Motion
`route/*-{dark,light}.png`, `pass2/*-{dark,light}.png`: identical content by design (app forces dark). Reduce Motion:
`route/popover-route-reduce-motion.png` (`-TokeiReduceMotion YES`) and `withAnimation(reduceMotion ? nil : …)` in code.

## Commands
- `xcodegen generate`; Debug app build `-derivedDataPath ~/Library/Developer/TokeiWork/dd-route-ui` → BUILD SUCCEEDED
  (only the two existing `plotAreaFrame` deprecation warnings).
- Core targeted: DemoFixtureTests RouteSuggestionTests SecondTickerTests WP4LabelMotionTests NoEyebrowTextTests
  RoutePlanTests RouteTargetPolicyTests BurnBoardTests MenuBarLabelModelTests SavedSnapshotLaunchTests
  AgentRouteSnapshotTests → `Executed 80 tests, with 0 failures` `** TEST SUCCEEDED **`.
- `bash .claude/gates/run-all.sh fast` → ALL GATES GREEN (format and lint SKIP: swiftformat/swiftlint not installed).
- `~/agent-kit/bin/secscan` → VERDICT: PASS.

## Commits (`git log --oneline dev..HEAD`)
17027c2 docs(features): route row, demo data, hidden clocks; captures avoid the pointer
b3857dd fix(timers): nothing ticks while the dashboard is off screen
42298d1 feat(route): "Send work here next" in the popover and Overview
0563f51 Merge branch 'dev' into patch/2026-11-15/route-ui   (WP-A; conflict in AIUsageDashboardApp.swift kept both)
daab397 feat(proof): publishable demo data for captures (-TokeiProofFixture demo)

## Contract additions (all additive, UI/App side)
`RouteSuggestion`, `RouteNextView`, `DashboardViewModel.routeSuggestion` (UI extension), `SecondTicker`,
`WindowVisibilityMonitor.dashboardOnScreen`; Debug flags `-TokeiProofFixture demo`, `-TokeiDemoRoute`,
`-TokeiProofRouteExpanded`, `-TokeiProofWindowSize`, `-TokeiProofTickReport`. Outside the UI scope: `App/AIUsageDashboardApp.swift`
(demo hook, dashboard env), `App/WindowVisibilityMonitor.swift`, `App/DemoFixture.swift`, `project.yml` (2 test-source
lines), `docs/FEATURES.md` (3 rows).

## Known gaps / not checked
- Real-data run of the route row on this Mac's live snapshot (demo only, by design of the captures).
- Full Core suite, cross-model review, prove-red via the kit script (tests are committed with new types, so it would
  only show compile-red; the one logic fix was shown red manually above).
- Overnight a system alert (UserNotificationCenter) held focus for a while; pass-1 captures were inactive. Pass 2 is active.
- Existing copy elsewhere still has em dashes ("Cursor, Auto monthly window — the tightest live quota", drill-in insight
  "cache reads — heavy reuse"); not touched (outside this AC).
- The "Tightest quota" line still counts a stale reading that the route row treats as waiting (its own rule).

## Fix round 1 (review r1 S1)
- S1 fixed: one shared gate `RouteSuggestion.chipTarget(_:utilizations:now:)`. The row still always shows RoutePlan's
  recommendation; the Overview tile and drill-in chip show only when `RouteTargetPolicy.human` (15-point spread,
  target <= 70%) names a plan, and only if that is the row's plan (otherwise no chip). Both chips read
  `DashboardViewModel.routeChipTarget` over the same visible `gaugeUtilizations` the shipped chip used.
- Tests (RouteSuggestionTests, now 16): equal 30%/30% -> row recommends, no chip; 83%/84% -> no chip; 72%/20% -> chip on
  the row's plan (Codex); one plan -> no chip; every case: a chip is nil or the row's plan. DemoFixtureTests asserts the
  capture fixture's chip is Codex.
- Red on round-1 behaviour (scratch copy with chipTarget returning the row target):
  `testNearlySpentPlansOnePointApartGetNoChip : XCTAssertNil failed: "claudeCode"`,
  `testTwoEqualPlansGetARecommendationButNoChip : XCTAssertNil failed: "claudeCode"` (2 failures of 16). The clear-spread
  case passes on both by design (it guards against over-suppression).
- `git merge dev` (WP-D, CLI only): clean, no conflicts. Rebuilt Debug app: BUILD SUCCEEDED.
- Tests: DemoFixtureTests RouteSuggestionTests SecondTickerTests WP4LabelMotionTests NoEyebrowTextTests RoutePlanTests
  RouteTargetPolicyTests BurnBoardTests MenuBarLabelModelTests SavedSnapshotLaunchTests AgentRouteSnapshotTests
  RouteCommandTests -> `Executed 93 tests, with 0 failures` `** TEST SUCCEEDED **`.
- `bash .claude/gates/run-all.sh fast` -> ALL GATES GREEN (format/lint SKIP, tools not installed).
- Recapture: none needed. Fresh captures on this build (`proof/route-ui/fix-r1/`) show the Overview tile "Send here next"
  and the drill-in "Send work here next" chip still on Codex (demo has a 52-point spread), so `site-captures/` stands.
- Commits now:
ad0e55b Merge branch 'dev' into patch/2026-11-15/route-ui
8572071 fix(route): chips keep the shipped quieting rule (review r1 S1)
17027c2 docs(features): route row, demo data, hidden clocks; captures avoid the pointer
b3857dd fix(timers): nothing ticks while the dashboard is off screen
42298d1 feat(route): "Send work here next" in the popover and Overview
0563f51 Merge branch 'dev' into patch/2026-11-15/route-ui
daab397 feat(proof): publishable demo data for captures (-TokeiProofFixture demo)
