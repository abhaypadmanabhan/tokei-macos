cd /Users/abhayp/Downloads/Projects/tokei-worktrees/2026-07-19-ui-ia-consolidation
Work ONLY in this directory. Never touch the main repo or another worktree.

Resume Tokei WP-5: finish matching the dashboard UI to the "Tokei Dashboard" mockup and wire every surface to real data so the whole app works.

FIRST read the checkpoint — full state, the design system, the data-wiring map, and per-surface specs:
  tasks/handoff/WP5-visual-redesign.md

The decoded mockup is durable alongside it (read for exact values — no need to re-extract the bundle):
  tasks/handoff/new-design-outline.txt    (DOM + inline styles, per surface)
  tasks/handoff/new-design-logic.js        (data model, renderChart/Donut/Heatmap/Gauge/History, pace/quota helpers)
  tasks/handoff/new-design-template.html   (full decoded DOM)
  original bundle: ~/Downloads/Tokei Dashboard.html

State: branch patch/2026-07-19/ui-ia-consolidation @ df8f63f — clean, build-green, not merged.
DONE (committed): P0 tokens · P1 tinted logos · P2 tabs+drawers · P3 Overview · heatmap fix.
REMAINING: P4 Value · P5 Agents tab · P6 Drill-in · P7 Menu bar · P8 states/reflow/cleanup. Exact per-surface specs + real VM/store bindings are in the checkpoint's REMAINING + data-wiring sections.

Scope lock: AIUsageDashboardApp/UI/ + Assets.xcassets/ProviderMarks/ + MenuBar/ only. Never Core/, App/, project.yml, or MenuBar/MaxxerMath.swift (compiled into the 302 Core tests — keep its API stable).

Hold directives: no 01/ 02/ numbered kickers; confidence stays subtle (dotted underline + tooltip, no chips); heatmap + donut stay on Overview; mono for numbers/paths only, sans for names/body/buttons; per-agent tints are DATA colour, accent stays state-only; every animation reduce-motion-safe; keep honest empty/loading/error + "—" not "0" + 640×480 reflow.

Reuse the design system already in PadzyTheme / AgentTint / PaceVerdict / ProviderBrandMark.tinted / PadzyToggle — don't re-derive tokens. Wire to the REAL ViewModel/stores (the mockup's providers array is illustrative only); preserve existing bindings when rebuilding each surface.

Approach: run padzy-os (aitracker) + frontend-design + staff-engineer-workflow. Delegate each surface rebuild to a focused subagent (spec + tokens + data map + "preserve bindings, build-to-green, do NOT commit"); review its diff, rebuild, commit small. Then cleanup sweep (delete dead ProviderChipStrip.swift + QuotaWindowRow.swift + orphans) + /simplify + append a WP-5 note to tasks/patch-bibles/2026-07-19.md §8.

Build/verify:
  cd AIUsageDashboard && xcodegen generate
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test    # 302 pass
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp  -destination 'platform=macOS' build
Then launch this worktree's build (DerivedData -dfmeddobpfrxvxeqtepfotxljyha / Tokei.app).

VERIFICATION GAP: this environment can't screenshot (no macOS Screen Recording / Accessibility permission → screencapture is black, System Events can't drive the window). Do the build-green gate yourself; hand VISUAL verify to me (I launch Tokei.app / paste screenshots). If you want automation, tell me to grant the terminal those two permissions in System Settings → Privacy.

Out of scope under WP-5 (need Core/feature work — leave as follow-ups): range set Today/Week/Month/All, functional accent-override, a real mark_gemini asset.

I'll paste the design bundle next.
