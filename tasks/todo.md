# WP-6 — 5 behavioural gaps (re-QA 2026-07-21)

Branch: patch/2026-07-21/overview-quota-hover · base dev @ abb627e

## FIX 1 — Heatmap responds to range control  [Core+VM+tests]
- [ ] `UsageAnalytics.heatmapMatrix` gains `range:`/`now:`, filters hourly slots by day-window before folding (mirror filteredDailyTotals). Default `.lifetime` → non-breaking.
- [ ] `DashboardViewModel.heatmap(for:)` passes `viewModel.range` + `now()`.
- [ ] Tests: same hourlyTotals under .sevenDay/.thirtyDay/.ninetyDay → different matrices; out-of-range excluded. VM range-swap test.

## FIX 2 — Quota lens shows % not tokens  [Overview]
- [ ] `agentModels` metric-aware: quota mode → "46%" + "54% left" caption, threshold-coloured; usage mode unchanged.
- [ ] Extend AgentCellModel (substat/substatColor); AgentGridCell renders it. Switch animates (reduce-motion safe — already gated).

## FIX 3 — Every enabled provider appears in quota  [Overview]
- Root cause (traced): quota surfaces render only `viewModel.utilization`; a live-quota provider (claude/cursor/antigravity, all enabled in real prefs) drops to `.unavailable` windows whenever `fetchQuotaWindows()` throws (cooldown/429/unauthorized/empty) → nil-mapped → silently omitted. Banner shows Claude now because cache is fresh; QA hit a transient cooldown.
- [ ] Shared `quotaState(for:)` → live / fetching(enabled,no window) / connect(!enabled) / localOnly.
- [ ] `AgentQuotaBars` + agent grid enumerate ALL visible providers; explicit honest state, never omit an enabled provider.

## FIX 4 — Menu-bar quota: animated fill + pace marker  [MenuBar]
- [ ] Animate each quota bar 0→value on switch (reduce-motion: final state only).
- [ ] Red pace notch at previous period's used% (baseline = QuotaSeriesStore.shared sample ~one window-duration ago); no baseline → no marker.
- [ ] Label render path (MenuBarLabel/MaxxerMath) untouched.

## FIX 5 — Hover details: trend + heatmap  [Charts]
- [ ] LineTrendChart: hover → nearest-point RuleMark + styled callout (date · total · top agent). Per-day top-agent computed in UI from per-provider dailyTotals.
- [ ] ActivityHeatmap: replace `.help()` with immediate styled hover tooltip (weekday+hour · top agent · tokens). Cells are weekday×hour category — never say "that day".
- [ ] Respect reduce-motion (no flicker).

## Verify — ALL DONE
- [x] xcodegen generate; Core test scheme (304 tests, 0 fail); App build scheme (BUILD SUCCEEDED).
- [x] Visual verify in running app (this worktree's DerivedData build): FIX 1 (7D sparse vs 90D dense heatmap), FIX 2 (grid % + N% left), FIX 3 (all 5 providers, Antigravity FETCHING…, Cline LOCAL LOGS), FIX 4 (menu-bar Quota fill bars + reset countdowns + red pace notch), FIX 5 (heatmap tooltip + trend callout).
- [x] All 5 fixes marked done. Completion note appended to Patch Bible §8. Commit per fix. No merge/push/PR.
