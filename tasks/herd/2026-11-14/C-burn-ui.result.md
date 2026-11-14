STATUS: READY

# WP-C · Burn UI + Mac smoothness — result (Claude Opus 5.5, 2026-11-14)

Branch `patch/2026-11-14/burn-ui` (worktree `~/src/tokei-worktrees/2026-11-14-burn-ui`), HEAD `f16da97`, dev merged in
at 8dedb49 (WP-A engine, no conflicts). Scope held: only `App/UI/**`, `App/App/*`, `Tests/UITests/*`, `project.yml`
(test sources). Nothing in `Core/`, `TokeiCLI/` or `UI/Settings/AgentConnectSection.swift`; `SettingsDrawer.swift` got
one include line (`BurnNudgesSection()` after `QuotaAlertsSection`), next to where WP-B adds its own line.

Proof media (out of git; real usage visible): `~/Library/Developer/TokeiWork/proof/burn-ui/`
(`captures/` sample + fresh install with `snapshots.md`, `captures-real/` real engine data, `review-r1/`, `perf/`, `rig/`).

## The one detail that shows care

The second lap. Past 1× the daily ring does not stop full: the first lap dims and the next lap runs over it, cut from it
by a thin line of the surface colour, so "beyond the goal" reads at a glance in one hue, with no shadow and no second
colour (theme invariants 3 and 5). The centre switches from "62%" to "1.5×" at the goal and rolls with the app's 220 ms
live-number timing (snaps under Reduce Motion). On real data it reads 9.6×: the current lap over nine dimmed ones
(`captures-real/real-burn-dark-top.png`).

## Transitions and states checked (before building, then proven)

| Transition / state | Behaviour | Proof |
|---|---|---|
| Launch, saved → live | Every strip line and Burn section is always present (plain words when empty); numbers roll in place, no reflow | `captures/saved-to-live.mp4`; first `transitions` clip showed "Saved just now · updating…" → "Synced just now", 511M → 517M in place |
| Menu strip → Burn | One click: dropdown closes, dashboard opens on Burn (⌘2) | `MenuBarView.openBurn`; strip is one Button |
| Tab switch, drill-in, Settings | One spring `PadzyMotion.navigate` (.smooth 0.28 s, no bounce); underline slides; Reduce Motion swaps instantly | `captures/transitions.mp4` |
| Celebration | Overlay, hit testing off, no focus change, ends with its `.task`; plays only on an exposed surface (r1 S1); stale (>12 h) dropped | `captures/celebration-*.mp4`, `review-r1/` |
| Fresh install | Strip "No daily goal yet / Set plan costs, or use an agent today."; Burn: ring track, Set plan costs, every section says what fills it, Share disabled | `captures/*empty*` |
| Sync error | Dropdown keeps its existing error state (strip not shown); Burn shows the last snapshot | code reading |

## Placement (AC 2): a Burn tab after Overview, not inside Value

```
Overview  Burn  Value  Agents                          ⌘1 ⌘2 ⌘3 ⌘4
[ring 1.5×]  $14.62 burned on your plans today, of a $9.68 goal    [Share my week]
             11-day streak  Goal hit today
Use it or lose it    Codex 5-hour   ▬▬▭▭▭  62% left   42 min
This week's agents (rank, mark, $, tokens)   | Records 2×2
Left on the table 24%  + recent windows
Value tier this month  Idle · Warming · Break-even · Maxxing · Goblin mode (2 px accent marker)
Badges (hairline grid of 13)   fine print: plans only
```
Why a tab: Burn is the daily destination the menu strip opens (today, streak, windows expiring in minutes) and has its own
hero; Value is a calm month-to-date ledger. Inside Value, the countdowns would sit under the plan table and Value would
have two heroes.

## Acceptance criteria

### AC 1 · Menu bar burn strip — done
Top of the dropdown: ring (second lap past 1×), "1.5× of today's goal", "$14.62 on your plans today", "11-day streak
goal hit today" (flame filled only when alive; "keep it alive" in warn; "start one today"), and the top expiring window
"Codex 5-hour · 62% left · 42 min" (ticks per minute only while on screen). Click opens Burn. Empty state as above.
- Check: own-window snapshots, light + dark, sample + fresh install + real data:
  `captures/dropdown-{sample,empty}-{dark,light}.png`, `captures-real/real-dropdown-{dark,light}.png`
  (real: "9.7× of today's goal", "$180.28 on your plans today", "4-day streak goal hit today").
- First review caught truncated strip text ("of today'…"); fixed in 5b2b39d, re-captured.
- Light vs dark: Tokei ships dark-themed in both modes (docs/07-padzy-theme.md; roots set `.preferredColorScheme(.dark)`),
  so the pairs differ only in window chrome. Captured with `-AppleInterfaceStyle Light|Dark`.

### AC 2 · Burn view — done
Hero ring + streak, use-it-or-lose-it with countdowns, this week's agents (zero-burn rows hidden, f2e9543), records,
left on the table, tier ladder with the user's position, badges (unlocked with date; locked with progress and the rule
sentence), Share my week, plan-only fine print (bible §7).
- Check: `captures/burn-{sample,empty}-{dark,light}-{top,middle,bottom}.png` and
  `captures-real/real-burn-{dark,light}-{top,middle,bottom}.png` (real: 9.6×, $179.97 of $18.67, leaderboard
  Claude Code $663.01 / Codex $77.11, records, 1.6× Break-even, badges 5 of 13). Lower sections via Debug routes
  `-TokeiProofRoute burn.middle|burn.bottom` (10ded06).
- Menu self-test (⌘ shortcuts renumbered): `open -n -W --stdout perf/selftest-menus.txt <Debug Tokei.app> --args -TokeiSelfTest menus`
  → 15 lines `PASS …` incl. `PASS View › Burn is ⌘2`, `PASS ⌘2 shows Burn`, `PASS ⌘4 shows Agents`, then `SELFTEST PASS`.

### AC 3 · Celebrations — done
Badge, record and tier-up moments play once: spring-driven ember burst + glow on the ring (badges on their own cell);
Goblin mode gets two waves, more sparks, longer reach. Reduce Motion: static 2 px accent outline + the words for 4 s.
Overlay only, `allowsHitTesting(false)`, no focus or layout change (the words sit in a reserved line), `.task`-scoped so
nothing keeps running. Played only where seen: the dropdown only while open (18bae04), Burn only when not covered (r1 S1).
- Check: Debug trigger `-TokeiBurnSample YES -TokeiProofRoute burn -TokeiBurnMoment tier.goblinMode -TokeiBurnMomentDelay 3`
  (+ `-TokeiReduceMotion YES`). Recordings (Tokei's own window via ScreenCaptureKit, 7 s each):
  `captures/celebration-goblin.mp4`, `captures/celebration-record.mp4`, `captures/celebration-goblin-reduce-motion.mp4`.
  Frames checked: burst + "Tier up: Goblin mode" then clear by ~2 s; Reduce Motion shows outline + words, no burst.
- Unit: `BurnBoardTests` (5) — follows `viewModel.burn`, celebrates the headline moment once, never replays, a covered
  surface (drill-in, drawer, or Burn's own share sheet) leaves it pending; `BurnCopyTests.testMomentTitlesAndWhichMomentHeadlines`.

### AC 4 · Share my week — done
1200×630 PNG: week's plan usage at API prices, tokens, month multiple + tier, streak, top agent; product names only.
Copy (pasteboard PNG) and Save… (NSSavePanel). Card frozen at open; PNG keyed on that card (r1 S2).
- Check: `captures/share-card.png` (`sips` → pixelWidth 1200, pixelHeight 630), `captures/share-sheet-dark.png`.
- Unit: `ShareCardModelTests` (3) incl. `testCardHasNoAccountIdentifiers` (Mirror of stored fields is exactly the seven
  aggregate fields, no String storage; an email, account id, path and project name planted in the snapshot never
  reach any drawn line or the file name).

### AC 5 · Settings "Burn nudges" — done
`BurnNudgesSection`: switch bound to `@AppStorage(BurnNudgePolicy.enabledKey)` (default on; also registered in
`AIUsageDashboardApp.init`), caption "Up to 2 a day, when a window resets soon with plenty left." (from
`BurnNudgePolicy.maxPerDay`); disabled with "Alerts are off above, so nudges are off too." when the master alert switch is
off. `AgentConnectSection.swift` untouched.
- Check: `captures/settings-burn-nudges-{dark,light}.png`.

### AC 6 · Smoothness, measured first — done, with one metric not improved
Rig: `~/Library/Developer/TokeiWork/proof/burn-ui/rig/` (`tokeiperf.swift`, `perf-session.sh`, `hitches.py`,
`profile.py`, `profile-session.sh`). Release builds, same rig, back to back:
`TOKEI_TABS=1,3,4 rig/perf-session.sh apps/before/Tokei.app ab-before` then `… apps/after/Tokei.app ab-after`
(before = unmodified dev 3fd3e98 + contract; after = this branch at the dev merge cd8cea8). Launch = process-cold
(new process, warm disk cache) `open` → dashboard window in the window server list; dropdown = status-item click →
panel window listed; hitches = xctrace Animation Hitches (`--all-processes`, Tokei rows only) over 15 s of tab presses
(Overview/Value/Agents via the tab buttons' AX press) and 15 s of Overview wheel scrolling; idle = `ps -o time` delta
over 300 s, window open (front) then closed (AX close button).

| Metric | Before | After | Note |
|---|---|---|---|
| Cold launch → dashboard window (median of 5) | 335 ms | 293 ms | |
| Menu click → dropdown on screen, first / warm median of 5 | 244 / 142 ms | 252 / 144 ms | flat, with the burn strip added |
| Idle CPU, window open, 300 s | 6.20 % (18.61 s) | 4.95 % (14.86 s) | other agents writing logs trigger syncs in both |
| Idle CPU, window closed, 300 s | 3.68 % (11.06 s) | 2.17 % (6.51 s) | |
| Tab switching, 15 s: hitches / total / worst | 33 / 371 ms / 50.0 ms | 55 / 550 ms / 41.7 ms | see fade A/B below: within run-to-run noise |
| Overview scrolling, 15 s: hitches / total / worst | 6 / 58 ms / 16.7 ms | 11 / 142 ms / 16.7 ms | single runs |
| Main-thread stalls ≥ 16.7 ms (Time Profiler, 40 s: 4 menu opens, 20 tab switches, scrolling) | 58, longest 72 ms | 38, longest 59 ms | before-p2 vs ab-after-profile |
| `NSStatusItem _redrawReplicantSnapshot` samples inside stalls | 437 | 195 | the measured top offender |
| `ValueView.body` main-thread samples (of which scorecard) | 31 (17) | not in top 30 | |

Pane-fade A/B (to test whether the new tab fade caused the extra hitches; same build otherwise, alternating):
`rig/hitch-ab.sh nofade-1=… fade-1=… nofade-2=… fade-2=…` → 
`nofade-1 59 hitches, total 558 ms, worst 66.7 ms` · `fade-1 43, 383 ms, worst 25.0 ms` ·
`nofade-2 53, 658 ms, worst 75.0 ms` · `fade-2 48, 450 ms, worst 41.7 ms` (`perf/hitch-ab/results.txt`).
Conclusion: the fade lowers both the count and the worst hitch (it spreads the new pane's first frame over the spring
instead of one hard swap), so it stays. Against the unmodified build, tab-switch hitch counts still swing between
single runs (33 before vs 43–55 after), so this metric shows no proven improvement or regression (gap below).

Offenders found and fixed (profile first, `rig/profile.py` reads the trace as text, traces deleted after):
1. Status-item fan-out (e971582): the menu bar label held the whole `DashboardViewModel`; every `@Published` write
   (each tab switch wrote `showingSettings = false` even when false; the App observed the navigator) re-rendered the
   label, and each label render makes `NSStatusItem` redraw its replicant snapshot on the main thread — the largest
   block inside stalls. Now `MenuBarLabelModel` (@Observable, assigns only changed values), `NavigationMenuState`
   (publishes `canGoBack` only on change), guarded navigator writes. Test: `MenuBarLabelModelTests` (3; the first fails
   if a no-op view-model write notifies the label).
2. Value engine re-run (88af83f): `ValueView` recomputed `MaxxerValueEngine.scorecard` ~15× per render; now once.
3. Burn surfaces observe a UI-owned `@Observable BurnBoard`, not the view model (5c3a6cc).

### AC 7 · Transitions — done
One spring for tab switches (underline `matchedGeometryEffect` + new pane fades in, old pane leaves at once), drill-ins
(was easeOut 0.18) and the Settings/Add-agent drawers (were easeOut 0.2); instant under Reduce Motion (669dc86).
No layout jump saved → live (every burn line reserved).
- Check: `captures/transitions.mp4` (10 s: Burn → Value → Agents → Overview → Burn, drill into the top agent and back,
  Settings open and close; driven by Accessibility presses) (03:04, log: `pressed Burn tab … pressed Rank 1 / pressed Back to / pressed Settings / pressed Close`, 467 frames; frames
  show the new pane fading in on each tab, the drill-in sliding from the trailing edge and fading out on Back, the drawer
  sliding in and out); `captures/saved-to-live.mp4`.

### AC 8 · Theme rules — done
No eyebrows (`NoEyebrowTextTests` passes over the new files; it caught one `uppercased()` during the work), mono numbers,
one accent hue per view, 2 px accent bar for active (tab underline, tier marker). Contrast: measured `ink4` 3.9:1 and
`ink5` 2.6:1 on the ground, so burn text stops at `ink3` (~7:1) via `BurnTone.caption`; faint inks only draw marks.
- Check: `BurnContrastTests` (4): text tokens ≥ 4.5:1 and marks ≥ 3:1 on ground, menu panel, panel, hover fill; a scan
  fails if a burn view uses `ink4`/`ink5` directly.

## Tests, build, gates (exact commands)

- `cd AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -derivedDataPath ~/Library/Developer/TokeiWork/dd-burn-ui test -only-testing:AIUsageDashboardCoreTests/{BurnBoardTests,BurnCopyTests,ShareCardModelTests,BurnContrastTests,NoEyebrowTextTests,MenuBarLabelModelTests,AccountSeriesStyleTests}`
  → `Executed 35 tests, with 0 failures` / `** TEST SUCCEEDED **` (02:56, b861b73: AccountSeriesStyleTests 3, BurnBoardTests 4, BurnContrastTests 4, BurnCopyTests 15, MenuBarLabelModelTests 3, NoEyebrowTextTests 3, ShareCardModelTests 3); after the r2 fix `-only-testing:AIUsageDashboardCoreTests/BurnBoardTests` → `Executed 5 tests, with 0 failures` (03:03, f16da97) (new classes: BurnCopyTests, ShareCardModelTests, BurnBoardTests, BurnContrastTests, MenuBarLabelModelTests). Earlier on the merged tree with WP-A's `BurnViewModelTests` too: 41 tests, 0 failures.
- Release: `xcodebuild … -scheme AIUsageDashboardApp -configuration Release -derivedDataPath ~/Library/Developer/TokeiWork/dd-burn-ui build`
  → `** BUILD SUCCEEDED **` at b861b73 (02:56) and again with the r2 fix (03:02, f16da97 content; log `proof/burn-ui/build-final.log`; only warnings are the pre-existing `plotAreaFrame` deprecations in AccountTrendChart.swift:141 and LineTrendChart.swift:219). Clean Release at the dev merge: 7 unique warning sites before and after, none in files this lane touched.
- `bash .claude/gates/run-all.sh fast` → `PASS preflight, no-secret, no-large-artifact, no-uncommitted, cli-version-sync, format, lint` / `[run-all] ALL GATES GREEN` (format and lint SKIP inside: swiftformat/swiftlint not installed)
- `~/agent-kit/bin/secscan ~/src/tokei-worktrees/2026-11-14-burn-ui` → `VERDICT: PASS` (head f16da97c4ecd, 26 commits, 0 uncommitted paths); no FLAG or GAP lines

## Review fixes (Codex Sol, C-review-r1.md and C-review-r2.md)

| Id | Fix | Commit | Check |
|---|---|---|---|
| S1 celebration consumed while Burn is covered | `BurnBoard.celebration(forSurfaceExposed:)`; Burn passes exposed = no drill-in, no Settings/Add-agent drawer; dropdown uses the same gate | 356a099 | Unit `BurnBoardTests.testACoveredSurfaceLeavesTheCelebrationPending` (fails if a covered pass gets it). Live: `rig/review-checks.sh` (03:05, Debug b861b73): launch on Burn with `-TokeiBurnMoment tier.goblinMode -TokeiBurnMomentDelay 6`, AX-press "Rank 1" at 3 s (drill into Claude Code), moment fires at ~6 s while covered (`review-r1/s1-1-covered.png`), press "Back to" at ~12 s: the burst and "Tier up: Goblin mode" play on return (`review-r1/s1-3-after-back.png`, `review-r1/s1-2-after-back.mp4`). Before the fix it would have played under the drill-in and finished by ~8 s |
| S2 exported PNG can differ from the card shown | Card frozen when the sheet opens; PNG `.task(id: card)`; Copy, Save and the debug hook share `exportPNG()` | e95ef37 | Live: `rig/review-checks.sh` (03:06, real data): `-TokeiProofRoute burn.share -TokeiShareCardOut review-r1/s2-export.png -TokeiShareCardOutDelay 45` writes, 45 s after opening (with live syncs in between, status "Synced just now"), exactly what Copy/Save export. `review-r1/s2-export.png` and the on-screen preview (`review-r1/s2-window.png`) show the same card: $813.32, 1.6× Break-even, 4-day streak, Claude Code, 2.69B tokens |
| r2 S1 the Share my week sheet covers Burn but the gate only checked the dashboard | `BurnExposure.burnTab(dashboardExposes:shareSheetOpen:)`; hero and badges get the celebration only when the dashboard exposes Burn and no share sheet is open | f16da97 | `BurnBoardTests.testTheShareSheetCoversBurnLikeADrillIn`: with the old rule `Executed 5 tests, with 2 failures` / `** TEST FAILED **`; with the fix `Executed 5 tests, with 0 failures` / `** TEST SUCCEEDED **` |
| (found while proving S1) leaderboard rows and the strip lost their press action for VoiceOver | Buttons keep their own accessibility element; only the label is set | b861b73 | An AX press on "Rank 1" did nothing before; after the fix the same press drills into Claude Code and "Back to Burn" returns (`captures/transitions.mp4`, 03:04 log: `pressed Rank 1`, `pressed Back to`) |

## Commits (`git log --oneline dev..HEAD`)

```
f16da97 fix(burn): the Share my week sheet covers Burn, so celebrations wait for it to close (review r2 S1)
b861b73 fix(burn): leaderboard rows and the burn strip keep their button press for VoiceOver
e95ef37 fix(burn): Share my week exports exactly the card it shows (review r1 S2)
356a099 fix(burn): a covered Burn pane leaves the celebration pending (review r1 S1)
10ded06 chore(proof): Debug routes for the Burn tab's lower sections; captures stay live when covered
f2e9543 fix(burn): an agent with no burn this week is not a place on the leaderboard
cd8cea8 Merge dev (WP-A burn engine, 8dedb49) into patch/2026-11-14/burn-ui
88af83f perf(value): run the value engine once per render, not about fifteen times
e971582 perf(menubar): the status item redraws only when its label changes
18bae04 fix(burn): the dropdown plays a celebration only while its panel is open
5b2b39d fix(burn): strip text no longer truncates; quieter empty states from the snapshot review
956fb4c fix(burn): label today's dollars as plan burn, not the Cost view's today
44dd453 fix(burn): burn text meets 4.5:1; the faint inks only draw marks
618b87a test(burn): BurnBoard follows viewModel.burn and celebrates each new moment once
669dc86 feat(motion): tab switches, drill-ins and drawers share one navigation spring
5c3a6cc feat(burn): Burn tab, menu bar burn strip, celebrations, share card and nudge switch
```

## Core requests (not made; for the orchestrator / WP-A owner)

1. `DashboardViewModel` sends `objectWillChange` for writes that change nothing: `applyLive` sets
   `showingSavedSnapshots = false` and `savedSnapshotsDate = nil` on every sync, and `selectedProvider`'s `didSet` writes
   `showingSettings = false` unconditionally. Each send re-renders every view model observer (Overview, dropdown, status
   strip). Guarding these writes (or moving the VM to `@Observable`) would cut idle CPU further. UI side is done.
2. No additive contract changes were made.

## Known gaps

- Tab-switch and scroll hitches: no measured improvement; single 15 s runs swing 33–59 hitches under identical
  conditions. A conclusive number needs ≥ 5 alternating runs per build (about 40 min with xctrace's 5 min save).
- Animation Hitches with `--attach` hangs at "ending recording" on this Mac; `--all-processes` filtered to Tokei works.
- The first "before" session (00:59) used an earlier rig whose key presses may not have reached Tokei; its numbers
  (launch 301 ms, dropdown warm 194 ms, tabs 87 hitches, scroll 17, idle open 4.57 %) are superseded by the A/B above.
- Idle CPU includes syncs triggered by other agents' log writes during the run (same for both builds; single runs).
- Launch is process-cold, not disk-cold (`purge` needs sudo).
- The like-for-like AX-driven profile of the unmodified build lost its menu opens (status item clicks did not land), so
  stall counts are compared against the key-driven before-p2 profile.
- Light and dark captures are the same content by design (dark-themed app).
- `lessons` CLI is not installed on this Mac; lessons are below instead.
- WP-A seeds first-run badges with today's date ("Unlocked Nov 14" on all five on this Mac): engine behaviour, noted.

## Lessons (vault `lessons` CLI missing here)

- Mac proof recordings: `screencapture -v -R` records whatever app is in front (it captured another session's DaVinci
  Resolve); record the app's own window with ScreenCaptureKit `SCContentFilter(desktopIndependentWindow:)` (`rig/winrec`).
- A background CLI cannot activate another app on this macOS, and `CGEvent.postToPid` key/scroll events are ignored while
  the target is inactive: press controls with `AXUIElementPerformAction`, send wheel events through HID only after
  checking the target is frontmost and on top, and prefer Debug routes over synthesized input for captures.
- `xcodebuild clean -configuration Release` on a shared DerivedData path also removed the Debug `.app`.
- A MenuBarExtra label re-render makes `NSStatusItem` redraw its replicant snapshot on the main thread; keep the label on
  a narrow model and never write `@Published` values that did not change.
- `.accessibilityElement(children: .ignore)` on a `Button` drops its press action for assistive tech; set the label only.
