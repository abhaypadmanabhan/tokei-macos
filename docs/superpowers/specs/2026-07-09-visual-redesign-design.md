# Tokei Visual Redesign — Design Spec

- **Date:** 2026-07-09
- **Status:** Approved (brainstorming) → ready for implementation plan
- **Author:** /morning-patch orchestration (brainstormed with user)
- **Supersedes on conflict:** the strict `aitracker` theme constraints in
  `tasks/patch-bibles/*` §5 (radius ≤4px, one-accent-only, no gradients) — the user has
  explicitly chosen the richer look below. Pink `#FF3B70` remains the single *action* accent.
- **Driver:** user supplied 5 inspiration mockups (Overview, Provider Detail, Settings, Menu
  bar) after disliking the current design. This spec turns them into a phased build.

## 1. Goal & scope

Replace Tokei's flat, numbered-kicker UI with a richer analytics dashboard matching the
mockups: rounded surface cards, real charts (line/area/donut), an activity heatmap, a
circular gauge, colored per-provider brand logos, and light gamification (streaks). All data
must be **real** — widgets without a real source render honest empty states, never fake numbers.

**Phased delivery (each phase independently reviewable + shippable):**
- **Phase 1a** — design tokens + component library + derived analytics; Overview (image 4) and
  Provider Detail (image 1), everything except heatmap/peak-hour.
- **Phase 1b** — hourly-bucket Core data addition; unlocks the activity heatmap + peak-hour.
- **Phase 2** — Settings (image 2).
- **Phase 3** — Menu bar (image 5).

This spec fully specifies **Phase 1a + 1b**. Phases 2–3 are scoped at a high level here and get
their own spec/plan when reached.

## 2. Design language

Extend `UI/Components/PadzyTheme.swift`; do not fork it. Keep the mono numeric discipline and
1px hairlines. Changes:

- **Radius:** introduce `PadzyRadius` scale — `card = 12`, `control = 8`, `pill = 999`. Cards
  become rounded surface panels (`PadzyTheme.surface`) over the flat `ground`.
- **Metric palette (data-only, never chrome):** new `PadzyChartPalette`:
  - input `#4C86FF` · output `#3DBE8B` · cacheRead `#A46BFF` · cacheWrite `#E8912D`
  - deltaUp `#3DBE8B` · deltaDown `#FF4D4D`
  - heatmap ramp: `surface` → pink `#FF3B70` (5 stops)
  - donut ramp: pink shades `#FF3B70 → #7A1D35`
  These colors appear ONLY inside charts/sparklines/deltas. Buttons, nav, active ticks, and
  "action" affordances still use the single accent `#FF3B70`. This preserves the
  "one accent for action" rule while allowing categorical data color.
- **Chart gradient:** a pink→transparent vertical area fill under line charts. The one
  sanctioned gradient, charts only — no gradients on cards/chrome.
- **Typography:** unchanged (display + mono families already in PadzyTheme).

## 3. Component library — `UI/Charts/` (new)

Each component is standalone, preview-driven, and takes plain value types (no view-model
coupling), so it is testable in isolation.

- **`LineTrendChart`** — Swift Charts (`import Charts`, macOS 14 ✓). Input: `[(Date, Int)]`.
  Pink `LineMark` + `AreaMark` gradient, trailing peak-dot with value label, muted axis.
- **`AreaTrendChart`** — compact variant for the rolling cards (sparkline-scale area fill).
- **`ProviderDonut`** — Swift Charts `SectorMark`. Input: `[(ProviderID, Int)]`. Pink-shade
  ramp + external legend (name · % · absolute). Center may hold a total.
- **`ActivityHeatmap`** — hand-rolled `Canvas`/grid. Input: `[[Int]]` (7 weekdays × 24 hours,
  or nil per cell). LOW→HIGH pink ramp, hour axis labels (12AM/4AM/…), weekday rows.
  Renders an honest empty state when the hourly source is absent (Phase 1b gate).
- **`CircularGauge`** — trimmed ring (`trim` + `.rotationEffect`), center % label. Input: a
  `Utilization` (used/limit). For "72% of session limit."
- **`MetricSparkline`** — refactor the existing inline `Sparkline` into `UI/Charts/`; add a
  `tint` param for per-metric color.
- **`StatCard` / `SectionCard`** — the rounded card shells (title kicker, optional trailing
  control, hairline-bounded body). Used across Overview + Provider Detail.

**Assets:** new `Resources/Assets.xcassets/ProviderBrands/` color image set per provider
(`brand_claude`, `brand_codex`, `brand_cursor`, `brand_antigravity`, `brand_cline`,
`brand_opencode`). A new `ProviderBrandMark` view resolves these; falls back to the existing
monochrome `ProviderMark` if a brand asset is missing (never blank). Monochrome `ProviderMark`
is retained for the menu bar / dense contexts.

## 4. Core analytics layer — `Core/Analytics/UsageAnalytics.swift` (new)

Pure, synchronous derivation over existing `ProviderSnapshot` fields (`dailyTotals`,
`todayUsage`, `week/month/lifetimeUsage`, `quotaWindows`). **No new parsing.** Fully unit-tested.

Functions (all return `nil`/empty honestly when history is insufficient):
- `streak(dailyTotals:) -> (current: Int, longest: Int)` — consecutive active days (>0 tokens),
  counted to *today* for `current`.
- `bestDay` / `leastActiveDay(dailyTotals:) -> (Date, Int)?`.
- `dailyAverage(dailyTotals:, window: Int?) -> Int?`.
- `peakDay(dailyTotals:) -> (weekday: Int, tokens: Int)?`.
- `delta(current:previous:) -> Double?` — signed percent; used for "↑18% vs yesterday" and
  "vs last 7 days." Nil when previous is 0/unknown (no divide-by-zero, no fake baseline).
- `providerSplit(snapshots:, range:) -> [(ProviderID, Int)]` — donut source, today or ranged.
- `rolling(snapshots:) -> (sevenDay: Int, thirtyDay: Int, lifetime: Int)` with per-window delta.

Data ownership: `UsageAnalytics` is `Core`-side (no UI import), consumed by the view model,
never called directly from a View (frozen contract: UI → view model only).

## 5. Core hourly-bucket addition — Phase 1b

**Problem:** the activity heatmap (Overview + Provider Detail) and "peak hour" (Provider
Detail) need weekday×hour aggregation that does not exist. `dailyTotals` is per-day total only.

**Approach:** the local parsers already read per-record timestamps (Claude JSONL, Codex,
opencode `time.created` ms). Add:
- `ProviderSnapshot.hourlyTotals: [Date: Int]?` — **append-only** field (frozen-contract rule:
  add to `Core/Storage/ModelCodableExtensions.swift` in the same commit). Keyed by hour-truncated
  `Date`. Optional so providers without timestamped records omit it.
- Parser aggregation: each `LocalLogProvider` parser buckets records by hour alongside its
  existing daily bucketing. Providers that cannot (plan-only, e.g. Antigravity) leave it nil.
- `UsageAnalytics.heatmapMatrix(hourlyTotals:) -> [[Int?]]` (7×24) and
  `peakHour(hourlyTotals:) -> (hour: Int, tokens: Int)?`.

**Gate:** until 1b merges, `ActivityHeatmap` + peak-hour render the honest empty state; nothing
else in Phase 1 depends on hourly data.

**Deferred sub-item (per-metric hero sparklines):** the tiny sparklines under INPUT/OUTPUT/
CACHE need per-day *per-metric* split, which `dailyTotals` (total-only) lacks. Phase 1a MVP:
render a single total-tokens sparkline in the hero, omit per-metric sparklines. Full per-metric
split is a later data addition (same shape as hourly), explicitly out of Phase 1 scope.

## 6. Phase 1 surfaces — widget → data source

**Overview (image 4):**
| Widget | Source | Phase |
|---|---|---|
| TODAY hero total + INPUT/OUTPUT/CACHE-READ/CACHE-WRITE | `todayUsage` | 1a real |
| Hero sparkline (total-only MVP) | `dailyTotals` | 1a real |
| Per-metric hero sparklines | per-day metric split (absent) | out of scope |
| Token-usage-over-time line | `dailyTotals` | 1a real |
| Usage-by-provider donut | `UsageAnalytics.providerSplit` | 1a real |
| Streak / longest / best day / least active / daily avg | `UsageAnalytics` | 1a real |
| Daily activity heatmap | `hourlyTotals` | 1b |

**Provider Detail (image 1):**
| Widget | Source | Phase |
|---|---|---|
| Header: brand logo, name, status pill, last-sync, watching-path | snapshot + `ProviderMetadata` | 1a real |
| TODAY hero + metric cards | `todayUsage` | 1a real |
| LIMITS bars (session/weekly/per-model, % + resets + used/limit) | `quotaWindows` | 1a real |
| USAGE TREND line | `dailyTotals` | 1a real |
| THIS WEEK: peak day, daily avg, delta | `UsageAnalytics` | 1a real |
| Circular session gauge (if used on detail) | `quotaWindows` | 1a real |
| Peak hour + activity heatmap | `hourlyTotals` | 1b |

**Range selector** ("Last 7 Days"): a `UsageRange` enum (7D/30D/…) drives the line/donut/rolling
windows off `dailyTotals`. Ranges beyond available history clamp + disclose ("only N days of
data").

## 7. Work packages (for the implementation plan / next /morning-patch)

- **WP-A · Design tokens + component library** — `UI/Components/PadzyTheme.swift` (radius +
  palette), `UI/Charts/*` (all components), `Resources/Assets.xcassets/ProviderBrands/*`,
  `ProviderBrandMark`. Claude UI agent + `padzy-os`. UI-only.
- **WP-B · Core analytics** — `Core/Analytics/UsageAnalytics.swift` + tests. Codex/Core. No UI.
- **WP-C · Overview + Provider Detail rebuild** — `UI/Overview/*`, `UI/ProviderDetail/*`,
  `UI/Dashboard/DashboardView.swift` wiring; consumes WP-A + WP-B. Claude UI agent. Depends on
  A + B (merge order A,B → C).
- **WP-D · Hourly buckets (Phase 1b)** — `ProviderSnapshot.hourlyTotals` + parser aggregation +
  `ModelCodableExtensions` + `UsageAnalytics.heatmapMatrix/peakHour` + tests. Codex/Core.
  Unlocks heatmap/peak-hour, which WP-C already renders as empty until this lands.

Disjoint file scopes: A/C = `UI/` + `Resources/`; B/D = `Core/`. A before C; B before C; D
independent, merges when ready. UI locked to a Claude agent per the standing rule.

## 8. Testing

- **`UsageAnalytics`** — full unit coverage: streak (gaps, today-boundary, all-zero, single
  day), best/least day (ties, empty), delta (zero previous → nil, negative, exact), peak day,
  provider split (hidden providers excluded), rolling windows. Deterministic via injected dates.
- **Hourly (WP-D)** — parser bucketing from fixture logs (Claude JSONL + opencode message
  fixtures) into known weekday×hour cells; DST/timezone handled via a fixed calendar.
- **Components** — SwiftUI `#Preview`s across empty / partial / full data (the sanctioned UI
  verification artifact; UI has no unit target). Include an empty-heatmap and a
  no-history Overview preview to prove honest empty states.
- Existing Core tests stay green; App scheme must build.

## 9. Risks & mitigations

- **Swift Charts learning/perf on large series** — cap plotted points (e.g. 30–90 day windows);
  donut/line inputs are small aggregates, not raw records.
- **Color creep breaking the one-accent rule** — palette is confined to `PadzyChartPalette` and
  used only inside chart/sparkline/delta components; a lint-style grep in review guards against
  metric hues leaking into buttons/nav.
- **hourlyTotals cost/size** — hour buckets over lifetime could be large; store only the
  trailing window needed for the heatmap (e.g. last 7–14 days) rather than all history.
- **Brand-logo licensing/quality** — crafted monochrome-tintable brand marks; fall back to the
  existing `ProviderMark` if an asset is missing so nothing renders blank.
- **Scope of a full rebuild of `DashboardView`** — WP-C touches it broadly; mitigate with the
  component extraction (A) first so the view is assembled from tested pieces, not inline code.

## 10. Out of scope (explicit)

- Per-metric per-day sparklines (needs a metric-split data addition).
- Settings redesign (Phase 2) and Menu-bar redesign (Phase 3) — high-level in §1, own spec later.
- Theme picker / OLED / Light mode from image 2 (Phase 2).
- Any monetization/leaderboard/share-card gamification beyond the local streak stat.
