# WP-5 handoff — visual redesign to match `Tokei.html` mockup

Checkpoint written 2026-07-20. Previous session ran out of context. This file is
the single source of truth to resume. Everything below is durable; the session
scratchpad is gone.

## Where the code is

- **Worktree:** `/Users/abhayp/Downloads/Projects/tokei-worktrees/2026-07-19-ui-ia-consolidation`
- **Branch:** `patch/2026-07-19/ui-ia-consolidation` @ `fe568b7` — clean, nothing
  uncommitted. WP-4 (sidebar → tabs + chip strip + drill-in) is DONE and committed
  (9 commits). NOT merged, NOT pushed.
- **Scope lock:** `AIUsageDashboardApp/UI/` only. Never touch `Core/`, `App/`,
  `project.yml`, `MenuBar/*` behavior contracts, or Bible §4 frozen contracts.
- **Build/test:**
  ```
  cd AIUsageDashboard && xcodegen generate
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test   # 302 pass
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp  -destination 'platform=macOS' build
  ```
- **DerivedData for THIS worktree** (used for visual verify — do not confuse with the
  user's `AI_tracker/.../build/dev` instance):
  `AIUsageDashboard-dfmeddobpfrxvxeqtepfotxljyha`. Always confirm the running app is
  this build before screenshotting (WP-2 lesson: wrong-build trap).

## What WP-5 is

The user built a target design in Claude Design, downloaded as
`/Users/abhayp/Downloads/Tokei.html` (a self-unpacking bundle). WP-4 already did the
IA (tabs, chips, drill-in, gear). WP-5 makes the built UI **look like the mockup** and
adds the surfaces the mockup was missing.

The user will paste a NEW, extended design at the start of the resume session (they
took the gap-prompt below to Claude Design). Build against that new one; the current
mockup is the style reference.

## Design reference (durable copies in this folder)

- `design-reference.html` — the extracted, runnable template markup + component logic
  from `Tokei.html` (open in a browser, or read it — it has exact values/animations).
- `ref-overview.png`, `ref-value.png`, `ref-drill.png` — rendered screenshots.
- Original bundle still at `/Users/abhayp/Downloads/Tokei.html`.
- To re-extract: the `<script type="__bundler/template">` payload is JSON-encoded HTML;
  the `<script type="text/x-dc">` block after `</x-dc>` is the component JS (state,
  providers array, renderChart/renderHistory, styles).

## Design tokens (from the mockup — USE THESE, they differ from PadzyTheme)

The mockup is a step darker and flatter than the shipped app. Decide with the user
whether to move `PadzyTheme`/`PadzyRadius` or keep shipped values — the mockup uses:

- ground `#0B0B0D` · window `#0F0F12` · cell `#0F0F12` · hairline `#1C1C21` ·
  border-2 `#26262C`
- ink ramp: `#ECECF1` (primary) → `#C4C4CC` → `#9A9AA4` → `#6E6E78` → `#54545C` (faintest)
- accent `#FF3B70` (hover `#ff5a86`)
- per-agent tints: claude `#C77D5A`, codex `#5FA88C`, cursor `#9AA0AA`, cline `#8A93E6`,
  antigravity `#D2A15C`, gemini `#6D93DB`, opencode `#B98BD0`
- quota color by pct: `≥90 accent` · `≥60 #D2A15C` · else `#6E6E78`
- tier chip (playful ON): green `#6BBF8A`; (OFF): `#9AA0AA`
- radius: 10px window, 4px cells — mockup, NOT the ≤4px Bible line (already a documented
  override in PadzyTheme; confirm it still holds)
- fonts: `ui-sans-serif`/SF Pro for text, `ui-monospace`/SF Mono for ALL numbers
- animations: `tk-up` (fade+rise), `tk-fade`, `tk-draw` (line stroke), `tk-dot`,
  `tk-grow` (bar scaleX), `tk-pulse` (skeleton). 650ms ease-out cubic on metric/tab/
  drill change. ALL must have a `prefers-reduced-motion` static path.

## USER DIRECTIVES (verbatim intent — hold these)

1. "match it as best as you can, make it fluidic and clean, good use of colours,
   product sense and design, no clutter of text."
2. **No `01/` `02/` numbered kickers** — mockup dropped them; plain "Overview"/"Value"
   tabs. This overrides padzy-os Invariant 2 for THIS surface (already user-confirmed
   pattern, see tasks/lessons.md 2026-07-08 website entry).
3. **Confidence stays SUBTLE** — no "REPORTED/ESTIMATED/LOCAL" chips shouting. Mockup
   does it as a dotted underline under the number + a tooltip (`title=`). Keep that.
   Drill-in header may show one small tier word; the agent grid must not.
4. **Heatmap + donut STAY** (user decided this explicitly). They were absent from the
   first mockup; the user is bringing them back in the new design.
5. Use Mobbin MCP when a pattern needs a reference.

## Gap prompt already given to the user (what the new design should add)

The user took this to Claude Design; the returned design should cover:
- Overview: donut (usage split by agent, per-agent tint, total in centre) + activity
  heatmap (7×24, single-hue ramp) + patterns row (current/longest streak, best day,
  quietest day, daily average).
- Persistent bottom status bar: last sync, confidence, watched path, Sync now.
- Drill-in extras: watched path + last sync + tier in header; circular gauge for
  tightest window; peak-hour + this-week stats; quota windows grouped by model; pace
  marker (linear-burn vs actual, verdict ahead/on pace/headroom); plan-only variant
  (plan, credits, accepted lines, honest "not measured locally", enable-online action);
  "route work here" hint on the emptiest agent.
- Connections screen: per-agent live-quota opt-in, 3 states (off/connecting/live).
- Settings drawer with real depth: per-agent monthly plan cost (blank=unset not $0),
  data sources w/ paths + rescan, show/hide agents, quota alert thresholds, appearance
  + accent, notifications, version + update check.
- Add-agent: detected-first list.
- Menu bar: 4 readouts (tokens today / tightest % / all-time / icon only).
- Constraint: real macOS window, min 640×480, show reflow.

## OPEN DECISIONS for the resume session (ask the user)

1. **Settings**: mockup uses a 340px right drawer + scrim. Shipped is a full-pane
   7-card grid holding the plan-cost fields. Drawer-with-all-controls vs keep-full-pane.
   (Was about to ask when session ended — user hasn't answered.)
2. **Token migration**: move `PadzyTheme` ground `#131316`→`#0B0B0D` etc. app-wide, or
   scope the darker palette to the redesigned surfaces? App-wide is cleaner but touches
   the menu bar's rendered look (shipped + verified — re-verify if changed).
3. Heatmap/donut placement: on Overview (user wants them) vs drill-in — confirm which.

## Real data model (from the mockup's providers array — for realistic previews)

7 agents: claude (533M today, reported, quotas weekly 46% / 5h 22%, $200 plan, 3.6×,
lifetime 2.31B), codex (8.9M, estimated, $20, 2.9×), cursor (1.38M, local, $20, 2.1×),
cline (4.2M, local, no quota/pay-as-you-go, $5, 2.5×), antigravity (no tokens, quota
71%, $5, unavailable), gemini (signed out), opencode (0.62M, local, no plan cost set).
claude token split today: input 41.2M / cache-read 402.8M / cache-write 63.5M / output 25.5M.

## Files WP-4 created/owns (WP-5 will mostly edit these)

- `UI/Dashboard/DashboardTabBar.swift` (tabs + range + gear), `ProviderChipStrip.swift`,
  `DashboardView.swift` (shell, drill-in, keyboard nav), `AppSection.swift` (DashboardTab).
- `UI/Overview/OverviewView.swift`, `UI/Value/ValueView.swift`, `UI/Charts/*` (donut,
  heatmap, line, area, gauge, sparkline, Cards), `UI/ProviderDetail/ProviderDetailView.swift`.
- `UI/Components/PadzyTheme.swift` (tokens), `SurfaceStateView.swift` (states),
  `ProviderOverviewRow.swift` (quota row + pace), `MenuBar/MaxxerMath.swift` (chip stat,
  merged-today, lifetime, formatting — the ONLY UI file compiled into Core tests).
- `Tests/MaxxerTests/MaxxerChipStatTests.swift`.

## Process reminders

- padzy-os skill (aitracker theme) + frontend-design. Mockup loop optional now (design
  already exists). Mobbin MCP available.
- Small reviewable commits. Pre-commit hook runs no-secret/no-large-artifact/format.
- Visual verify REQUIRED before "done" — build App scheme, launch THIS worktree's
  DerivedData build, screenshot every state + 640×480 reflow. Build-pass ≠ verify.
- Restore any UserDefaults you write for testing (provider_hidden_*, menuBarDisplayMode,
  maxxer.planCost.*). Relaunch the user's dev build when finished.
- Append a WP-5 note to `tasks/patch-bibles/2026-07-19.md` §8 when done.
