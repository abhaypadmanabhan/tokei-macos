# Tokei — Quota Dashboard & Token Maxxing: Issue Set

Derived from `tasks/specs/2026-07-08-quota-dashboard-spec.md`. Decisions Q1–Q10 baked in.
Ordered top→bottom = tackle order. Each issue tagged **NEW** / **REFINES #n** / **SUPERSEDES #n**
against existing repo issues so you update-vs-create deliberately (no dupes).

Labels that exist: `P0-critical` `P1-high` `P2-medium` `provider-claude` `provider-cursor`
`provider-antigravity` `infra` `security` `token-maxxer` `gamification` `growth` `design` `ship`.
**No P3/P4 label exists** — P3/P4 issues below use `token-maxxer`/`growth` + note "create P3/P4 label if wanted".

---

## PHASE P0 — quota + usage parity

### P0.1 — Capture & pin the Claude `oauth/usage` response body  ·  **NEW**
- **Labels:** `P0-critical` `provider-claude`
- **Context:** The `GET api.anthropic.com/api/oauth/usage` endpoint returned HTTP 200 on this Mac, but the probe captured status only — field names for the decoder are unconfirmed. Every downstream Claude-quota issue depends on a pinned real payload.
- **Scope:** One-time dev spike. With a valid Keychain token, make a single authenticated GET, save the raw JSON body to `tasks/research/claude-usage-response.json` (redact any account identifiers), and document the exact field paths for `five_hour` / `seven_day` / `seven_day_opus` / `extra_usage` / `limits[]` (the `weekly_scoped` entries) — noting `utilization` vs `resets_at` key names as actually returned.
- **Acceptance check:** `tasks/research/claude-usage-response.json` exists with a real (redacted) body, and a short field-map table is committed alongside it.
- **Guardrails:** Do NOT print or commit the token. Do NOT commit un-redacted emails/org ids/account ids. Exactly ONE live call — no polling loops. This endpoint shares Claude Code's rate budget; a burst here can 429 your real CLI.
- **Depends on:** none (do first).

### P0.2 — Add `ClaudeUsageClient` (fetch + decode + resilience)  ·  **NEW** (feeds SUPERSEDES #5)
- **Labels:** `P0-critical` `provider-claude` `security`
- **Context:** Turns the pinned payload into a typed client, siblinged to `CursorUsageClient` / `AntigravityQuotaClient`. This is the core unblock for Claude quota parity (the app's biggest hole).
- **Scope:** New `Core/Network/ClaudeUsageClient.swift`: read Keychain `"Claude Code-credentials"` (fallback `~/.claude/.credentials.json`), check `expiresAt`, call the endpoint with `Authorization: Bearer` + `anthropic-beta: oauth-2025-04-20`, decode into `[QuotaWindow]` (percent convention: `used`=utilization, `limit`=100, `remaining`=100−used, `resetAt`=resets_at). Include self-contained resilience: in-request retry ≤3 honoring `retry-after` (cap 30s), a persisted cooldown file (default 5min, cap 60min — skip the call entirely while cooling), and a stale-serve cache (fresh 10min, serve stale ≤7d flagged `stale`, invalidate a window when it crosses its own `resets_at`). Unit-test the decoder against the P0.1 fixture.
- **Acceptance check:** A unit test decodes the committed fixture into `.session` + `.weekly` (+ scoped) `QuotaWindow`s with correct percentages and reset dates; a simulated 429 produces a cooldown + stale-cache read, never a throw to the UI.
- **Guardrails:** Do NOT implement OAuth token refresh (Claude Code refreshes the Keychain; on 401 surface "run `claude` once"). Do NOT log/persist the token anywhere. Do NOT let any network error propagate as a crash or red-error — always degrade.
- **Depends on:** P0.1.

### P0.3 — Wire Claude quota into `ClaudeCodeProvider` behind opt-in toggle  ·  **SUPERSEDES #5**
- **Labels:** `P0-critical` `provider-claude`
- **Context:** Swaps the hardcoded `.unavailable` stubs in `ClaudeCodeProvider.fetchSnapshot()` for live `ClaudeUsageClient` output. Existing gauge UI lights up with zero view changes (Codex-proven path).
- **Scope:** Add a `claudeNetworkUsageEnabled` toggle (UserDefaults, **OFF by default**, Settings row labeled "reads your own Claude account, may break without notice"). When ON and the client returns windows: publish them, add `.quota` to capabilities, set `authStatus` from token presence/expiry. Map `weekly_scoped[]` → `.perModel` windows **generically** using each entry's own `display_name` label + `bucketKey`. Add a shared-pool disclosure label on the tile: "includes claude.ai + Cowork usage". Hide the extra-usage window until its utilization is non-zero.
- **Acceptance check:** With the toggle OFF, Claude shows exactly today's `.unavailable` behavior. With it ON and the client mocked to return sample windows, the Claude tile renders session + weekly + any scoped gauges; with the client mocked to throw, the tile falls back to the `.unavailable` stub and the app stays green.
- **Guardrails:** MUST fail-safe to the existing `.unavailable` stub on ANY client error — a dead endpoint can never break the app. Do NOT hardcode "Opus"/"Sonnet" — render whatever `weekly_scoped` labels arrive. Do NOT enable the toggle by default.
- **Depends on:** P0.2.

### P0.4 — Quota snapshot sampler + append-only series persistence  ·  **NEW** (v2-sync foundation)
- **Labels:** `P0-critical` `infra`
- **Context:** The heatmap daily-fill math (§4) and the Maxxing score (§3) both need a time series of quota %; a single live reading isn't enough. This series is also the exact shape a v2 Supabase sync will push — build it flat now.
- **Scope:** A background sampler that, while the app runs, polls each ENABLED live-quota provider every **15 min** (reusing the P0.2 cooldown discipline) and appends rows `(provider, windowId, timestamp, usedPercent, confidence, source)` to the JSON store. Flat, append-only, no mutation. Add the new stored property/collection to `ModelCodableExtensions.swift` manual Codable. Include reset-crossing detection (used% drop ≥5pp AND `resets_at` advance ≥60s) so cycles delimit correctly.
- **Acceptance check:** After running with ≥1 live provider enabled, the store contains time-ordered sample rows for that provider's windows; a round-trip encode/decode of the store preserves them; the series survives an app relaunch.
- **Guardrails:** Do NOT skip the `ModelCodableExtensions` update — any new stored property omitted there silently breaks persistence (project rule). Do NOT poll disabled providers. Do NOT poll faster than 15 min or bypass the cooldown (429 risk on shared-budget endpoints). Do NOT make live paid calls — these are the user's own subscription quota reads only.
- **Depends on:** P0.3 (needs at least one live-quota provider; Cursor/Antigravity already qualify, so this can start once any is sampling-ready).

### P0.5 — Classify Codex windows by duration, surface credits + reset-bank  ·  **NEW**
- **Labels:** `P0-critical` `token-maxxer`
- **Context:** Codex quota already comes from local `~/.codex/sessions/*.jsonl` (shipped), but windows are read by slot position. Free/lower tiers put the weekly window in the `primary` slot, so positional reading mislabels weekly as 5h.
- **Scope:** In the Codex parser, classify each window by `limit_window_seconds` (18000s → `.session`/5h, 604800s → `.weekly`) instead of primary/secondary position. If present in local JSONL, also surface the credit window (`spend_control.individual_limit`) and reset-bank counts as additional windows. P0 stays **local-JSONL only** — no remote `wham/usage` call.
- **Acceptance check:** A parser test feeds a fixture whose weekly window sits in the primary slot and asserts it is labeled `.weekly`, not `.session`.
- **Guardrails:** Do NOT add the `chatgpt.com/wham/usage` remote path here (deferred to P2). Do NOT own an OpenAI token refresh in this issue.
- **Depends on:** none (independent of Claude work).

### P0.6 — Antigravity: stale-serve quota cache when the app isn't running  ·  **NEW** (REFINES #4)
- **Labels:** `P0-critical` `provider-antigravity`
- **Context:** Antigravity quota comes from the local language_server RPC, which only answers while the Antigravity app is running. Today the gauge disappears when it's closed; a stale cache keeps the last-known windows visible.
- **Scope:** Persist the last successful `RetrieveUserQuotaSummary` result (7-day stale window) and serve it flagged `stale` when the RPC is unreachable. Drop individual cached buckets whose `resetTime` has already passed.
- **Acceptance check:** With Antigravity closed, the tile shows the last-known windows with a `stale` badge rather than vanishing; buckets past their reset are hidden.
- **Guardrails:** Do NOT present stale data as fresh — always badge it. Do NOT assume Antigravity shares a pool with Gemini (see P1 tile copy). Tile copy reads "separate from Gemini app (unconfirmed)".
- **Depends on:** none.

### P0.7 — Port quota resilience layer to `CursorUsageClient`  ·  **NEW**
- **Labels:** `P0-critical` `provider-cursor`
- **Context:** The Cursor client currently fetches naively; the retry/cooldown/stale-cache pattern built for Claude (P0.2) should back it too for consistent offline/error behavior.
- **Scope:** Refactor the P0.2 resilience helper into a small reusable component and have `CursorUsageClient` use it (retry ≤3, persisted cooldown, 7-day stale-serve).
- **Acceptance check:** With the network mocked to fail, Cursor serves its last-known quota flagged `stale` instead of showing an error; a test proves cooldown suppresses back-to-back calls.
- **Guardrails:** Do NOT change the Cursor auth/cookie logic (shipped + verified). Do NOT alter the WorkOS token handling.
- **Depends on:** P0.2 (reuses its helper).

---

## PHASE P1 — dashboard

### P1.1 — Provider tiles: plan label + live window bars + reset countdowns  ·  **NEW** (REFINES #21)
- **Labels:** `P1-high` `design`
- **Context:** The hub's core surface — one tile per provider showing every live window (5h / weekly / monthly) as a labeled bar with a live reset countdown. This is where quota parity becomes visible.
- **Scope:** A tile component driven by `[QuotaWindow]`: plan label (from provider metadata), one bar per window with used% fill, color `≥90% red / ≥70% amber / else emerald`, and a countdown to `resetAt`. Padzy theme (`aitracker.json`); mono numerals; hairline bars. `.unavailable` providers render an honest empty state, not a fake bar.
- **Acceptance check:** With all four providers feeding sample windows, each tile shows correctly-colored bars and live-updating countdowns; a provider with `.unavailable` shows the empty state.
- **Guardrails:** Follow the Padzy design system exactly — no library-default rounding/shadows. Respect `prefers-reduced-motion` on the countdown. Do NOT invent token numbers; bars are percentage-only.
- **Depends on:** P0.3 (for Claude to have windows; other providers already do).

### P1.2 — Pace notch marker + linear-burn "on track to end at X%" verdict  ·  **NEW**
- **Labels:** `P1-high` `design`
- **Context:** Raw fill mid-window punishes early-week users. A linear-burn expected-position marker plus a projection verdict turns a bar into a "are you ahead or behind pace" read.
- **Scope:** For windows with a trusted length (5h, 7d hardcoded; Cursor cycle computed from `billingCycleEnd` − cycle start), compute `elapsed = (len − timeToReset)/len`, render a notch at the even-burn position (cut into the fill, hidden until used ≥5%), mark it red when `used > expected + 3pp`, and show a hover verdict ("on track to end at X%" / "ahead — runs out in ~3h") plus the exact local reset datetime. Windows of unknown length render usage only, no marker.
- **Acceptance check:** A weekly window at 50% used with 50% time elapsed shows an on-pace (non-red) notch; at 80% used / 50% elapsed the notch is red and the verdict projects >100%.
- **Guardrails:** Do NOT draw a pace marker for windows whose length isn't trusted (billing-cycle windows without a known start) — usage-only, per spec. Do NOT animate the notch if reduced-motion is set.
- **Depends on:** P1.1.

### P1.3 — Activity heatmap: 52-week blended daily-fill + percentile fallback  ·  **NEW** (REFINES #25)
- **Labels:** `P1-high` `design`
- **Context:** The signature "did you use what you pay for, day by day" view. Uses the §4 daily-allotment math where quota samples exist, and falls back to personal-percentile-on-tokens so it works day-one from existing parsed history.
- **Scope:** 52-week grid. Primary mode: per-provider `fill = day_used_pp / daily_allotment_pp` (weekly ÷ 7; Cursor 100pp ÷ cycle-days), blended across providers by plan-price weight, capped 200%. Fallback mode (no samples / pre-sampler history): 5 levels from quantiles (p50/p75/p90) of the user's own non-zero token days. Cells carry the right confidence badge. Tooltip: per-provider breakdown + exact tokens. Stats: active days, current + longest streak.
- **Acceptance check:** With sample series present, cells reflect daily-fill % and a perfect-pace day reads ~100%; with only token history, cells render the percentile fallback and are badged `.estimated`/`.localParsed`.
- **Guardrails:** Do NOT use 5h windows in the daily denominator (burst allowance only). Do NOT present fallback-mode cells as quota-accurate — badge them. Padzy palette, not GitHub greens.
- **Depends on:** P0.4 (samples) — degrades without it via fallback.

### P1.4 — "Route work here" chip on the least-filled provider  ·  **NEW**
- **Labels:** `P1-high` `token-maxxer`
- **Context:** Directly answers spec question 3 ("which provider is underused right now"). A single chip nudges routing toward the provider with the most headroom.
- **Scope:** Among quota-live providers, compute current weekly-window fill and surface a "Route work here →" chip on the lowest. Hidden when no provider is quota-live or all are near-equal.
- **Acceptance check:** Given three providers at 80/40/70% weekly fill, the chip appears on the 40% provider.
- **Guardrails:** Do NOT show the chip for `.unavailable`/`.estimated`-only providers (misleading). Do NOT flicker the chip on tiny fill deltas — require a meaningful gap.
- **Depends on:** P1.1.

### P1.5 — Menu bar "tightest window %" display mode  ·  **NEW**
- **Labels:** `P1-high`
- **Context:** The menu bar shows a summed token total today; an optional mode showing the single most-constrained window % is the fastest "am I about to get capped" glance.
- **Scope:** Settings toggle: menu bar shows either today's token total (current) or the highest used% across all live windows, with the provider glyph. Updates on refresh.
- **Acceptance check:** In tightest-window mode, the menu bar reflects the max used% across providers and updates when that window changes.
- **Guardrails:** Do NOT break the existing token-total mode (default stays). Do NOT include `.unavailable` windows in the max.
- **Depends on:** P0.3.

---

## PHASE P2 — Token Maxxing layer

### P2.1 — One-time plan-price setup prompt (prefilled, skippable)  ·  **NEW**
- **Labels:** `P2-medium` `token-maxxer`
- **Context:** The overall Maxxing score weights providers by monthly subscription price (§3). Prices are public; the plan is knowable per provider. This prompt collects them once.
- **Scope:** A setup sheet listing each detected provider with its plan prefilled where possible (Claude tier from Keychain `rateLimitTier`, Cursor from `stripeMembershipType`, Antigravity from decoded protobuf) and an editable monthly price. **Skippable** — skipping a provider excludes it from the overall score and never blocks setup. Persist to UserDefaults.
- **Acceptance check:** Completing the sheet stores per-provider prices; skipping a provider leaves it price-less and it is excluded from the overall-score denominator; setup completes either way.
- **Guardrails:** Do NOT block app usage on this prompt. Do NOT auto-fill a price the user must be told is an assumption — show it as editable and labeled. Local-only; no account/login.
- **Depends on:** none (but precedes score UI).

### P2.2 — Maxxing score engine (`s(U)=min(U/85,1)`, 28-day rolling, price-weighted)  ·  **SUPERSEDES #23 (engine part)**
- **Labels:** `P2-medium` `token-maxxer`
- **Context:** The core "am I maxxing" number. Pure function over the P0.4 sample series; 85 is the single tunable target constant.
- **Scope:** Per completed cycle `s(U)=min(U/85,1)`; per-provider score = `0.7·mean(weekly/monthly s(U)) + 0.3·mean(opened-session s(U))` over 28 days; overall = plan-price-weighted mean across priced providers. Expose 85 as one named constant. Providers with `.unavailable` quota excluded, never zero-scored.
- **Acceptance check:** Unit tests: a provider at 85% every cycle scores 1.0; at 100% scores 1.0 (no penalty); an `.unavailable` provider is absent from `overall`; changing the target constant to 80 shifts scores predictably.
- **Guardrails:** Do NOT penalize hitting 100% (full extraction = full marks). Do NOT include unopened session-days as zeros in the session mean. Do NOT invent token ceilings — score is percentage-derived only.
- **Depends on:** P0.4, P2.1.

### P2.3 — Starvation + underuse flags (workday-aware)  ·  **NEW**
- **Labels:** `P2-medium` `token-maxxer`
- **Context:** Splits "healthy high use" from "capped too early" and "leaving tokens on the table" without judging output quality.
- **Scope:** Starvation: a window hitting 100% with >15% of its duration remaining → mark cycle `starved` (score stays 1.0); ≥2 consecutive starved weekly cycles → routing/upgrade nudge. Underuse: pace <0.4 at ≥50% through a weekly/monthly window, OR zero activity ≥3 consecutive days. Idle rule respects a **workdays-only toggle, default ON**.
- **Acceptance check:** A window capping with 30% time left is flagged `starved` but still scores 1.0; a provider idle Mon–Wed (workdays-only ON) triggers the underuse nudge, while an idle weekend alone does not.
- **Guardrails:** Do NOT lower the score for starvation — it drives advice, not shame. Do NOT count weekend idleness when the workdays-only toggle is ON. Rate-limit each nudge to once per window cycle per provider.
- **Depends on:** P2.2.

### P2.4 — Score UI: hero tier badge + per-provider contribution bars  ·  **REFINES #23 (UI part)**
- **Labels:** `P2-medium` `token-maxxer` `design`
- **Context:** Makes the score the emotional centerpiece — tier badge + how each provider contributes + flags.
- **Scope:** Hero tier from overall score (≥85 "Token Maxxer 🔥", 60–84 "Solid", 35–59 "Leaving tokens on the table", <35 "Paying for air"), per-provider contribution bars, and `starved`/`underused` chips from P2.3. Padzy styling.
- **Acceptance check:** A given set of provider scores renders the correct tier label and proportional contribution bars; flagged providers show their chip.
- **Guardrails:** Follow Padzy design system exactly. Keep copy positive-framed (80–90% = "maxxing", never a warning). Respect reduced-motion on any celebratory animation.
- **Depends on:** P2.2, P2.3.

### P2.5 — Notification reframe + underuse nudge + reset-rollover moment  ·  **NEW** (extends shipped notif engine)
- **Labels:** `P2-medium` `token-maxxer`
- **Context:** The existing 80/95 threshold alerts read as warnings; the vision reframes 80–90% as a positive "maxxing" moment and adds underuse + reset-celebration signals.
- **Scope:** Reframe 80–90% notifications to positive copy; add the underuse nudge (P2.3 thresholds, once per cycle per provider) with a "route to <lowest-fill> →" action; add a reset-rollover moment fired when a window drops ≥5pp AND its `resets_at` advances ≥60s (1-hour per-window cooldown, survives relaunch).
- **Acceptance check:** Crossing 85% fires positive copy (not a warning); a detected reset fires exactly one rollover notification and not again within the cooldown; an underuse condition fires at most once per cycle.
- **Guardrails:** Do NOT spam — honor the existing UserDefaults-armed no-spam re-arm and the QUOTA ALERTS toggle. Do NOT fire rollover on sliding-reset jitter (require both the drop and the reset-advance).
- **Depends on:** P2.3.

### P2.6 — Streaks: consecutive days ≥ target% of daily allotment  ·  **REFINES #25**
- **Labels:** `P2-medium` `gamification`
- **Context:** A streak that rewards *using your quota*, not merely opening the app — consecutive days where daily-fill clears a bar.
- **Scope:** Compute current + longest streak of days where blended daily-fill ≥ a threshold (default tied to the 85 target, e.g. ≥50% of daily allotment); surface on the heatmap and score UI.
- **Acceptance check:** A run of 5 qualifying days followed by a miss yields current-streak 0 and longest-streak 5.
- **Guardrails:** Do NOT count zero/near-zero days as streak days (defeats the purpose). Reuse the P1.3 daily-fill math — do not re-derive it.
- **Depends on:** P1.3, P0.4.

---

## PHASE P3 — v2 platform (design-gated; create P3 label if wanted)

### P3.1 — Supabase auth + sync of the sample-series schema  ·  **NEW**
- **Labels:** `token-maxxer` `infra` (add `P3` label)
- **Context:** v2 cross-device view. The P0.4 flat append-only series was built to push as-is; this adds opt-in auth + sync without reworking the data layer. Local-first stays the default.
- **Scope:** Design + implement opt-in Supabase auth and one-way/merge sync of `(provider, windowId, ts, value, confidence, source)` rows, deduped by `(provider, windowId, ts)`. Gated behind explicit opt-in.
- **Acceptance check:** With sync on, two machines' series merge without duplicate rows; with sync off, behavior is identical to v1 local-only.
- **Guardrails:** Do NOT make sync default-on. Do NOT sync tokens/credentials — only percentage series + non-secret metadata. Keep the app fully functional offline.
- **Depends on:** P0.4.

### P3.2 — AI Insights: churn heuristics + routing advice + Wrapped card  ·  **NEW** (REFINES #24)
- **Labels:** `token-maxxer` `growth` (add `P3` label)
- **Context:** The "healthy vs wasteful" nuance the v1 score deliberately avoids — cache-read ratio, burst concentration — plus a shareable recap.
- **Scope:** Compute churn heuristics (Claude cache-read ratio, share of weekly burn inside one 5h session) as flagged *heuristics*, routing recommendations, and a local-render "Wrapped"-style share card.
- **Acceptance check:** Insights surface at least one heuristic + one routing suggestion from real series; the share card renders locally with no network call.
- **Guardrails:** Do NOT fold heuristics into the v1 score (keeps it defensible). Do NOT upload anything to render the card — local only.
- **Depends on:** P0.4, P2.2.

### P3.3 — Dollar-value layer: API-equivalent $ + value multiple  ·  **REFINES #22**
- **Labels:** `token-maxxer` (add `P3` label)
- **Context:** The "flex" metric from the vision (API-equiv $ ÷ subscription $). `Core/Pricing` already exists internally (#22).
- **Scope:** Wire `Core/Pricing` into a per-provider API-equivalent dollar value and an overall value multiple; display as a secondary layer beside the utilization score.
- **Acceptance check:** A provider's tokens × pricing yields an API-equiv $ and a value multiple vs its subscription price.
- **Guardrails:** Value multiple is the v2 flex, NOT the primary metric — utilization stays primary. Do NOT block v1 on this.
- **Depends on:** P2.2. (Reconcile with existing #22.)

### P3.4 — Opt-in value-multiple leaderboard  ·  **REFINES #27**
- **Labels:** `growth` (add `P3` label)
- **Context:** Growth lever; already scoped as #27. Listed here only to place it in sequence.
- **Scope:** See #27. Decision- and monetization-gated.
- **Acceptance check:** Per #27.
- **Guardrails:** Opt-in only; local-first default preserved.
- **Depends on:** P3.1, P3.3. (Update #27 rather than duplicate.)

---

## PHASE P4 — provider expansion (create P4 label if wanted)

### P4.1 — Generalized connector framework + OpenCode / Pi / Gemini CLI / Copilot  ·  **REFINES #26**
- **Labels:** `infra` (add `P4` label)
- **Context:** Adding a provider should be config, not bespoke code. Already scoped as #26; this refines it with the concrete first targets and the known Gemini CLI path.
- **Scope:** A connector framework (passive parse default, optional hook trigger, `status`/`doctor`) so a new tool is a config entry. First targets: OpenCode, Pi, Gemini CLI (`~/.gemini/oauth_creds.json` + `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`), Copilot.
- **Acceptance check:** Adding one new provider requires only a config/adapter entry, and it appears with tokens and/or quota using the shared tile + sampler.
- **Guardrails:** Do NOT hardcode per-provider UI. Do NOT own OAuth refresh flows you can avoid (prefer the tool's own credential file). Reuse the P0.2 resilience layer.
- **Depends on:** P0.4, P1.1. (Update #26 rather than duplicate.)

---

## Reconciliation summary (existing issues)
- **#5** [P2] Claude rate-limit view → **superseded** by P0.2+P0.3 (now P0, live endpoint). Close or re-scope #5.
- **#21** utilization spine → realized by P0.4 + P1.1. Update #21 to point at these.
- **#23** Maxxer Score → split into P2.2 (engine) + P2.4 (UI). Update #23.
- **#25** streaks/heatmap → split into P1.3 (heatmap) + P2.6 (streaks). Update #25.
- **#22** value engine → P3.3. **#24** flex card → part of P3.2. **#26** provider expansion → P4.1. **#27** leaderboard → P3.4.
- **#14** Keychain hardening is a prerequisite posture for P0.2 — link them.
