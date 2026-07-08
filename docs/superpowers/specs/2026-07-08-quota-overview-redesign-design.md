# Design — Quota Overview Redesign + Guided Connections

- **Date:** 2026-07-08
- **Status:** Approved (design), pending spec review
- **Supersedes:** the `quotaHubStrip` / `ProviderQuotaTile` top strip merged in `patch/2026-07-08/quota-tiles-ui` (#21, P1.1)
- **Product:** Tokei (`ai.padzy.tokei`), local-first macOS AI-usage dashboard, "aitracker" theme

## 1. Problem

The shipped quota strip (rejected in manual test) has five defects:

1. **Duplication** — the top strip renders the same windows the per-provider detail tab already shows.
2. **No consolidated glance** — there is no real "dashboard/home"; the strip is just repeated tiles.
3. **Space waste** — a full-height tile row consumes the top of the window for low-density info.
4. **Crops / no reflow** — content does not fit or auto-resize to the window; information is clipped.
5. **No logos** — providers are text-only; no recognizable brand marks.

Plus a functional gap from P0.3: **no in-app control** to enable Claude live quota — the
`claudeNetworkUsageEnabled` flag exists but has no UI, so a shipped user cannot turn it on.

## 2. Goals

- A genuine **Overview home** that consolidates all providers into a one-glance summary, distinct
  in altitude from the per-provider detail tabs (no duplication).
- A **guided Connections** surface so any user can enable/connect a coding agent's live quota safely.
- **Monochrome brand marks** per provider, on-theme.
- **Fit-to-window**: content reflows and scrolls; nothing crops.

Non-goals: changing any `Core/**` logic, the sampler (P0.4), heatmap, or Maxxer score. This is a
UI-layer redesign consuming the existing view-model contract.

## 3. Architecture

All work is in `AIUsageDashboardApp/UI/**` + `Resources/Assets.xcassets`. No `Core` change; the
frozen contract (§4 of the Patch Bible) holds — the UI reads only the view model.

### 3.1 Navigation
`DashboardView` today: `quotaHubStrip` + (`sidebar` | `rightPane`) + `statusStrip`.

- **Remove** `quotaHubStrip`.
- **Sidebar** gains a pinned top entry `00 / OVERVIEW` (numbered mono kicker) above the provider
  list; Settings stays pinned at bottom.
- A lightweight nav enum drives `rightPane`: `.overview` → `OverviewView`; `.provider(ProviderID)`
  → existing `ProviderDetailView`; `.settings` → `SettingsView` (unchanged); `.connections` →
  `ConnectionsView`.
- Keyboard up/down selection (existing `selectNext/PreviousVisible`) includes the Overview row.

### 3.2 OverviewView (new)
- **Header:** aggregate headline from the Wave-1 utilization spine —
  `viewModel.aggregateUtilization` → `"AGGREGATE  {peak}% peak · {coveredProviders} live"`.
  No new computation; if the aggregate is unavailable, show `"— no live quota connected"`.
- **Body:** a vertical `ScrollView` of one **ProviderOverviewRow** per *visible* provider
  (respects the existing `ProviderVisibility` hide toggle), sorted by used% descending (tightest first).
- **ProviderOverviewRow** contents:
  - `ProviderMark` (monochrome logo, ink; muted if provider unavailable/disabled)
  - provider display name + plan label (from existing provider metadata)
  - the provider's **single tightest window only** (max `usedPercent` across its `quotaWindows`):
    window-type label, `used%` (mono), a hairline fill bar, and a reset countdown.
  - color: `#FF3B70` ≥90 / `#E8A23D` ≥70 / `#3DBE8B` otherwise.
  - `.unavailable`/not-connected provider → muted row, no bar, with a `Connect live quota →`
    button that deep-links to `ConnectionsView`.
  - the whole row (when it has data) is a button → navigate to that provider's detail tab.
- Rationale for "tightest window only": the detail tab owns the full per-window breakdown; Overview
  answers "am I about to get capped anywhere" at a glance without repeating the tab.

### 3.3 ConnectionsView (new)
- Reached from a **"Manage connections →" link in Settings** and from Overview's `Connect →`
  deep-link. Not a separate top-level sidebar entry — keeps the sidebar to Overview + providers + Settings.
- One **ConnectionRow** per connectable provider (Claude Code, Cursor, Antigravity; extensible):
  - detected state: `Installed` / `Not found` (reuse each provider's availability check)
  - connected state + freshness: `Connected · updated {n}m ago` / `Not connected`
  - a single **Enable** `Toggle` bound to that provider's `@AppStorage` flag
    (`claudeNetworkUsageEnabled` — NEW UI binding; `cursorNetworkUsageEnabled`,
    `antigravityOnlineQuotaEnabled` — existing).
  - plain-language disclosure: *"Reads your own {provider} account. May break if the provider
    changes their API."*
  - error/help line on failure: e.g. `Run \`claude\` once to refresh your login.`
- This screen is the single home for enablement; the scattered Settings toggles either move here or
  link here (see §3.5).

### 3.4 ProviderMark (new) + assets
- `ProviderMark(providerID:)` view maps `ProviderID` → a **template** image asset.
- Assets: each provider's official mark, recolored to a single flat shape, added to
  `Assets.xcassets` with **Render As = Template Image**; rendered `.foregroundColor(PadzyTheme.ink)`
  (or `.muted` when disabled). Template rendering strips brand color → aitracker-compliant and
  low trademark risk.
- Fallback: a generic SF Symbol if an asset is missing, so the view never blanks.

### 3.5 SettingsView
- Replace the existing inline Cursor/Antigravity toggles with a single **"Manage connections →"**
  link to `ConnectionsView` (one source of truth for enablement; Claude joins there). Keep
  `notificationsEnabled` and other non-connection settings inline as-is.

### 3.6 Fit-to-window
- Overview rows live in a `ScrollView` — many providers scroll, never crop.
- Audit `DashboardView`/detail for fixed frames forcing overflow; lower `minWidth` (currently 860)
  to a value the content reflows into, and let bars/labels use flexible width + `.layoutPriority`
  and truncation so a narrow window shrinks gracefully instead of clipping.
- Detail pane content stays in its existing `ScrollView`.

## 4. Components (isolation)

| Unit | Purpose | Depends on |
|------|---------|-----------|
| `AppSection` enum | drives rightPane routing | — |
| `OverviewView` | consolidated all-provider glance | view model, `ProviderOverviewRow` |
| `ProviderOverviewRow` | one-line provider summary (tightest window) | `ProviderMark`, theme |
| `ConnectionsView` | guided enable/connect per agent | `ConnectionRow`, `@AppStorage` flags |
| `ConnectionRow` | one agent's detect/connect/enable | view model availability, theme |
| `ProviderMark` | monochrome logo per provider | `Assets.xcassets` template images |

Each is independently previewable and testable; none reaches into `Core`.

## 5. Data flow

`DashboardViewModel` (existing) → `OverviewView` reads `aggregateUtilization` + per-provider
`snapshot(for:).quotaWindows` (computes tightest window inline, a pure `max(by: usedPercent)`).
`ConnectionsView` reads provider availability + `@AppStorage` flags; toggling a flag flips the
provider's `.quota` capability on next refresh (existing P0.3 path). No UI→provider direct calls.

## 6. Error / empty / loading states

- Overview with no live providers → aggregate shows `— no live quota connected`; every row shows the
  `Connect →` affordance.
- A provider mid-fetch → row shows a loading shimmer (reduced-motion aware) not a zero bar.
- Connection error → `ConnectionRow` shows the help line; app never errors out.

## 7. Testing

- SwiftUI previews: Overview (all-populated / mixed / all-unavailable / narrow-width 640pt),
  `ProviderOverviewRow` (nominal/warning/critical/unavailable), `ConnectionsView`
  (installed+connected / installed+off / not-found / error).
- `AIUsageDashboardCore` test suite stays green (no Core change).
- Manual: window resize down to min shows no cropping; enabling Claude in Connections lights its
  Overview row + detail tab after refresh; disabling returns to the empty state.

## 8. Rollback

Pure UI branch merged `--no-ff` → one `git revert -m 1 <sha>`. The retired `ProviderQuotaTile` /
`quotaHubStrip` can be restored from history if needed.

## 9. Out of scope / next

- Pace notch (P1.2), heatmap (P1.3), route-here chip (P1.4), menu-bar tightest-window (P1.5),
  sampler (P0.4) — unchanged, later waves.
- Real (non-template) brand assets sourcing/verification is a design-asset task; template
  monochrome marks are the shipping form.
