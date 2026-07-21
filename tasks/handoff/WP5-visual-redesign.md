# WP-5 handoff — visual redesign to the `Tokei Dashboard.html` mockup

Checkpoint rewritten 2026-07-21. Single source of truth to resume. Everything below is durable.

## Where the code is
- **Worktree:** `/Users/abhayp/Downloads/Projects/tokei-worktrees/2026-07-19-ui-ia-consolidation`
- **Branch:** `patch/2026-07-19/ui-ia-consolidation` @ `4033551` — clean (only untracked = `tasks/handoff/*` assets). NOT merged, NOT pushed.
- **Scope lock:** `AIUsageDashboardApp/UI/` + `Assets.xcassets/ProviderMarks/` + `MenuBar/`. NEVER touch `Core/`, `App/`, `project.yml`, or `MenuBar/MaxxerMath.swift` (the ONLY UI file compiled into the 302 Core tests — keep its public API stable).
- **Build/verify:**
  ```
  cd AIUsageDashboard && xcodegen generate
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test   # 302 pass
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp  -destination 'platform=macOS' build
  ```
- **This worktree's DerivedData / app:** `~/Library/Developer/Xcode/DerivedData/AIUsageDashboard-dfmeddobpfrxvxeqtepfotxljyha/Build/Products/Debug/Tokei.app` (regular window app + MenuBarExtra; window opens on launch).

## Design reference (durable, in this folder)
- `new-design-template.html` — the decoded/rendered DOM of `~/Downloads/Tokei Dashboard.html` (exact inline-style values).
- `new-design-outline.txt` — pruned DOM tree with inline styles (fast to scan per surface).
- `new-design-logic.js` — the component JS: the mock `providers` array, per-agent tints, glyph CSS, `renderChart/renderDonut/renderHeatmap/renderGauge/renderHistory`, pace/quota helpers. **Read this for exact values instead of re-decoding the bundle.**
- Original bundle still at `/Users/abhayp/Downloads/Tokei Dashboard.html`.

## DONE (committed, all build-green)
- **P0 `1635897`** — `PadzyTheme` migrated app-wide to the dark ramp; see "Design system" below. `AgentTint`, `PaceVerdict`, `PadzySpace`, `PadzyMotion`, `Font.sans`, `Font.mono(weight:)`, `TokenFormatter` (mockup fmt, nil→"—"). `TokeiStatusIcon` accent single-sourced. Heatmap/area gradients recoloured neutral.
- **P1 `b7bc6ef`** — `ProviderMark(tint:)` + `ProviderBrandMark(tint:)`/`.tinted(_:size:)` per-agent tinted glyph; gemini→`sparkle` fallback (6 real `mark_*` assets, gemini has none). `PadzyToggle` → mockup pill (white knob).
- **P2a `2e330e5`** — `DashboardTab` = 3 plain tabs `Overview/Value/Agents` (no kicker); `AppSection.connections` now owned by `.agents` tab. `DashboardTabBar` plain labels + restyled range chips. **ProviderChipStrip removed from the shell** (mockup has none). New `PressureBanner` (tightest live quota, taps to drill). Status bar restyled.
- **P2b `5ac55ef`** — Settings + Add-agent are now **380px right drawers** (`SettingsDrawer`, `AddAgentDrawer`, shared `DrawerScaffold`). Deleted dead `SettingsView.swift` + `AddAgentSheet.swift`. Gear→`viewModel.showingSettings`; add-agent→`showingAddAgent`. `AppSection.settings` removed.
- **P3 `cb8deae`** — Overview rebuilt: metric selector (Usage/Quota), 62px hero, restyled `LineTrendChart`, `OverviewAgentGrid` (tinted glyph + subtle dotted-underline confidence), per-agent-tint `ProviderDonut`, weekday bars, streak/avg, heatmap. New `OverviewParts.swift`, `OverviewAgentGrid.swift`.
- **heatmap `4033551`** — `ActivityHeatmap` → continuous single-hue opacity field (was blocky discrete ramp). User-requested tweak; approved-ish.

## Locked decisions (2026-07-20, confirmed with user)
1. Settings = **380px right drawer** (done). 2. Palette = **migrated app-wide** (done). 3. Logos = **existing marks tinted per-agent** (done).

## Design system now in place (REUSE — do not re-derive)
`PadzyTheme`: ground `#0B0B0D` · window/surface `#0F0F12` · panel `#131316` (drawers) · statusBar `#0C0C0E` · menuPanel `#141418` · hairline `#1C1C21` · border2 `#26262C` · scrim. Ink ramp `ink`=`#ECECF1`, `ink2`=`#C4C4CC`, `ink3`=`#9A9AA4`, `ink4`/`muted`=`#6E6E78`, `ink5`=`#54545C`. `accent`=`#FF3B70` (+`accentHover`), `good`=`#6BBF8A`, `warn`=`#D2A15C`, `danger`=`#FF4D4D`. `quotaColor(pct)` (≥90 accent / ≥60 warn / else ink4). `PaceVerdict(pct:elapsed:).word/.color`. `AgentTint.color(id)` (claude `#C77D5A`·codex `#5FA88C`·cursor `#9AA0AA`·cline `#8A93E6`·antigravity `#D2A15C`·gemini `#6D93DB`·opencode `#B98BD0`). `PadzySpace.{xs4,s8,m12,l16,xl20,xxl28,xxxl40}`. `PadzyMotion.{settle .65,quick .2,toggle .15}` — ALWAYS gate with `@Environment(\.accessibilityReduceMotion)` → nil. `PadzyRadius.{window10,cell4,chip4,control8,pill}`. `Font.mono(size:weight:)` numbers/paths/kickers only; `Font.sans(size:weight:)` names/body/buttons. `ProviderBrandMark.tinted(id,size:)`, `PadzyToggle` (.padzy), `SectionLabel`, `HairlineDivider`, `SurfaceStateView`.

## Data-wiring map (the REAL APIs — mockup providers array is illustrative only)
`DashboardViewModel` (`Core/Sync/DashboardViewModel.swift`, injected `@EnvironmentObject`): `snapshots:[ProviderSnapshot]`, `isLoading`, `errorMessage`, `lastSyncedAt:Date?`, `selectedProvider:ProviderID`, `showingSettings`, `range:UsageRange`(.sevenDay/.thirtyDay/.ninetyDay), `refresh() async`, `snapshot(for:)`, `isAvailable(_:)`, `selectNext/PreviousProvider()`, `utilization:[Utilization]`, `overviewTrend`, `providerSplit`, `overviewDelta`, `streak`, `bestDay`, `leastActiveDay`, `dailyAverage`, `trend(for:)`, `thisWeek(for:)`, `heatmap(for:)`, `peakHour(for:)`. NOT on VM: merged-today = `MaxxerMath.mergedTodayUsage(in:)`; tightest = `MaxxerMath.tightestWindow(in: utilization)`; lifetime = `snapshot.lifetimeUsage`; plan cost = `MaxxerPlanCostStore.monthlyUSD(for: id.rawValue)`/`setMonthlyUSD`; value/tier = `MaxxerValueEngine.scorecard(snapshots:planCosts:now:)` → `MaxxerScorecard.totalValueMultiple/.tier`; capability tier = `ProviderCapabilityTier.classify(_:).label`; watched path = `ProviderMetadata.localPaths(for:).first`; visibility = `ProviderVisibility.isHidden/visible`; add/detect = `AddAgentModel`. `ProviderSnapshot`: `providerID, displayName, authStatus, quotaWindows:[QuotaWindow], todayUsage/weekUsage/monthUsage/lifetimeUsage:TokenUsage, costUsage, warnings, dailyTotals:[Date:Int]?, hourlyTotals`. `QuotaWindow`: `type:QuotaWindowType(session/daily/weekly/fiveHour/monthly/credits/perModel/lifetime), used/limit/remaining:Double?, resetAt, confidence:MetricConfidence, label:String?`. `TokenUsage.totalTokens:Int?` + input/output/cacheRead/cacheCreation. `MetricConfidence`: exact/providerReported/localParsed/estimated/unavailable (+`.displayName`).

## REMAINING (next session)
- **P4 Value** (`Value/ValueView.swift`) — mockup outline L167-219. PLAN VALUE·THIS MONTH kicker; 84px mono hero (`MaxxerScorecard.totalValueMultiple`); tier chip (`.tier`, green "ALL RIGHT-SIZED" / warn "N TO REVIEW"); ◆ insight sentence; per-agent rows (glyph · name · `plan → api` w/ dotted-underline confidence for estimated · mult in multColor); TOTAL row; excluded note. Row tap → drill into provider. Drop the hand-built fixed-width table for a clean hairline-row grid.
- **P5 Agents tab** (`Connections/ConnectionsView.swift` + `ConnectionRow.swift`) — mockup L220-268. Per-agent cards: `ProviderBrandMark.tinted` · name · tier chip (`ProviderCapabilityTier.label`) · path (mono) · **Show** toggle (`ProviderVisibility`) · watch dot + Rescan · **LIVE QUOTA** state off/connecting/live toggle (`ConnectionRow`'s `@AppStorage` enable flag → replace native `.switch` with `.padzy`). Footer privacy note.
- **P6 Drill-in** (`ProviderDetail/ProviderDetailView.swift`, and de-dup the quota-row still duplicated in `DashboardView`'s plan-only `capabilityPane`) — mockup L269-407. Back · tinted glyph · name · "Route work here" chip (green, on headroom agent) · planLabel · confidence · meta grid (watched file/last sync/capability) · ◆ insight · circular gauge (`CircularGauge`, tightest window) + verdict · stats row · PLAN & CREDITS plan-only variant (credits bar + "not measured locally" + Enable-online) · QUOTA WINDOWS grouped by model with pace markers (`PaceVerdict`, marker at elapsed%) · DAILY HISTORY 30d (`renderHistory`, agent-tint) · TOKEN SPLIT today (input/cache/output shades from `todayUsage`).
- **P7 Menu bar** (`MenuBar/MenuBarView.swift` + `MenuBarLabel`) — mockup L545-613. Popover: TOKENS·TODAY hero · plan value + tier · tightest quota + dot + who · top-3 agents mini-list · Open Tokei / Quit. Readout picker already wired via `MenuBarDisplayMode` (tokens/quota/all-time/icon).
- **P8 states · reflow · cleanup** — restyle empty/loading/error to the mockup (`SurfaceStateView`); verify narrow reflow <720 + the 640×480 minimum on every surface; every `tk-*`/animation reduce-motion-safe. **Cleanup sweep:** delete now-unused `ProviderChipStrip.swift` + `QuotaWindowRow.swift` (dead), remove the now-unused `openConnections()`/any orphans, drop `PadzyChartPalette.heatmapRamp`/`donutRamp` if fully unused, run `/simplify`.
- Then: append a WP-5 note to `tasks/patch-bibles/2026-07-19.md` §8; restore any test UserDefaults; **out-of-scope follow-ups** (do NOT do under WP-5 — need Core/feature work): range set Today/Week/Month/All (Core `UsageRange`), functional accent-override store, a real `mark_gemini` asset.

## VERIFICATION GAP (important)
This session's process has **no macOS Screen Recording or Accessibility permission** → `screencapture` returns pure black and `osascript`/System Events can't drive the window. **Automated screenshots are impossible.** Visual verify must be the user (launch `Tokei.app`, look, or Cmd-Shift-4 + paste). To fix for automation: grant the terminal Screen Recording + Accessibility in System Settings → Privacy.

## Process that worked
Delegate each surface rebuild to a focused subagent with: the mockup spec (from the decode files), the design-system tokens, the data-wiring map, "preserve every VM binding", and a **build-to-green, do-not-commit** mandate; then review its diff + rebuild + commit. Keeps main context lean (this session stayed healthy; the prior one died of context). Small reviewable commits; pre-commit gate runs no-secret/no-large-artifact/format.
