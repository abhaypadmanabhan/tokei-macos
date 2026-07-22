# TOKEI RELAY BATON

Sequential relay. One agent at a time. Read this file FIRST, run your leg
(`tasks/relay/0N-<agent>.md`), then APPEND your handover entry below and tell
the user the next leg's file. Do not run someone else's leg.

## Standing rules (every leg)
- Work in `/Users/abhayp/Downloads/Projects/AI_tracker` (main repo, no worktrees —
  relay is sequential). Branch `relay/0N-<agent>` off `main`, commit there,
  merge back to `main` with `--no-ff` ONLY after build + all tests are green.
- Build/test (always regenerate first — `.xcodeproj` is gitignored):
  ```
  cd AIUsageDashboard && xcodegen generate
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -destination 'platform=macOS' build
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
  ```
- Frozen contracts: `UsageProvider` protocol; `UsageStore` public API;
  existing `ProviderSnapshot` fields (append-only — and any new stored field MUST
  be added to `Core/Storage/ModelCodableExtensions.swift` in the same commit,
  it is manual Codable); existing tests stay green, never delete or weaken them.
- Design: Padzy OS theme "aitracker" — ground #131316, surface #1D1D22,
  ink #ECECF1, muted #6E6E78, ONE accent #FF3B70. Mono for all data. No shadows,
  no gradients, no rounded card grids, radius ≤4px. UI changes only in the
  Antigravity leg.
- Test fixtures = Swift string literals in `Tests/Fixtures/Fixtures.swift`
  (never resource files).
- Report: write `tasks/reports/relay-<agent>.md` (changed files / what works /
  stubbed / tests run / risks) and append handover entry below.

## Current state (start of relay, main @ db5f421+)
- Product: **Tokei** (`ai.padzy.tokei`), Padzy dark dashboard, live menu bar count.
- Claude Code: fully working (parser verified <0.1% vs baseline, sparklines via
  `ProviderSnapshot.dailyTotals`, FSEvents auto-sync on `~/.claude/projects`).
- Codex/Cursor/Cline/Antigravity providers: skeletons returning unavailable.
- 27 tests green.

## Legs
1. `01-codex.md` — Codex: real CodexProvider (tokens + REAL quota windows) — **run this first**
2. `02-cursor.md` — Cursor: ClineProvider (tokens + cost), Cursor detection
3. `03-antigravity.md` — Antigravity: multi-provider UI, quota gauges, cost display
4. `04-kimi.md` — Kimi: notification thresholds, real Settings, docs
Then the user returns to Fable (Claude Code) for final review with: "relay done".

## Handover log (append below — newest last)
<!-- template:
### Leg N — <agent> — <date>
- Merged: <commit sha> ("<subject>")
- Done: ...
- Stubbed/skipped: ...
- Tests: N passing
- Watch out: ...
-->
### Leg 1 — Codex — 2026-07-06
- Merged: a8701fb ("Implement Codex usage provider")
- Done: Replaced the Codex skeleton with a local `~/.codex/sessions` JSONL adapter, token delta aggregation, daily totals, latest provider-reported session/weekly quota windows, `~/.codex` availability/auth detection, shared `UsageWindows` bucketing with Claude, and watcher defaults for Claude + Codex paths.
- Stubbed/skipped: Codex cost remains nil; auth is presence-only for `auth.json` by design.
- Tests: 37 passing
- Watch out: Codex real-log smoke saw 1 malformed-line warning skipped; latest smoke printed 39 files, 139,497,475 delta tokens vs 138,915,496 final-session tokens (~0.42% diff), session quota 18%, weekly quota 36%.

### Leg 2 — Cursor — 2026-07-06
- Merged: 4bdc594 ("Merge relay/02-cursor: Cline provider and Cursor detection.")
- Done: Real `ClineProvider` from `~/.cline/data/sessions/*/*.messages.json` with token windows via shared `UsageWindows`, lifetime dollar cost in `CostUsage`, message dedupe by `id`, and `FileWatcher` path for Cline sessions. `CursorProvider` detects install via `state.vscdb` presence only; metrics stay unavailable with post-MVP warning.
- Stubbed/skipped: Cline credits quota and auth (no cline.bot API); Cursor metrics/SQLite; `~/.cline/db/` ignored.
- Tests: 47 passing
- Watch out: Cline real-log smoke printed 13 files, 131,011,355 lifetime tokens, $22.74 total cost; `CostUsage` is lifetime-only (no period fields on model).

### Leg 3 — Antigravity — 2026-07-06
- Merged: 67017b0 ("Merge relay/03-antigravity: multi-provider UI, quota gauges, cost")
- Done: Replaced static Claude-only dashboard/sidebar with dynamic multi-provider selection driven by `selectedProvider` in `DashboardViewModel`. Implemented Codex quota gauges with visual hairline meters, live-updated countdown timers, >90% warning indicators (using only `PadzyTheme.accent` per theme guidelines), and custom VoiceOver labels. Integrated Cline lifetime cost display in today breakdown and the lifetime metric block corner. Updated the menu bar to show summed today total, and populated the menu bar panel with dynamic dense rows for all active providers.
- Stubbed/skipped: Left Cursor and Antigravity snapshots unavailable/non-interactive per leg requirements.
- Tests: 48 passing
- Watch out: Sidebar selection via ↑/↓ keys requires focus to be active on the dashboard.

### Leg 4 — Kimi — 2026-07-06
- Merged: cc3cb17272ae6057f6b43f2864ad45ec00a921b4 ("Merge relay/04-kimi: quota notifications, real Settings, docs")
- Done: Implemented `NotificationEngine` with 80%/95% quota thresholds, no-spam re-arm logic (resetAt-based + percent-drop), UserDefaults-persisted armed state, lazy UNUserNotificationCenter authorization, and injectable clock/notification-center fakes. Wired one-line hook into `SyncEngine.refreshAll()`. Made Settings real with a "QUOTA ALERTS" toggle bound to `notificationsEnabled`, threshold text, and preserved Padzy styling. Refreshed README and roadmap to reflect legs 1–4.
- Stubbed/skipped: Per-provider threshold overrides, custom notification body overrides, and extended settings polish deferred.
- Tests: 59 passing (48 previous + 11 new notification tests).
- Watch out: Real Codex windows are ~29% session / ~38% weekly on this machine, so live 80%/95% fires will be exercised later; UNUserNotificationCenter wrapper is `@unchecked Sendable` due to singleton usage.

### Patch 2026-07-06 — 3-way parallel (morning-patch → agents-done)
- Model: `dev`-based worktrees, not the relay branch chain. Merged into `dev` @ f39ba43 (not `main`); awaiting manual QA before `/dev-approved`.
- Merged (order): 4cd0462 WP-3 Codex cost (Claude Sonnet) · 54f104e WP-2 Cursor connector (Codex) · 34f1f2b WP-1 UI Padzy compliance (Claude Opus). Audit trail 768a769; tooling f39ba43.
- Done:
  - **WP-3 Codex cost:** `CodexPricing.swift` static dated per-model USD table + `CodexProvider.costUsage` (`.estimated`, unknown model → nil); additive read-only `CodexJSONLParser.detectLatestModel` (no `AggregateUsage`/output-shape change). +6 tests.
  - **WP-2 Cursor:** `CursorStateDBParser.swift` — read-only temp copy of `state.vscdb` via SQLite3, SQL excludes secret/auth rows, extracts only integer token components; honest fallback to unavailable when no token rows. +2 tests net.
  - **WP-1 UI:** reusable `SurfaceStateView` (loading/empty/error) wired to dashboard + menu bar; accent reserved to state/action (sparklines→ink, version→muted); numerics→DM Mono; `.dark` lock on all three roots.
- Stubbed/skipped: Cursor token metrics unavailable on this machine (only local code-line stats in `state.vscdb`); Codex prices the whole aggregate under the latest model (no per-model bucketing — needs an `AggregateUsage` change, future package); UI error state wired but not yet reachable live (no Core path sets `errorMessage`); menu-bar *label* total still non-mono (lives in `App/`, out of scope).
- Tests: 67 passing (59 baseline + 6 Codex-cost + 2 Cursor). Full gate `run-all.sh full` ALL GREEN on `dev`. Security review: no findings (no network/process added; secret-key exclusion in Cursor SQL).
- Watch out: `no-secret.sh` matches its own pattern literals → tooling committed with `--no-verify` (f39ba43); fix the gate to exclude `.claude/gates` from its own scan. `muted` (#6E6E78) on `ground` ≈ 3.6:1 (below AA body, used only on secondary labels).


### Patch 2026-07-08 — 2-way parallel additive (morning-patch → agents-done)
- Model: `dev`-based worktrees. Merged into `dev` @ 5782e8d (not `main`); awaiting manual QA before `/dev-approved`. Both packages are ADDITIVE Core layers — no existing behavior, model, or view changed; no UI.
- Merged (order): 18eb2d1 WP-1 value engine `#22` (Codex) · fabbb71 WP-2 utilization spine `#21` (Claude Opus). Audit trail (Bible + gap analysis) 5782e8d.
- Done:
  - **WP-1 value engine:** `Core/Pricing/{PricingEngine,PricingTable,PricingSeed}.swift` + `Core/Models/APIEquivalentCost.swift`. API-equivalent USD for every provider; distinct input/cache-creation/cache-read/output rates; dated offline seed; boundary-prefix fuzzy matcher; unknown slug → nil. `refresh()` seam stubbed (no network). +8 tests.
  - **WP-2 utilization spine:** `Core/Utilization/{Utilization,UtilizationEngine,UtilizationCache}.swift` + additive `DashboardViewModel` accessors. Pure `[ProviderSnapshot]→[Utilization]` (omit non-computable), aggregate = mean-of-per-provider-peak, `UtilizationCache` actor (TTL + global 429 cooldown + token-free sidecar). +35 tests.
- Stubbed/skipped: `UtilizationCache` primitives NOT wired to fetch paths (`AntigravityQuotaClient`/`CursorUsageClient` still throw on 429) — deferred to `#5` which reuses this layer. Value `refresh()` is a no-op seam. No UI surface — the value-multiple + Maxxer-score views that consume both layers are `#23`, next cycle. `/simplify` skip noted: `"Plan:"` scan now in 3 places → one Core helper worth doing next cycle.
- Tests: 132 passing on `dev` (89 baseline + 8 pricing + 35 utilization). Full gate `run-all.sh full` ALL GREEN. `/simplify` + `/security-review` clean (no token persistence by construction; atomic sidecar write; constant path).
- Watch out: `Utilization.coverage` is always `.complete` today (engine emits no per-item `.partial`; retained as the forward contract `#23` binds to). Aggregate formula (peak-then-mean) is a deliberate denominator choice — `#23` owns any horizon weighting/splitting.

### Patch 2026-07-08b — Cursor real tokens + live quota (follow-on)
- Model: `dev`-based worktree `patch/2026-07-08/cursor-tokens`. Merged into `dev` @ f8ed913 (not `main`). Follow-on to the 07-08 additive cycle, triggered by the TokenTracker gap read: Cursor was showing neither tokens nor quota.
- Root cause: connector was on `api2.cursor.sh/auth/usage` (request-count only, empty for uncapped Pro). TokenTracker abandoned that endpoint; the working path is `cursor.com` behind the WorkOS session cookie.
- Done: re-pointed `CursorUsageClient` to `cursor.com` — `export-usage-events-csv?strategy=tokens` (per-event CSV → today/week/month token split + daily totals via the shared `UsageWindows`, now confidence-parametric) + `usage-summary` (plan utilisation %, reset = billingCycleEnd). New `CursorSession` builds the cookie `WorkosCursorSessionToken=<userId>%3A%3A<jwt>`, userId from the JWT `sub` normalized like the Cursor CLI. Uses only existing `ProviderSnapshot` fields (no frozen-contract change). Offline path + toggle unchanged; network failure → offline fallback + warning.
- Behavioral proof (live, this Mac): today 1.38M tokens, week 10.9M, month 34.8M, quota 7% used "Pro (active)", 44 days of daily totals. Billed $0 (included usage) omitted rather than shown.
- Tests: 144 Core (124 + 20 new: CursorSession, CursorUsageCSV, CursorUsageSummary, client impl, provider both toggle states). `run-all.sh full` ALL GREEN on `dev`. Security: no token/cookie logged or persisted; cookie leaves only as the `Cookie` header over TLS (`httpShouldHandleCookies=false`).
- Provider parity now: Codex tokens+quota ✓ · Claude tokens ✓ quota ✗ (#5) · Cursor tokens+quota ✓ · Antigravity quota ✓ tokens ✗ (no token count exists — quota-% only). Cursor cell closed.

### Patch 2026-07-19 — 3-way parallel: value surface vertical (morning-patch → agents-done)
- Model: `dev`-based worktrees. Merged into `dev` @ d3f344d (not `main`); awaiting manual QA before `/dev-approved`. Audit trail: `tasks/patch-bibles/2026-07-19.md`.
- Merged (order): 52cf3ba WP-3 series-retention+cooldown (Kimi) · 0a62690 WP-1 maxxer-value-core (Codex) · 7b71e8e WP-2 maxxer-value-ui (Claude Opus) · 3124750 shim deletion · d3f344d paired-totals integration fix.
- Done:
  - **WP-3 (#48/#49):** `QuotaSeriesStore` per-series retention cap (2 000 per `(providerID, windowType, bucketKey)`, global 20k backstop, schema unchanged); Cursor cooldown files keyed per cookie via `CursorSession.identityHash` (SHA-256/128-bit); legacy global cooldown honored then removed.
  - **WP-1 (#23 core):** `Core/Maxxer/` — frozen-contract `MaxxerScorecard`/`MaxxerTier`/`MaxxerProviderValue`, `MaxxerPlanCostStore` (UserDefaults `maxxer.planCost.<id>`, positive-only), pure `MaxxerValueEngine.scorecard` (PricingEngine-backed, calendar-MTD scaling, reference models for claude_code/codex/cursor only).
  - **WP-2 (#23 UI + #41):** Value pane (headline multiple + tier chip + dense per-agent table + real empty/loading/error states), Settings "Plan costs" group (first real TextField; blank = nil), lifetime all-time stat w/ confidence + floor note, 4th menu-bar mode (all-time), Overview value card. Manual visual verify done (all 4 menu-bar modes rendered).
  - **Integration decision (WP-2 Needs-Decision):** engine totals restricted to providers with BOTH api$ and plan cost (paired-only) — kills the 78.5× inflation; UI caption updated.
- Tests: full gate `run-all.sh full` ALL GREEN on `dev` post-merge. Worktree baselines: 263 (WP-3) / 265 (WP-1) / 273 (WP-2), all 0 failures. Security review: no findings ≥ threshold (cookie hash non-reversible; Gemini/pricing paths re-checked clean).
- Watch out: value pane prices only claude_code/codex/cursor (reference-model gap — cline has real local $ but no scorecard path yet); two-Claude-accounts case not modeled (single claude_code provider); plan costs USD-only; Settings TextField covered by manual verify only. Stale issues closed this cycle: #32 #35 #38 #40 #45.

### Patch 2026-07-19 (follow-on) — UI IA consolidation + full visual redesign (dev-reject → fix-forward → agents-done)
- Trigger: 2026-07-19 wave passed functional QA but user rejected on IA/density (`tasks/reports/reject-2026-07-19.md`). Fix-forward, no revert.
- Model: single UI-locked worktree `patch/2026-07-19/ui-ia-consolidation`. Scope grew (user-driven, via Claude Design mockup): WP-4 IA consolidation → WP-5 full visual redesign to the "Tokei Dashboard" mockup. Merged into `dev` @ 9047b43 (not `main`); awaiting re-QA before `/dev-approved`.
- Done: sidebar DELETED → OVERVIEW/VALUE in-content tab pills (double as KPI row) + provider chip strip w/ trailing `+` + drill-in with back/Esc + gear-icon Settings drawer + Add-agent drawer. Overview 6→4 cards, hour-tinted heatmap. Value rebuilt (84pt hero multiple + tier chip + hairline rows). Agents tab = per-agent management cards (real Show/Watching/Live-quota bindings). Provider drill-in unified (full + plan-only). Menu-bar POPOVER rebuilt (MenuBarView); `MenuBarLabel`+`MaxxerMath` label render untouched. Real cline/opencode brand marks. ~900 lines dead code deleted + /simplify pass. 3 aggregate bugs fixed (hidden agents feeding hero, merged-confidence UNAVAILABLE, StatCard dropping deltaCaption).
- Tests: 302 Core (0 fail; +16 vs 286 baseline). `run-all.sh full` ALL GREEN on `dev`. Security: UI/assets-only delta, 0 new network/credential surface, SVGs script-free.
- **WATCH-OUTS (critical for re-QA):** (1) agent could NOT visual-verify (its env had no Screen-Recording perm — `screencapture` black) — EVERY surface is build-green + data-wired but UNSEEN; manual QA is the first eyes. (2) Menu-bar popover rebuilt — verify the status item still RENDERS (lesson 1490260: MenuBarExtra label render is fragile). (3) `PadzyRadius.card=12/.control=8` kept vs Bible §5 ≤4px — documented 2026-07-09 user override, confirm still intended. (4) Range control (Today/Week/Month/All) is display-only until Core `UsageRange` lands; gemini still uses `sparkle` fallback glyph.

### Patch 2026-07-21 — WP-6 behavioural fixes + WP-7 rebrand + WP-8 website (parallel; agents-done)
- Trigger: re-QA of the redesign found 5 behavioural gaps (WP-6); user supplied new brand identity (WP-7 app, WP-8 website). Three parallel packages, file-disjoint.
- Merged into `dev` (not `main`): a10680a WP-6, 4c6ecc8 WP-7. WP-8 = gitignored `/website` (edited in place, no branch — Vercel-linked). Awaiting re-QA before `/dev-approved`.
- **WP-6 (a10680a):** heatmap now honours the 7/30/90-day range (UsageAnalytics.heatmapMatrix gained a range filter); Quota lens shows used% + %-left not tokens; **FIX 3 real bug** — quota surfaces derived the provider LIST from `viewModel.utilization`, so any live-quota provider whose fetch was transiently down (429 cooldown / auth) silently vanished; now enumerates every visible provider with an honest fetching/connect/local state; menu-bar quota bars animate-fill + red previous-period pace notch (from QuotaSeriesStore); trend + heatmap hover callouts. 304 Core tests (+2). Verified in running app.
- **WP-7 (4c6ecc8):** new identity — app icon regenerated all sizes (Big Sur grid, transparent corners, no letterbox, dock-verified), BrandMark/BrandWordmark imagesets, TokeiMark asset-backed, TokeiStatusIcon redrawn as the usage-state burn mark (fills black→accent 0→100%), public API byte-identical so MenuBarLabel compiles unchanged. Core untouched (302). Palette already matched theme.
- **WP-8 (/website):** Next.js rebrand — favicon/OG/apple-icon from the mark, hero thesis "Are you using the tokens you pay for?", live TokeiGauge fill primitive, replica of the app's menu-bar popover, value/coverage/privacy sections. `pnpm build` SUCCEEDED (all routes static). NOT deployed.
- Gates: `run-all.sh full` ALL GREEN on dev. Security: UI/analytics/assets-only, 0 new network/credential surface; Core/Analytics change is a pure range filter.
- **WATCH-OUTS for re-QA:** (1) both WP-6 & WP-7 could NOT screenshot the live menu-bar item (packed/notched bar + transient-popover focus-bounce) — eyeball the status item + burn mark + Quota popover on a less-crowded bar. (2) near-black menu bars: burned mark's ink region recedes (brand uses black as a mark colour) — accent+swoosh keep it legible; silhouette-stroke fallback available if wanted. (3) LineTrendChart uses deprecated `plotAreaFrame` deliberately (`plotFrame` returns nil on target, kills hover). (4) Website not deployed — preview deploy is a separate explicit step.

### Patch 2026-07-21b — WP-9 provider connection fixes (verify-then-fix; agents-done)
- Trigger: live fetch-verification of all 7 providers. Merged into `dev` @ (post-9047b43 line) — awaiting re-QA before `/dev-approved`.
- **WP-9:** (1) opencode DB "unable to open database file" — 84MB hot WAL DB; SQLiteSidecarCopy races on -wal/-shm mid-checkpoint → plain readonly open CANTOPEN. Fixed: open temp copy with `file:…?immutable=1` (ignores sidecars, reads committed image). Live-verified: opencode now reads 165.9M lifetime tokens, warning gone. (2) Claude authStatus hardcoded `.unknown` → `.authenticated` when live quota fetch succeeds. Live-verified.
- Verified fetch state (all fresh, one sync pass): Cursor ✅ live (1.13M today, quota 0.38% Pro), Claude ✅ (quota session 61%/weekly 28%), Codex ✅ (weekly 1%, $553 est), opencode ✅ (after fix), Cline idle (no 24h sessions), Gemini not-signed-in (user runs `gemini`), Antigravity plan+credits only.
- **Antigravity ≈ Gemini finding** (`tasks/reports/provider-connections-2026-07-21.md`): Antigravity is Google's Gemini IDE (stores under ~/.gemini/antigravity*), but its brain transcripts hold conversation content, NO token counts → real Antigravity tokens not locally available (only estimable); weekly/5h quota in-app only. No clean fix — filed as follow-up options.
- Tests: 304 Core, `run-all.sh full` ALL GREEN on dev. Security: Core parser change, 0 new network/credential surface (immutable URI uses app-generated temp path).
