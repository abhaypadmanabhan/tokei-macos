# WP-5 — finish the visual redesign (P4–P8)

Worktree `2026-07-19-ui-ia-consolidation` · branch `patch/2026-07-19/ui-ia-consolidation`.
Baseline @ 203eed4 verified GREEN: 302 Core tests pass · app BUILD SUCCEEDED.

Process per surface: read target → build to mockup with REAL bindings → build-green → commit small.
Scope lock: `UI/` + `Assets.xcassets/ProviderMarks/` + `UI/MenuBar/`. Never `Core/`, `App/`, `project.yml`, `UI/MenuBar/MaxxerMath.swift` API.

- [x] **P4 Value** — DONE @ 94d3ef8. 84px hero · inline tier chip · "$api from $plan" · ◆ insight · hairline rows · TOTAL · excluded footnote w/ lifetime fold · row-tap drill / unpriced→set-plan-cost.
- [x] **P5 Agents** — DONE @ 2d2c933. Per-agent cards: tinted glyph · tier chip · path · Show (ProviderVisibility) · Watching+Rescan · LIVE QUOTA off/connecting/live (`.padzy`, connectable-only) · Cursor disclosure + footer note.
- [x] **P6 Drill-in** — DONE @ 7253d9c. Unified `ProviderDetailView` (full + plan-only PLAN&CREDITS), plan-only rerouted in `DashboardView`, `LineTrendChart` tint added. Reviewed subagent diff + independent build.
- [x] **P7 Menu bar** — DONE @ 79ec8e4. Popover rebuilt: hero+Δ · Plan value+tier · Tightest quota+dot+who · top-3 · Open Tokei/Quit. dismissPopover preserved. MenuBarLabel left (already correct).
- [x] **P8 cleanup** — DONE @ f9418b6 (dead files + ramps + params) · 94181cf (capabilityPane + 16 helpers) · 09fcfaa (/simplify safe wins). SurfaceStateView left as-is (already honest/themed from P0). Reflow code in place (ViewThatFits/FlowLayout/width prefs).
- [x] WP-5 note appended to `tasks/patch-bibles/2026-07-19.md` §8. No test UserDefaults to restore (Core untouched, previews use throwaway suites).

Full gate GREEN: 302 Core tests · app BUILD SUCCEEDED.
DEFERRED /simplify follow-ups + out-of-scope items documented in Patch Bible §8.
**VISUAL VERIFY still owed by user** (no Screen Recording perm → screencapture black). Launch this worktree's Tokei.app, eyeball P4–P8 + 640×480 reflow before merge.
