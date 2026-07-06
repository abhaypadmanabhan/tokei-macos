# Relay Leg 3 — Antigravity

## Changed files
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel.swift`
- `AIUsageDashboard/AIUsageDashboardApp/UI/Dashboard/DashboardView.swift`
- `AIUsageDashboard/AIUsageDashboardApp/UI/MenuBar/MenuBarView.swift`
- `AIUsageDashboard/AIUsageDashboardApp/App/AIUsageDashboardApp.swift`

## What works
- **Dynamic Selection**: `DashboardViewModel` manages `selectedProvider` and publishes updates. Sidebar is built dynamically from all cases of `ProviderID`. Available rows (determined via `isAvailable`) display today's token total and show hover/click affordances, while unavailable ones are visual skeletons and not clickable.
- **Keyboard Navigation**: Arrows ↑/↓ navigate selection only through available/active providers via `.focusable()` and `.onMoveCommand` on the view.
- **Quota Gauges & Countdown**: Active quota windows (Codex) render below TODAY and above the metric blocks. A horizontal hairline bar represents `usedPercent` with accent-colored fill. Resets countdown is reactive and ticks down every second using a local state timer. High usage (>90%) shows a `!!` indicator.
- **VoiceOver Integration**: Gauges are equipped with detailed accessibility labels, e.g. `"Codex session window 29 percent used, resets in 3 hours"`.
- **Cost Display**: If present (`costUsage != nil`), Cline lifetime dollar cost (e.g. `$22.74`) renders in the today usage breakdown and in the top-right corner of the `LIFETIME` metric block.
- **Generalized Status Bar**: Synced timestamp, confidence level, and watch path update to match the selected provider.
- **Menu Bar updates**: The menu bar text sums today's token usage across all active providers. Clicking the menu bar icon displays a panel with dense rows for each active provider showing today's tokens, plus the Codex session quota (e.g. `S 29%`).

## Stubbed or skipped
- No functional components outside of UI and ViewModel were modified (strictly conforming to leg specifications).
- No new provider features or parsers were introduced.

## Tests run
- `xcodegen generate`
- `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build` — succeeded.
- `xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test` — 48 tests passed, 0 failures.

## Risks
- The arrow keys navigation relies on focus being on the dashboard view. The main view sets focusable but SwiftUI focus states can sometimes behave differently depending on active system controls.
