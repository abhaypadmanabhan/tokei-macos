# Tokei — Quota Dashboard & Token Maxxing Spec

**Date:** 2026-07-08 · **Status:** DRAFT — awaiting Abhay review · **No code in this cycle.**
**Inputs:** live machine probes (this Mac), TokenTracker source read (cloned, `src/lib/usage-limits.js` + dashboard), 2026 web research with citations. Sources: `tasks/reports/2026-07-07-tokentracker-gap-analysis.md`, memory `usage-data-sources.md`.

**Locked decisions honored:**
- Token Maxxing = quota-window utilization (provider's own %), NOT dollar/absolute-token budgets. Dollar value = v2 layer.
- v1 local-only, notarizable, no login. Data layer shaped so Supabase sync + AI Insights bolt on in v2 without rework.

---

## 1. Quota Model Table (2026, researched 2026-07-08)

| Provider | Windows | Reset cadence / anchor | Shared pool | Local data | Live quota source | Confidence |
|---|---|---|---|---|---|---|
| **Claude** (Pro / Max 5x / Max 20x) | 5h session · 7-day all-models · 7-day model-scoped (Opus; API also has Sonnet field) | 5h rolling from first message; weekly at fixed per-account time | **YES** — one pool: claude.ai chat + Claude Code + Desktop + **Cowork** | Tokens: `~/.claude/projects/**/*.jsonl` ✓ (shipped). Limits: **NOT in any local file** (re-verified today) | `GET api.anthropic.com/api/oauth/usage` (undocumented; OAuth token from Keychain) — **probed HTTP 200 on this Mac today** | Existence HIGH · stability MEDIUM (unversioned endpoint) |
| **Codex** (ChatGPT Plus/Pro/Business) | Rolling 5h + weekly, both **token-metered** since 2026-04; + purchasable credits + "reset bank" (bankable resets since 2026-06) | Windows anchor to first request after reset (rolling, non-calendar) | Shared across all Codex surfaces (CLI/IDE/cloud/review); separate from ChatGPT chat today, merging with "other agentic features" — in flux | `~/.codex/sessions/*.jsonl` has `rate_limits.primary/secondary` (`used_percent`, `resets_at`) — **we already parse this, shipped** | Local JSONL (shipped) or `chatgpt.com/backend-api/wham/usage` (needs token refresh via `auth.openai.com`, public client `app_EMoamEEZ73f0CkXaXp7hrann`) | HIGH (local path machine-verified) |
| **Cursor** (Pro $20 / Pro+ / Ultra) | **Monthly pools only** — no 5h/weekly. Two pools: first-party (Auto/Composer) + API-credit (named models). Auto is no longer "unlimited" per current docs | Monthly billing cycle; reset = `billingCycleEnd` from API | N/A (no siblings) | Plan/auth in `state.vscdb`; **no token/quota offline** | `cursor.com/api/usage-summary` + CSV export, WorkOS cookie auth — **shipped + live-verified 2026-07-08** (7% used, Pro) | HIGH |
| **Antigravity** (free / AI Pro $20 / Ultra) | Per-model-group buckets, each with **5h + weekly** windows (paid: 5h-refresh; free: weekly-dominant). Volatile — limits raised ~3x twice in H1 2026 | 5h refresh toward weekly cap; anchor semantics unpublished — per-bucket `resetTime` from RPC is only ground truth | **UNCONFIRMED** — evidence says separate per-product quotas on same subscription tier; do NOT assume shared with gemini.google.com / Gemini CLI | Plan + credits in `state.vscdb`; **no upstream token counts exist at all** | Local language_server connect-rpc `RetrieveUserQuotaSummary` (csrf from `ps`, port from `lsof`) — **shipped**; bucket ids seen in TokenTracker: `3p-weekly`, `3p-5h`, `gemini-weekly`, `gemini-5h` | MEDIUM (RE'd, fragile across app updates; requires app running — mitigate with stale cache) |

**Cross-cutting facts:**
- **Nobody publishes absolute token ceilings** for subscription plans. Claude/Codex/Antigravity all expose *percent + reset time* only. This is exactly why utilization-% is the right (and only defensible) v1 metric — validates the locked decision.
- Anthropic's only-ever absolute numbers (Aug 2025: Pro 40–80h Sonnet/wk, Max 20x 240–480h) are stale (pre-2026 limit doublings) — usable for marketing copy tone, never math.
- Antigravity is the only provider with quota-but-no-tokens; Claude was tokens-but-no-quota (fixed by §2).

---

## 2. Claude Quota Gap — Diagnosis (findings first, then fix)

### Findings (machine-verified today, read-only)

1. **Local logs genuinely lack limit state.** Grep of recent `~/.claude/projects/**/*.jsonl`: only an API-error shape (`error: "rate_limit"`, `isApiErrorMessage`) — no `used_percent`, no `resets_at`, no unified rate-limit fields. Our `.unavailable` stub was honest for local-only.
2. **Credentials live in macOS Keychain**, not `~/.claude/.credentials.json` (doesn't exist on this Mac). Keychain item `"Claude Code-credentials"` → JSON `claudeAiOauth { accessToken, refreshToken, expiresAt, scopes[user:profile, user:inference, …], subscriptionType: "max", rateLimitTier: "default_claude_max_5x" }`. Token was valid (~6.7h remaining) at probe time.
3. **Endpoint probe: `GET https://api.anthropic.com/api/oauth/usage`** with `Authorization: Bearer <keychain token>` + `anthropic-beta: oauth-2025-04-20` → **HTTP 200**. One call, status only, no token persisted.
4. **`~/.claude.json`** carries subscription metadata usable for labels: `oauthAccount.organizationRateLimitTier`, `hasExtraUsageEnabled`, `cachedExtraUsageDisabledReason` — no live percentages though.

### How the reference repo (TokenTracker) does it — `src/lib/usage-limits.js`

- Same endpoint + same headers. Auth: macOS → `security find-generic-password -s "Claude Code-credentials" -w` (2s timeout); Linux/Win → `~/.claude/.credentials.json`.
- **Response schema:** top-level `five_hour`, `seven_day`, `seven_day_opus`, each `{ utilization: 0–100, resets_at: ISO8601 }`; plus `extra_usage`; plus newer generic `limits[]` array with `kind: "weekly_scoped"` entries (`scope.model.display_name`, `percent`, `resets_at`) for model-scoped weeklies — they dedupe scoped-"Opus" against `seven_day_opus`.
- **No token refresh** — deliberate. On 401: "run `claude` once to refresh" (Claude Code refreshes the keychain itself). Avoids owning an OAuth refresh flow.
- **429 discipline (endpoint shares budget with Claude Code itself):** (a) in-request retry ≤3 honoring `retry-after` capped 30s; (b) persisted cooldown file (default 5min, cap 60min) — upstream call **skipped entirely** while cooling; (c) stale-serve cache: fresh TTL 10min, serve stale ≤7d flagged `stale: true`; cache invalidated the moment any window crosses its own `resets_at`.

### Proposed fix (P0 item, ~1 dev-day)

New `Core/Network/ClaudeUsageClient.swift` (sibling of `CursorUsageClient` / `AntigravityQuotaClient`):
- Read Keychain `"Claude Code-credentials"` (fallback `~/.claude/.credentials.json`), check `expiresAt`, never log/persist token (existing security posture).
- Call `/api/oauth/usage`; map → existing `QuotaWindow` (percent convention already matches: `used` = %, `limit` = 100): `five_hour` → `.session`, `seven_day` → `.weekly`, `seven_day_opus` / `weekly_scoped[]` → `.perModel` with `bucketKey`. `confidence: .providerReported`. `label` from `subscriptionType`/`rateLimitTier`.
- Port the 429 cooldown + stale-cache pattern (also protects Codex/Cursor clients later).
- `ClaudeCodeProvider.fetchSnapshot()` swaps hardcoded `.unavailable` stubs for client output; stubs remain the failure fallback. Add `.quota` capability. Behind an opt-in network toggle like `cursorNetworkUsageEnabled`. **UI needs zero changes** — `DashboardView` gauge rows light up automatically (Codex-proven path).
- Dev-time task: capture one real response body to pin decoder field names (probe was status-code-only).

---

## 3. Token Maxxing Scoring

### Principles
- Score input = the provider's OWN window utilization % (locked). No invented token ceilings.
- **Using what you pay for is good.** 100% at reset = perfect, not a warning. The failure modes are (a) leaving quota on the table, (b) starvation — hitting the cap long before reset and sitting blocked.
- Score must be computable from data we actually have per provider; degrade honestly (confidence tiers already exist).

### Per-window cycle score
For each completed window cycle (a 5h session window, a weekly window, or a monthly cycle), let `U` = utilization at reset (0–100, from provider %).

```
s(U) = min(U / 85, 1.0)        // linear ramp; 85%+ at reset = full marks (1.0)
```

- 85 chosen so "maxxed" is achievable without requiring cap-slamming; 80–90% band renders as "maxxing 🔥" (matches vision memo framing).
- `U = 100` still scores 1.0 — hitting the cap is NOT penalized (you extracted full value).

**Starvation flag (the "healthy high use vs wasteful churn" split):** utilization alone can't judge output quality, so v1 does not pretend to. Instead, distinguish *when* the cap hits:
- If a window reaches 100% with **>15% of the window duration remaining**, mark the cycle **starved**. Starved ≥2 consecutive weekly cycles → surface "you're capping early — route overflow to <lowest-fill provider> or upgrade" nudge. Score stays 1.0; the flag drives routing advice, not shame.
- Churn *signals* (low cache-read ratio on Claude, >50% of weekly burn inside one 5h session) are P3 "Insights" material — flagged as heuristics, never score modifiers in v1. Keeps the score defensible.

### Live (mid-window) display — pace, not raw fill
Raw fill % mid-window punishes people early in the week. Use TokenTracker's linear-pace idea:

```
elapsed  = (window_len − time_until_reset) / window_len
pace     = U / (85 × elapsed)          // 1.0 = on track to land at 85% by reset
projected_at_reset = U / elapsed       // shown as "on track to end at X%"
```

Pace markers only for windows with trusted lengths: 5h and 7d (hardcoded), Cursor cycle (computed from `billingCycleEnd` − cycle start). TokenTracker deliberately omits pace for windows of unknown length — copy that discipline.

### Provider Maxxing % (rolling 28 days)
```
provider_score = 0.7 × mean(s(U) over completed weekly/monthly cycles in window)
               + 0.3 × mean(s(U) over 5h-session cycles, counting only sessions that were opened)
```
- Weekly/monthly = the real capacity you paid for → dominant weight.
- 5h sessions: only score sessions the user actually started (an untouched day ≠ ten failed sessions); unopened days are handled by the underuse nudge, not the score.
- Cursor (monthly, one cycle at a time): mid-cycle use `pace` clamped to 1.0 as the provisional score; final `s(U)` on cycle close.
- Antigravity: score the per-group weekly buckets; provider score = mean across groups the user actually uses (nonzero burn in 28d).

### Overall Token Maxxing Score
```
overall = Σ (plan_price_p × provider_score_p) / Σ plan_price_p
```
Weight by **monthly subscription price** (known: user confirms plan at setup; tiers are public — Claude Max 5x $100, Cursor Pro $20, etc.). Price weighting is honest ("am I using what I *pay* for") without needing token ceilings — and it pre-wires the v2 dollar-value layer (same denominators). Providers with `.unavailable` quota are excluded from `overall` and labeled, never silently zero-scored.

**Display tiers:** ≥85 "Token Maxxer 🔥" · 60–84 "Solid" · 35–59 "Leaving tokens on the table" · <35 "Paying for air".

### Underuse nudge threshold
Trigger "you're not using X" when either:
- **Pace rule:** at ≥50% through a weekly/monthly window, `pace < 0.4` (i.e., trending to land under ~34% at 85-target normalization), OR
- **Idle rule:** provider with an active paid plan has zero token activity for ≥3 consecutive days (from our local parsers — works even where quota is `.unavailable`).
Nudge is rate-limited to once per window cycle per provider. Companion positive signal: "Route work here →" chip on the provider with the lowest current weekly fill among quota-live providers.

---

## 4. Daily Budget Math (heatmap denominator)

Problem: "% of daily allotment" across mixed cadences (5h rolling / weekly / monthly). Rules:

1. **Budget off the LONG window only.** 5h windows are burst allowances, not daily capacity — they never define the daily denominator (they feed the session score + starvation flag instead).
2. **Daily allotment in percentage-points (pp), not tokens** (ceilings unknown):
   - Weekly providers (Claude, Codex, Antigravity weekly buckets): `daily_allotment = 100pp / 7 ≈ 14.3pp`.
   - Cursor monthly: `daily_allotment = 100pp / days_in_cycle` (~3.2–3.4pp). **Suggested daily pace shown in UI: `remaining% / days_left_in_cycle`** — self-correcting: under-use early → pace suggestion rises; run-dry projection `projected_end = used% / elapsed_fraction`, and if >100% show ETA "runs dry ~July 19".
3. **Day's consumption in pp = delta sampling.** A background sampler polls each live quota source every 15–30min while app runs; store `(timestamp, window_id, used%)` snapshots (new lightweight series in JSON store). `day_used_pp = last_sample(day) − first_sample(day)`, reset-crossing handled by detecting % drop + `resets_at` advance (TokenTracker's reset-detector predicate: drop ≥5pp AND reset_at advance ≥60s). Gaps (app closed): attribute the observed delta proportionally across the gap days, mark those cells `.estimated`.
4. **Heatmap cell value (per provider):** `fill = day_used_pp / daily_allotment_pp`, cap display at 200%. Cell = 100% means "perfect even pace".
5. **Multi-provider blended cell:** price-weighted mean of per-provider fills (same weights as the overall score). Consistent story: heatmap, tiles, and score all share one weighting scheme.
6. **Fallback when quota sampling absent** (provider `.unavailable`, or history predating sampler): TokenTracker-style personal-percentile levels on absolute local tokens (quantiles of user's own nonzero days at p50/p75/p90 → 5 levels). Cells rendered in the fallback mode carry the `.estimated`/`.localParsed` badge. This also means the heatmap works day-one from existing parsed history, then upgrades as samples accrue.

---

## 5. Feature List — Phased

### P0 — Quota + usage parity (all four providers show tokens AND quota where they exist)
- [ ] **Claude live quota** (§2): `ClaudeUsageClient` + Keychain auth + 429 cooldown/stale-cache + opt-in toggle. Closes #5/#21-spine gap. *The* unlock.
- [ ] Claude `.perModel` scoped-weekly windows (Opus/Sonnet) rendered like Antigravity buckets.
- [ ] Shared-pool disclosure label on Claude tile: "includes claude.ai + Cowork usage".
- [ ] Quota snapshot **sampler + series persistence** (feeds §4; additive `ModelCodableExtensions` entry — persistence rule!).
- [ ] Codex: adopt duration-based window classification (18000s/604800s), not slot position — free-tier puts weekly in `primary_window` (TokenTracker lesson); surface credits/reset-bank fields if present in local JSONL.
- [ ] Antigravity: stale-cache when app not running (7d, `stale` flag) instead of gauge disappearing.
- [ ] Port 429/stale-cache pattern to Cursor client (currently naive).
- [ ] Data-layer prep for v2 sync: every stored series row carries `(provider, window_id, ts, value, confidence, source)` — flat, append-only, trivially syncable later. No auth code.

### P1 — Dashboard
- [ ] **Hub view**: per-provider tiles — plan label, live window bars (5h / weekly / monthly) with reset countdowns, pace notch marker (linear-burn expected position, red when >3pp over), "on track to end at X%" tooltip verdict.
- [ ] **Heatmap** (§4): 52-week grid, blended daily-fill mode with percentile fallback; tooltip = per-provider breakdown + exact tokens; streak + active-days stats.
- [ ] "Route work here" chip (lowest current weekly fill).
- [ ] Menu bar: optional switch from token total → headline "tightest window %" (most-constrained provider).

### P2 — Token Maxxing layer
- [ ] Maxxing score engine (§3) on the sampled series; per-provider + overall; 28d rolling.
- [ ] Score UI: hero tier badge, per-provider contribution bars, starved/underused flags.
- [ ] Notifications: existing 80/95 alerts → reframe 80–90 as positive "maxxing 🔥"; add underuse nudge (§3 thresholds); add reset-rollover moment (drop ≥5pp + reset advance ≥60s, 1h cooldown — TokenTracker's detector predicate).
- [ ] Streaks: consecutive days ≥X% of daily allotment (not just nonzero) + longest-streak stat.

### P3 — v2 platform (decision-gated, design-only until then)
- [ ] Supabase auth + sync of the P0 series schema; local-first stays default.
- [ ] AI Insights: churn heuristics (cache-read ratio, burst concentration), routing advice, weekly recap ("Wrapped"-style share card — local render).
- [ ] Dollar-value layer on `Core/Pricing` (#22): API-equivalent $ + value multiple (the flex metric).
- [ ] Opt-in leaderboard (#27).

### P4 — Provider expansion
- [ ] OpenCode, Pi, Gemini CLI, Copilot via generalized connector framework (config-not-code; hook-trigger optional, passive parse default). Gemini CLI path known from TokenTracker: `~/.gemini/oauth_creds.json` + `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`.

---

## 6. Open Questions (need Abhay)

1. **Undocumented-endpoint risk appetite:** `api/oauth/usage` is unofficial and unversioned; ToS-adjacent (reads your own account with your own token, same as TokenTracker/CodexBar/ccusage ecosystem). OK to ship behind opt-in toggle with "may break without notice" label? (Recommend: yes — entire competitor ecosystem does.)
2. **Sampling cadence:** 15min vs 30min polling for the quota series (429-budget vs heatmap resolution). Recommend 15min with the cooldown layer; confirm.
3. **Score weighting = plan price** requires asking the user their plan/price once at setup (we can prefill: Claude tier from keychain `rateLimitTier`, Cursor from `stripeMembershipType`, Antigravity from protobuf). Acceptable one-time prompt in local-only v1?
4. **85% target constant** for "maxxed" — feel right, or tune (80? 90?)? Pure product taste.
5. **Underuse idle rule** (3 days zero activity) — count weekends? Recommend a "workdays only" toggle default ON.
6. **Antigravity shared-pool wording:** Google doesn't confirm whether Antigravity shares quota with Gemini app/CLI. Tile copy: say nothing, or "separate from Gemini app (unconfirmed)"?
7. **Claude Sonnet-scoped weekly:** API exposes `seven_day_sonnet` but docs vague — render any `weekly_scoped` entry generically (recommended) or hardcode Opus+Sonnet?
8. **Codex remote endpoint:** local JSONL already gives windows (shipped). Also add `chatgpt.com/wham/usage` live path (fresher, includes credits + reset-bank, but needs owning OpenAI token refresh + writing back `auth.json`)? Recommend: defer to P2; local JSONL is fresh enough (updates every turn).
9. **`hasAvailableSubscription: false` + `out_of_credits`** currently in your `~/.claude.json` — extra-usage credits exhausted. Show extra-usage state (`extra_usage` field) as a fourth Claude bar or hide until non-zero?
10. **Version bump:** this plan spans multiple releases — keep shipping on `dev` with the existing RC flow, or cut 0.2.0 first? (Public-push still blocked on #11 history sweep.)
