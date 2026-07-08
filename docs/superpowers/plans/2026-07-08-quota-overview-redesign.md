# Quota Overview Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is a **taste-critical SwiftUI** build — also run the **padzy-os** skill (aitracker theme) for every view; visual craft (spacing, hierarchy, motion) is yours to get right within the tokens below.

**Goal:** Replace the rejected top quota strip with a consolidated Overview home + a guided Connections screen + monochrome provider logos, and make the window reflow without cropping.

**Architecture:** Pure UI-layer change in `AIUsageDashboardApp/UI/**` + `Resources/Assets.xcassets`. Reads the existing `DashboardViewModel` accessors (`utilization`, `aggregateUtilization`, `snapshot(for:)`, `isAvailable(_:)`). No `Core/**` edits — the frozen contract holds.

**Tech Stack:** Swift 5.9 / SwiftUI, macOS, xcodegen + xcodebuild. Test scheme `AIUsageDashboardCore`, build scheme `AIUsageDashboardApp`.

## Global Constraints

- **Work ONLY in** `../tokei-worktrees/2026-07-08-quota-overview` (branch `patch/2026-07-08/quota-overview`). Never touch the main repo or another worktree.
- **Scope IN:** `AIUsageDashboardApp/UI/**`, `AIUsageDashboardApp/Resources/Assets.xcassets`. **Scope OUT:** all `Core/**` (do NOT edit `DashboardViewModel` or any model), other providers, tests outside UI.
- **No UI→provider/network direct calls.** UI reads the view model only.
- **aitracker theme (verbatim):** ground `#131316` · surface `#1D1D22` · ink `#ECECF1` · muted `#6E6E78` · accent `#FF3B70`. Use `PadzyTheme.{ground,surface,ink,muted,accent}` and `Font.mono(size:)` / `Font.display(size:weight:)`.
- **Accent = state/action ONLY** (active/critical). Cost/plain numbers use ink. Mono for all numerals. **No shadows, no gradients, radius ≤ 4px.** Hairline (1px) structure via `HairlineDivider`. Numbered mono kickers via `EditorialKicker(number:title:)`.
- **Respect `@Environment(\.accessibilityReduceMotion)`** — no countdown/shimmer animation when set.
- Threshold colors (reuse across Overview + rows): `used% ≥ 90 → PadzyTheme.accent` (critical), `≥ 70 → Color(hex: "E8A23D")` (warning), else `Color(hex: "3DBE8B")` (nominal).
- **Regenerate the project before every build/test** (`.xcodeproj` is gitignored): `cd AIUsageDashboard && xcodegen generate`.
- Existing `AIUsageDashboardCore` tests must stay green. Commit in small steps; the pre-commit hook runs secret/artifact/format checks.

### Key existing types (consume, do not modify)
- `ProviderID`: `.claudeCode .codex .cursor .antigravity .cline` (`CaseIterable`, `rawValue` snake_case).
- `DashboardViewModel` (`@EnvironmentObject`): `snapshots`, `isLoading`, `selectedProvider: ProviderID`, `showingSettings: Bool`, `snapshot(for:) -> ProviderSnapshot?`, `isAvailable(_:) -> Bool`, `utilization: [Utilization]`, `aggregateUtilization: AggregateUtilization?`, `func refresh() async`.
- `Utilization`: `providerID`, `window: QuotaWindowType`, `usedPercent: Double` (0…100), `resetAt: Date?`, `plan: String?`, `confidence: MetricConfidence`.
- `AggregateUtilization`: `usedPercent: Double`, `coveredProviders: [ProviderID]`, `confidence`.
- `QuotaWindowType`: `.session .daily .weekly .fiveHour .monthly .credits .perModel .lifetime` (`rawValue` exists).
- `ProviderSnapshot.displayName: String`; `ProviderMetadata.planText(from: snapshot.warnings) -> String?`; `ProviderMetadata.localPaths(for:) -> [String]`.
- `ProviderVisibility.isHidden(_:) -> Bool`.
- Components: `EditorialKicker(number:title:)`, `HairlineDivider()`, `SurfaceStateView(kicker:kind:compact:onRetry:)` with `.loading(message:)`/`.empty(headline:hint:)`/`.error(headline:detail:)`.
- Connection flags (existing `@AppStorage`, UserDefaults keys): `cursorNetworkUsageEnabled`, `antigravityOnlineQuotaEnabled`. **NEW binding to add in UI:** `claudeNetworkUsageEnabled` (key already read by `ClaudeCodeProvider`; default `false`).

---

## File structure

| File | Responsibility |
|------|----------------|
| `UI/Dashboard/AppSection.swift` (new) | nav enum routing the right pane |
| `UI/Dashboard/DashboardView.swift` (modify) | drop `quotaHubStrip`; add Overview sidebar row; route pane by `AppSection` |
| `UI/Overview/OverviewView.swift` (new) | consolidated all-provider glance + aggregate header |
| `UI/Overview/ProviderOverviewRow.swift` (new) | one-line provider summary (tightest window) |
| `UI/Connections/ConnectionsView.swift` (new) | guided enable/connect list |
| `UI/Connections/ConnectionRow.swift` (new) | one agent's detect/connect/enable |
| `UI/Components/ProviderMark.swift` (new) | monochrome template logo per `ProviderID` |
| `Resources/Assets.xcassets/ProviderMarks/*` (new) | template imagesets |
| `UI/Settings/SettingsView.swift` (modify) | replace inline connection toggles with "Manage connections →" link |
| `UI/Components/ProviderQuotaTile.swift` (delete) | retired — replaced by Overview |

---

## Task 1: Navigation — Overview section, remove the strip

**Files:**
- Create: `AIUsageDashboardApp/UI/Dashboard/AppSection.swift`
- Modify: `AIUsageDashboardApp/UI/Dashboard/DashboardView.swift` (remove `quotaHubStrip` + its call at body top ~line 62 and definition ~103-137; add Overview sidebar row + pane routing)

**Interfaces:**
- Produces: `enum AppSection: Equatable { case overview; case provider(ProviderID); case settings; case connections }`, held as `@State private var section: AppSection = .overview` in `DashboardView`.
- Consumes: `viewModel.selectedProvider`, `viewModel.showingSettings`.

**Approach:** Keep `Core` untouched. Route `rightPane` on the local `section` state. Selecting a provider sets `section = .provider(id)` **and** `viewModel.selectedProvider = id`. Settings sets `section = .settings` and mirrors `viewModel.showingSettings = true` (kept in sync so no Core consumer breaks); any other transition sets `viewModel.showingSettings = false`. Overview is the default on launch.

- [ ] **Step 1: Create `AppSection.swift`**
```swift
import AIUsageDashboardCore

enum AppSection: Equatable {
    case overview
    case provider(ProviderID)
    case settings
    case connections
}
```

- [ ] **Step 2: Remove the strip.** In `DashboardView.body`, delete the `quotaHubStrip` call and the following `HairlineDivider()` at the top of the outer `VStack`; delete the `quotaHubStrip` computed property (~lines 103–137). Add `@State private var section: AppSection = .overview`.

- [ ] **Step 3: Add the Overview sidebar row** above `01 / PROVIDERS`. Mirror `settingsSidebarRow`'s structure (2px leading accent tick when active, surface fill, display font). Active when `section == .overview`. Kicker `00 / OVERVIEW`. Tapping sets `section = .overview` and `viewModel.showingSettings = false`.

- [ ] **Step 4: Route the pane.** Replace `rightPane`'s `if viewModel.showingSettings` gate with a `switch section`: `.overview → OverviewView()` (stub returning `Text("overview")` for now), `.settings → SettingsPane()`, `.connections → ConnectionsView()` (stub), `.provider → existing detail precedence`. Update `SidebarProviderRow` selection to set `section = .provider(providerID)` and `viewModel.selectedProvider = providerID`. Update keyboard up/down to move within providers and keep `section = .provider`.

- [ ] **Step 5: Build**
Run: `cd AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`; app launches to an Overview stub, no top strip, sidebar shows `00 / OVERVIEW` + providers + Settings.

- [ ] **Step 6: Commit**
```bash
git add AIUsageDashboardApp/UI/Dashboard/
git commit -m "refactor(ui): AppSection nav + Overview sidebar entry; remove quota strip"
```

---

## Task 2: ProviderMark — monochrome template logos

**Files:**
- Create: `AIUsageDashboardApp/UI/Components/ProviderMark.swift`
- Create assets: `AIUsageDashboardApp/Resources/Assets.xcassets/ProviderMarks/<provider>.imageset/` for claudeCode, codex, cursor, antigravity, cline

**Interfaces:**
- Produces: `struct ProviderMark: View { init(_ providerID: ProviderID, size: CGFloat = 18, enabled: Bool = true) }` — renders the template asset tinted `enabled ? PadzyTheme.ink : PadzyTheme.muted`, falling back to an SF Symbol if the asset is missing.

**Approach:** Each provider's official mark, reduced to a single flat silhouette, added as a **template** imageset (`"template-rendering-intent": "template"` in `Contents.json`, or set Render As = Template). Solid-shape PDF/PNG. If you cannot source a real mark cleanly, ship a clean geometric glyph per provider now (still template) and note it — recognizability can be refined later. Do NOT ship full-color marks.

- [ ] **Step 1: Add template imagesets.** For each provider create `ProviderMarks/<name>.imageset/Contents.json` with `"template-rendering-intent": "template"` and a single-scale vector (PDF) or `@1x/@2x` PNG silhouette. Name assets `mark_claude`, `mark_codex`, `mark_cursor`, `mark_antigravity`, `mark_cline`.

- [ ] **Step 2: Write `ProviderMark.swift`**
```swift
import SwiftUI
import AIUsageDashboardCore

struct ProviderMark: View {
    let providerID: ProviderID
    var size: CGFloat = 18
    var enabled: Bool = true

    init(_ providerID: ProviderID, size: CGFloat = 18, enabled: Bool = true) {
        self.providerID = providerID; self.size = size; self.enabled = enabled
    }

    private var assetName: String {
        switch providerID {
        case .claudeCode: return "mark_claude"
        case .codex: return "mark_codex"
        case .cursor: return "mark_cursor"
        case .antigravity: return "mark_antigravity"
        case .cline: return "mark_cline"
        }
    }

    var body: some View {
        Group {
            if let nsImage = NSImage(named: assetName) {
                Image(nsImage: nsImage).resizable().renderingMode(.template)
            } else {
                Image(systemName: "cube").resizable() // fallback, never blank
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .foregroundColor(enabled ? PadzyTheme.ink : PadzyTheme.muted)
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(ProviderID.allCases, id: \.self) { ProviderMark($0) }
    }.padding().background(PadzyTheme.ground)
}
```

- [ ] **Step 3: Build + eyeball the preview** (Xcode canvas or build). Expected: all five marks render monochrome in ink; disabled variant renders muted. `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**
```bash
git add AIUsageDashboardApp/UI/Components/ProviderMark.swift AIUsageDashboardApp/Resources/Assets.xcassets/ProviderMarks
git commit -m "feat(ui): ProviderMark monochrome template logos"
```

---

## Task 3: OverviewView + ProviderOverviewRow

**Files:**
- Create: `AIUsageDashboardApp/UI/Overview/ProviderOverviewRow.swift`
- Create: `AIUsageDashboardApp/UI/Overview/OverviewView.swift`
- Modify: `DashboardView` `.overview` route to use real `OverviewView` (replace stub)

**Interfaces:**
- Consumes: `viewModel.utilization`, `viewModel.aggregateUtilization`, `viewModel.snapshot(for:)`, `viewModel.isAvailable(_:)`, `ProviderMark`, `AppSection`.
- Produces: `struct OverviewView: View` (uses `@EnvironmentObject DashboardViewModel`); `struct ProviderOverviewRow: View { init(providerID:, displayName:, plan:, tightest: Utilization?, onOpen:, onConnect:) }`.

**Behavior:**
- Header kicker `00 / OVERVIEW`; aggregate line from `aggregateUtilization`: `"\(Int(round(agg.usedPercent)))% PEAK · \(agg.coveredProviders.count) LIVE"` in mono; if `nil` → `"— NO LIVE QUOTA CONNECTED"`.
- Body: `ScrollView` of one `ProviderOverviewRow` per visible provider (`!ProviderVisibility.isHidden`), sorted by the provider's tightest `usedPercent` descending.
- Tightest window per provider: `viewModel.utilization.filter { $0.providerID == id }.max(by: { $0.usedPercent < $1.usedPercent })`.
- Row with a tightest window: `ProviderMark` + displayName + plan (muted) + window-type label + `usedPercent%` (mono) + 1px fill bar (threshold color) + reset countdown; whole row is a button → `onOpen` (navigate to detail).
- Row without (`.unavailable`/nil): muted mark, no bar, a `Connect live quota →` button → `onConnect` (navigate to `.connections`).

- [ ] **Step 1: Write `ProviderOverviewRow.swift`** — layout uses flexible widths (`Spacer`, `.frame(maxWidth:.infinity)`), `.lineLimit(1)` + `.truncationMode(.tail)` on labels so it never crops; bar is `GeometryReader`- or `.frame(maxWidth:.infinity)`-based, height 4, radius ≤ 2. Countdown formats `resetAt` relative ("4d 9h" / "04:12:33"); no animation when `reduceMotion`. Include `#Preview` variants: nominal / warning / critical / unavailable.

- [ ] **Step 2: Write `OverviewView.swift`** — header + sorted `ForEach` of rows; `onOpen`/`onConnect` closures set nav (wire in Step 3). Include a `#Preview` with a mock `DashboardViewModel` covering: all-live, mixed, all-unavailable.

- [ ] **Step 3: Wire nav.** In `DashboardView`, `.overview` route renders `OverviewView(onOpen: { section = .provider($0); viewModel.selectedProvider = $0 }, onConnect: { section = .connections })` (adjust `OverviewView` init to take these closures).

- [ ] **Step 4: Build + run**
Run: `cd AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`; Overview shows aggregate + one row per provider, tightest-window only, logos present, `.unavailable` rows show `Connect →`; clicking a live row opens its detail tab.

- [ ] **Step 5: Commit**
```bash
git add AIUsageDashboardApp/UI/Overview AIUsageDashboardApp/UI/Dashboard/DashboardView.swift
git commit -m "feat(ui): consolidated Overview home — tightest window per provider + aggregate"
```

---

## Task 4: ConnectionsView + ConnectionRow (in-app enable, incl. Claude)

**Files:**
- Create: `AIUsageDashboardApp/UI/Connections/ConnectionRow.swift`
- Create: `AIUsageDashboardApp/UI/Connections/ConnectionsView.swift`
- Modify: `DashboardView` `.connections` route (replace stub); `SettingsView` (Task 5)

**Interfaces:**
- Produces: `struct ConnectionsView: View`; `struct ConnectionRow: View { init(providerID:, storageKey: String, disclosure: String, help: String) }` holding `@AppStorage(storageKey) private var enabled`.
- Consumes: `viewModel.isAvailable(_:)`, `viewModel.snapshot(for:)`, `ProviderMark`, `viewModel.refresh()`.

**Behavior per row:** `ProviderMark` + display name; detected state (`INSTALLED`/`NOT FOUND` from `viewModel.snapshot(for:) != nil` / availability); an **Enable** `Toggle` (`.toggleStyle(.switch).tint(PadzyTheme.accent)`) bound to the `@AppStorage` key; on change → `Task { await viewModel.refresh() }` (same pattern as existing Settings toggles); a muted `disclosure` line and, when enabled but no data, the `help` line. Rows: Claude (`claudeNetworkUsageEnabled`, disclosure "Reads your own Claude account. May break if Anthropic changes their API.", help "Run `claude` once to refresh your login."), Cursor (`cursorNetworkUsageEnabled`), Antigravity (`antigravityOnlineQuotaEnabled`, help "Requires the Antigravity app to be open.").

- [ ] **Step 1: Write `ConnectionRow.swift`** with the fields above; `#Preview` for installed+on / installed+off / not-found.
- [ ] **Step 2: Write `ConnectionsView.swift`** — kicker `CONNECTIONS`, `ScrollView` of the three `ConnectionRow`s separated by `HairlineDivider`. A top intro line: "Connect a coding agent to read its live quota. Local-first — off by default."
- [ ] **Step 3: Wire** `DashboardView` `.connections` route to `ConnectionsView()`.
- [ ] **Step 4: Build + run**
Run: `cd AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`; toggling Claude ON → after refresh, Claude's Overview row + detail tab light with live windows (session/weekly); OFF → back to empty. Cursor/Antigravity toggles behave as before.
- [ ] **Step 5: Commit**
```bash
git add AIUsageDashboardApp/UI/Connections AIUsageDashboardApp/UI/Dashboard/DashboardView.swift
git commit -m "feat(ui): guided Connections screen — in-app enable incl. Claude live quota"
```

---

## Task 5: Settings link + fit-to-window audit

**Files:**
- Modify: `AIUsageDashboardApp/UI/Settings/SettingsView.swift` (replace the inline Cursor/Antigravity connection `Toggle`s ~lines 56–95 with a single link)
- Modify: `AIUsageDashboardApp/UI/Dashboard/DashboardView.swift` (`minWidth`/reflow)

**Interfaces:** Consumes `AppSection`. Settings gains a "Manage connections →" button that routes to `.connections`. Requires passing a nav callback into `SettingsPane`/`SettingsView` (add an `onOpenConnections: () -> Void` init param).

- [ ] **Step 1: Replace inline connection toggles** in the `01`-section of `SettingsView` with one button "MANAGE CONNECTIONS →" (display font, styled like `settingsSidebarRow`) that calls `onOpenConnections`. Keep the section's intro copy trimmed to one line pointing to Connections. Leave `notificationsEnabled` + `02 QUOTA ALERTS` untouched. Remove the now-unused `cursorNetworkUsageEnabled`/`antigravityOnlineQuotaEnabled` `@AppStorage` decls **only if** nothing else in the file reads them (they now live in `ConnectionRow`).
- [ ] **Step 2: Thread the callback** — `SettingsPane`/`SettingsView` init takes `onOpenConnections`; `DashboardView` passes `{ section = .connections }`.
- [ ] **Step 3: Fit-to-window.** Lower `DashboardView`'s `.frame(minWidth: 860, minHeight: 560)` to `minWidth: 640, minHeight: 480`. Verify Overview rows + detail reflow (labels truncate, bars flex) at 640pt; nothing clips. Add a narrow-width (`.frame(width: 640)`) `#Preview` to `OverviewView`.
- [ ] **Step 4: Build + resize test**
Run: `cd AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`; drag the window to its minimum — Overview, Connections, and detail all reflow with no cropped text/bars; Settings shows the Connections link.
- [ ] **Step 5: Commit**
```bash
git add AIUsageDashboardApp/UI/Settings/SettingsView.swift AIUsageDashboardApp/UI/Dashboard/DashboardView.swift AIUsageDashboardApp/UI/Overview/OverviewView.swift
git commit -m "feat(ui): Settings→Connections link + fit-to-window reflow (min 640×480)"
```

---

## Task 6: Retire ProviderQuotaTile + final verification

**Files:**
- Delete: `AIUsageDashboardApp/UI/Components/ProviderQuotaTile.swift`

- [ ] **Step 1: Confirm no references** remain: `rg -n ProviderQuotaTile AIUsageDashboardApp` → expect zero hits (Task 1 removed the strip). Delete the file.
- [ ] **Step 2: Full gate**
Run: `cd AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test`
Expected: tests pass, 0 failures (unchanged count — no Core edits).
- [ ] **Step 3: App build**
Run: `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Commit + Bible note**
```bash
git rm AIUsageDashboardApp/UI/Components/ProviderQuotaTile.swift
git commit -m "refactor(ui): retire ProviderQuotaTile (replaced by Overview)"
```
Then append a completion note to `tasks/patch-bibles/2026-07-08.md` §W2.6 (branch+commits, done, stubbed — e.g. real vs geometric logos, tests run, files touched, risks) and commit.

---

## Acceptance (whole plan)
- No top quota strip. Sidebar: `00 / OVERVIEW`, `01 / PROVIDERS`, Settings.
- Overview: aggregate headline + one glanceable row per provider (logo + tightest window only + reset). No duplication of the detail tab's full breakdown.
- Connections screen enables Claude/Cursor/Antigravity in-app; Claude lights up after enabling.
- Provider logos render monochrome (ink/muted), on-theme.
- Window resizes to 640×480 with zero cropping.
- `AIUsageDashboardCore` green; App builds; no `Core/**` file changed (`git diff --name-only dev...HEAD` shows only `UI/**`, `Resources/**`, `tasks/**`).
