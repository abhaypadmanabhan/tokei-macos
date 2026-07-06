# RELAY LEG 3 — Antigravity: multi-provider UI, quota gauges, cost

Read `tasks/relay/BATON.md` first — standing rules, PADZY THEME RULES (strict),
build commands. Read Leg 1 + 2 handover entries. Branch: `relay/03-antigravity`.

## Mission
Tokei now has three live providers (Claude Code tokens, Codex tokens + REAL
quota windows, Cline tokens + REAL cost). Make the UI multi-provider: sidebar
selection drives the usage pane; show Codex quota gauges and Cline cost —
all inside the existing Padzy language (mockup in git history, current
DashboardView is the reference implementation).

## Files you own
- `AIUsageDashboard/AIUsageDashboardApp/UI/*`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Sync/DashboardViewModel.swift`
Nothing else. NO provider/parser/model/storage edits. If a provider gives you
awkward data, note it in the report — do not fix it yourself.

## Spec
1. **Selection**: `@Published var selectedProvider: ProviderID = .claudeCode`
   on the view model. Sidebar rows clickable when the provider's snapshot has
   any usable data (todayUsage.totalTokens != nil OR non-empty quotaWindows OR
   costUsage != nil); accent tick + surface background follow selection; rows
   keep hover affordance, add `.accessibilityAddTraits(.isButton)`. Rows with
   no data stay muted UNAVAILABLE, not clickable. Show compact today total
   under each available provider's name (mono, muted).
2. **Usage pane generalizes**: hero TODAY numeral + breakdown + metric blocks
   (7D/30D/LIFETIME + sparklines from `snapshot.dailyTotals`) render for the
   SELECTED provider. Claude behavior/layout must not regress.
3. **Quota gauges** (renders only if `!snapshot.quotaWindows.isEmpty` and
   confidence != .unavailable — i.e. Codex): a numbered region `0N / LIMITS`
   above the metric blocks. Per window: label (`SESSION · RESETS 14:32` style,
   countdown from `resetAt`, mono), horizontal meter — 1px hairline track,
   flat accent fill proportional to used_percent, right-aligned mono
   `29% / 100`. Padzy: sharp corners, flat fill, accent is the ONLY color;
   at >90% used do NOT introduce red — use full accent + a `!!` mono marker.
   Show the window's ConfidenceBadge (providerReported vs estimated matters).
   Claude's unavailable-quota windows must NOT render as gauges.
4. **Cost** (Cline): in the breakdown row and/or a metric block corner, show
   real dollars mono (e.g. `$4.83`), clearly labeled `COST`. Only when
   `costUsage != nil`.
5. **Menu bar**: label stays Claude-focused total is now wrong — make it the
   SUM of today totals across providers (nil-safe). Panel: one Dense row per
   provider with data (name, today, and for Codex the session % as
   `S 29%`), plus existing sync line/buttons.
6. **Empty/edge states**: selected provider with data but empty dailyTotals →
   flat hairline sparkline (already handled by Sparkline). Keep the no-~/.claude
   empty state for Claude only; other providers show their warnings inline.
7. Keyboard: ↑/↓ moves provider selection (`.focusable()` + `onMoveCommand`
   or equivalent); ⌘R refresh unchanged. VoiceOver labels on gauges
   ("Codex session window 29 percent used, resets in 3 hours").

## Definition of done
Build green; ALL tests green (do not touch tests, but they must still pass);
manual check: selecting each live provider swaps the pane correctly, Codex
gauges show real percentages, Cline shows dollars, Claude unchanged; Padzy
checklist holds (one accent, mono data, hairlines, no shadows/gradients);
merged to main --no-ff; report `tasks/reports/relay-antigravity.md` + BATON
entry. Include a screenshot in the report if you can.

## Handover
End with exactly:
"Leg 3 complete. Next: run Kimi with tasks/relay/04-kimi.md".
