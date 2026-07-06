# Padzy OS theme — "aitracker" (PROPOSED, pending Abhay confirmation)

Product: AI Usage Dashboard (native macOS, menu bar + dashboard).
Category: telemetry / dev-tool. Primary tiers: Functional (dashboard), Dense (menu bar, data rows).

Derivation rationale (per padzy-os/references/themes.md):
- Ground temp: **cool dark** — dev telemetry surface; distinct from Voxi's warm-dark `#171716`.
- Accent: **signal pink `#FF3B70`** — saturated, confident, no AI-slop cyan/blue; distinct from
  home/voxi lime `#C8E62C/#C9E530`, autocoach emerald `#109462`, volini orange `#FF4D00`.

```json
{
  "name": "aitracker", "label": "AI Usage Dashboard - macOS AI usage telemetry",
  "category": "telemetry", "ground_temp": "cool dark",
  "colors": { "ground":"#131316", "surface":"#1D1D22", "ink":"#ECECF1", "muted":"#6E6E78", "accent":"#FF3B70" },
  "accent_role": "active/selected states, sync-in-progress, progress fills, single primary action",
  "primary_tier": "Functional (dashboard); Dense (menu bar panel, data rows)",
  "display_face": "PP Neue Machina (fallback: SF Pro Display heavy weights if font not installed)",
  "mono_face": "DM Mono (fallback: SF Mono) — ALL numbers/timestamps/IDs/metrics"
}
```

Invariants (non-negotiable in every view):
1. Mono font for all data/numbers.
2. Numbered editorial kickers, e.g. `01 / PROVIDERS`.
3. Exposed hairline structure (1px dividers, labeled regions) — no card stacks, no shadows, no glass/materials.
4. Active/selected/syncing state = square 2px accent bar on leading/bottom edge.
5. Exactly one accent per view.

Contrast floor: body/UI text ≥ 4.5:1 on ground/surface; large text + non-text UI ≥ 3:1. Verify ink/muted/accent in dark mode (app ships dark-themed both modes for MVP).

On confirmation, lock into `~/.claude/skills/padzy-os/themes/aitracker.json`.
