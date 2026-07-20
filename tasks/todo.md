# WP-5 — Visual redesign wiring (Tokei Dashboard.html → SwiftUI)

Branch `patch/2026-07-19/ui-ia-consolidation`. Scope lock: `AIUsageDashboardApp/UI/` + `Assets.xcassets/ProviderMarks/` + `MenuBar/`. Never touch `Core/`, `App/`, `project.yml`, or Bible §4 frozen contracts. Wire new UI to the REAL Core view models — the mockup's providers array is illustrative only.

## Locked decisions (2026-07-20)
- Settings = **380px right drawer + scrim** (plan-cost inline; data-sources → Agents tab). Retire the 7-card `SettingsPane`.
- Palette = **migrate PadzyTheme app-wide** to the darker mockup ramp. Re-verify menu bar + status icon after.
- Logos = **refine existing `ProviderMark` vector marks, tint per-agent**. Draw any missing (codex/cline/opencode/gemini).

## Held directives
- No `01/` `02/` numbered kickers (plain tab labels; unnumbered mono section kickers OK).
- Confidence SUBTLE: dotted underline + `title=`/help tooltip. No shouting chips. Drill header may show one small tier word.
- Heatmap + donut STAY on Overview.
- Mono for numbers/paths/kickers ONLY; sans for names/body/buttons. 5-step ink ramp for hierarchy.
- Per-agent tints are DATA/identity color (low-chroma); accent FF3B70 stays state-only.
- All `tk-*` animations need a `prefers-reduced-motion` static path.
- Keep the 3 real strengths: honest empty/loading/error, `—` not `0`, ViewThatFits reflow @ 640×480.

## Phase 0 — Foundation: tokens + motion  (DONE — build green)
- [x] PadzyTheme app-wide dark ramp: ground `0B0B0D` · window/cell `0F0F12` · panel `131316` · hairline `1C1C21` · border2 `26262C` · scrim.
- [x] Ink ramp: `ECECF1 · C4C4CC · 9A9AA4 · 6E6E78 · 54545C` (+ good/warn/danger status hues).
- [x] Accent `FF3B70` + hover `FF5A86`. `quotaColor(pct)`. `PaceVerdict(pct,elapsed)` → word+color.
- [x] `AgentTint.color(_:)` map (new file, needs Core).
- [x] `PadzySpace` scale + `Font.sans` + `Font.mono(weight:)`.
- [x] `PadzyMotion` tokens (settle/quick/toggle). Radii add window 10 / cell 4 / chip 4.
- [x] `TokeiStatusIcon` accent now `NSColor(PadzyTheme.accent)`; heatmap ramp + areaGradient recoloured neutral; TokenFormatter → mockup fmt (nil→"—").

## Phase 1 — Agent identity / logos  (1 commit)
- [ ] Tinted glyph container (`glyphCss` equiv): rounded square, `tint@14%` bg, `tint@55%` border, tint text/mark.
- [ ] Refine `ProviderMark`; ensure all 7 marks exist + tint per-agent. One toggle style (`PadzyToggle`) app-wide; retire native `.switch`.

## Phase 2 — Shell  (1–2 commits)
- [ ] TabBar: plain `Overview / Value / Agents`, 2px tick, no kicker. Range chips only on Overview+usage. Gear → settings drawer.
- [ ] Pressure banner (tightest live quota; bg tinted by pct).
- [ ] Persistent status bar (sync dot+label, conf mix, path, Sync now).
- [ ] Settings drawer overlay (scrim + 380px): plan cost · quota alerts (steppers) · appearance+accent · notifications · version/update. Real controls only.
- [ ] Add-agent drawer (detected-first + all agents). Wire to real Core state.

## Phase 3 — Overview  (1–2 commits)
- [ ] Metric selector Usage / Quota. Hero 62px mono + delta + sub.
- [ ] Main line/area chart (neutral ink, cap line, accent end dot, hover). Restyle `LineTrendChart`.
- [ ] Agent grid (headroom dot · tinted glyph · name · stat + confidence underline). Replaces chip-strip-as-KPI.
- [ ] Usage-split donut (per-agent tint) + legend. Weekday bars (tk-grow, busiest=accent). Daily-avg + active-streak. Heatmap (7×24 single neutral hue) + when-you-work.

## Phase 4 — Value  (1 commit)
- [ ] PLAN VALUE hero 84px + tier chip + insight (◆). Per-agent rows (plan→api w/ confidence underline, mult). TOTAL row. Excluded note.

## Phase 5 — Agents tab  (1 commit)
- [ ] Promote Connections → 3rd tab. Per-agent cards: tinted glyph · name · tier chip · path · Show toggle · watch dot+rescan · LIVE QUOTA state (off/connecting/live) toggle.

## Phase 6 — Drill-in (ProviderDetail)  (1–2 commits)
- [ ] Back · tinted glyph · name · route-work chip · planLabel · confidence · meta grid · insight · gauge+verdict · stats.
- [ ] PLAN & CREDITS (plan-only variant: credits bar, not-measured note, enable-sync). Quota-windows-by-model + pace markers. Daily history (agent tint). Token split. De-dup the quota-row shared with the shell.

## Phase 7 — Menu bar  (1 commit)
- [ ] Restyle popover: tokens-today hero · plan value+tier · tightest quota+dot+who · top-3 agents · Open/Quit. Readout picker (tokens/quota/all-time/icon).

## Phase 8 — States · reflow · motion  (1 commit)
- [ ] Empty/loading/error restyled. narrow reflow <720 (agentGrid auto-fit · splitGrid 1fr · valueGrid · hide reset/conf) + 640×480 min. All tk-* w/ reduced-motion static path.

## Phase 9 — Verify (gate before "done")
- [ ] `xcodegen generate` → Core tests 302 green → App build.
- [ ] Launch worktree build (DerivedData `-dfmeddobpfrxvxeqtepfotxljyha`), screenshot every state + 640×480 reflow. (No macOS computer-use tool this session → screencapture/osascript fallback or hand to user.)
- [ ] Restore any test UserDefaults; relaunch user's dev build. Append WP-5 note to `tasks/patch-bibles/2026-07-19.md` §8.

## Execution notes
- Small reviewable commits (pre-commit hook: no-secret / no-large-artifact / format).
- Offload heavy per-surface builds to focused subagents (context hygiene — last session died of context). Foundation (P0–1) lands first, shared; surfaces can then parallelize.
- Checkpoint for visual review after Overview renders (Phase 3) before continuing.
