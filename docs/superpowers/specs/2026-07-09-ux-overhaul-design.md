# UX Overhaul — WP-2 Design (2026-07-09)

Branch: `patch/2026-07-09/ux-overhaul`. Source of truth: Patch Bible §WP-2. This
doc records the design decisions for the `+` add-agent flow and the cross-cutting
changes, per the brainstorming skill. The spec was pre-approved via `/morning-patch`;
this agent executes it (dispatched subagent).

## 1. Kill the numbered "NN / TITLE" kicker
- Delete `EditorialKicker` (both inits) from `PadzyTheme.swift`. Replace with
  `SectionLabel(_ title:)` — same mono/tracked/muted/uppercase treatment, **no number**.
- Replace inline literals: `"00 / OVERVIEW"`→`OVERVIEW`, `"01 / TODAY"`→`TODAY`,
  `"03 / STATUS"`→`STATUS`, `metricBlock "\(number) / \(title)"`→`title`.
- `SurfaceStateView`: `kicker: (number,title)?` → `header: String?` (unnumbered).
- Call sites: DashboardView, OverviewView, SettingsView, ConnectionsView,
  MenuBarView, ProviderDetailView, SurfaceStateView.

## 2. Settings revamp (#39)
- Real hierarchy: grouped sections with unnumbered `SectionLabel`, hairline-bounded
  surface blocks, section intro/description, honest states. Drop the flat numbered list.
- Groups: AGENTS (visibility = added/removed, links to Add Agent + Connections),
  ALERTS, REFRESH, ABOUT. Polished switch rows, consistent spacing.

## 3. Responsive window (buttons hide on max/min)
- `statusStrip`: wrap in `ViewThatFits(.horizontal)`:
  - wide: pulse + full status line + Spacer + labeled `SYNC NOW`.
  - tight: pulse + shortened status (drop WATCHING path) + Spacer + icon-only sync
    (`arrow.clockwise`). No clipping at 640×480.
- Min stays 640×480; window resizable. Verify small/mid/full via previews.

## 4. `+` Add-agent / link-a-coding-agent flow
- **Model**: `AddAgentModel` — `isAdded(id) = !ProviderVisibility.isHidden(id)`;
  `add(id)=setHidden(false)`, `remove(id)=setHidden(true)`.
- **Detection**: `AgentDetection.isInstalled(id)` — disk-only `FileManager` existence
  check over `ProviderMetadata.localPaths(id)` (expand `~`). No Core, no secrets.
- **First-run seeding** (`tokei.onboarding.seeded.v1`): on first launch, for each
  provider `setHidden(!isInstalled)`. New user w/ no agents → blank canvas. Existing
  user → installed providers stay visible (no regression).
- **`+` button**: Overview header (top-right) + a `+ ADD AGENT` sidebar row under
  PROVIDERS. Opens `AddAgentSheet` (`.sheet`).
- **AddAgentSheet** two regions:
  - DETECTED — providers installed on disk & not yet added: `ProviderMark` logo +
    name + `DETECTED` + one-click `ADD`; plus `ADD ALL DETECTED`.
  - ALL AGENTS (manual) — every provider w/ logo; added ones show `ADDED`/remove,
    others `ADD` even when undetected.
- **Blank canvas**: Overview `entries` empty → centered blank-canvas state leading
  with the `+` ("LINK A CODING AGENT"), not empty rows.

## 5. Opencode as an addable provider
- `ProviderID`: add `case opencode = "opencode"` (last; identical shared line, §4).
- `ProviderMark.assetName`: `.opencode → "mark_opencode"`.
- `ProviderMetadata.localPaths`: `.opencode → ["~/.local/share/opencode"]`.
- New monochrome template asset `Resources/Assets.xcassets/ProviderMarks/mark_opencode.imageset`
  (SVG, `template-rendering-intent = template`). Non-connectable (local logs only) →
  existing default branches handle it.

## 6. Maxed-out emphasis = accent intensity (no new hue)
- `ProviderOverviewRow.thresholdColor` currently returns amber `#E8A23D` / green
  `#3DBE8B` — decorative hues that violate the one-accent rule. Replace with
  accent-intensity: `<70` = ink · `70–89` = accent@0.6 · `≥90` = full accent + `!!`.
- Sidebar/detail critical states already use `!!` + accent; keep consistent.

## Testing
- `xcodegen generate` (project is gitignored) then Core `test` scheme stays green.
- `#Preview`s: blank canvas, detected sheet, manual menu, revamped Settings, window
  sizes (small/mid/full). Build App scheme to confirm compile.

## Risks
- Seeding must run exactly once and never hide a provider an existing user relies on
  → keyed by installed-on-disk, idempotent flag.
- Broad `EditorialKicker` removal touches many files → mechanical, previews verify render.
- Compiles against `ProviderID.opencode` added here (identical to WP-1's line).
