# Checkpoint — Cursor + Antigravity connectors (2026-07-06)

Self-contained resume point. A new session with ZERO prior context can read this
file + the linked ones and continue. Written because the originating session's
token use got high.

## TL;DR — the goal is NOT done yet
Original ask: "make the Cursor and Antigravity connection happen" = show each tool's
**real usage/quota**, like the app's other providers. Current state ships *honest
scaffolding* but NOT the meaningful quota numbers the user actually cares about:

- **Antigravity**: the real "Model Quota" (per-model **weekly + 5-hour limits as %**,
  e.g. Gemini 92% / 88%, Claude&GPT 100% / 100%, with reset countdowns) is **NOT in
  local storage**. Machine-confirmed: searched every Antigravity `state.vscdb` key/value
  + `app_storage.json` + `storage.json` — absent. The Antigravity app fetches it live
  from Google's backend using the `ya29…` OAuth token. Tokei currently shows only plan
  ("Pro") + a raw local `modelCredits` number (1000) that is **not** the model quota.
- **Cursor**: online path works (real `api2.cursor.sh/auth/usage` decoded), but this
  user is Pro/**uncapped** (`maxRequestUsage: null`, 0 requests) so there is little to
  show. Need to confirm whether a richer quota/limit endpoint exists (Cursor's own
  dashboard shows per-model request usage + plan limits).

**Remaining work = reverse-engineer the live endpoints** (primary: Antigravity Google
backend; secondary: verify Cursor's best usage endpoint) and wire real quota into the
existing `.providerReported` network path, behind the existing opt-in toggles.

## Repo state
- Branch `dev` @ `453fa1c` (clean). `main` untouched. Nothing tagged/released.
- Product: **Tokei** (`ai.padzy.tokei`), local-first macOS AI-usage dashboard.
  xcodegen + xcodebuild. Test scheme `AIUsageDashboardCore`, build scheme
  `AIUsageDashboardApp`. `.xcodeproj` is gitignored → run `cd AIUsageDashboard &&
  xcodegen generate` before building. 85 Core tests green.
- Round-2 worktrees still on disk (can be pruned): `../tokei-worktrees/2026-07-06-*`.
- Gates in `.claude/gates/` (`run-all.sh full`), pre-commit hook, Patch Bible workflow
  (`/morning-patch` → `/agents-done` → `/dev-approved`|`/dev-reject`). Dev-branch model.

## What shipped this round (all on dev, verified)
Merged connector round (Bible: `tasks/patch-bibles/2026-07-06.md` §"ROUND 2"):
- `dcfb832` Antigravity connector (Codex) — offline protobuf via zero-dep `MiniProtobufReader`.
- `fad1dd4` Connection UX (Claude Code UI) — per-provider show/hide toggles, honest
  capability tiers, local-path disclosure, Cursor online toggle.
- `f78c1f8` Cursor connector (Kimi) — A offline (plan/tier + accepted-lines) + B network.
Post-merge fixes (live-verified in the running app):
- `a63053a` — plan-only providers count as "available" (Cursor was rendering UNAVAILABLE).
- `baa5e11` — real `api2.cursor.sh/auth/usage` schema decoded; removed Antigravity's
  fabricated credits gauge (was a unit-mismatched "50% / 100"); honest info instead.
- `453fa1c` — flipping the Cursor online toggle now triggers `viewModel.refresh()`
  (was a no-op until the next file-watch). Verified: SYNCED advances on each flip.

## Machine-verified technical facts (this Mac, 2026-07-06)
See also repo memory `usage-data-sources.md` and GH issues #3 (Cursor), #4 (Antigravity).

### Antigravity
- DB: `~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb`, table `ItemTable`.
  - `antigravityAuthStatus` = JSON `{name, email, apiKey, userStatusProtoBinaryBase64}`.
    - `apiKey` = **Google `ya29…` OAuth access token** (SECURITY: read-only, never log/persist).
    - `userStatusProtoBinaryBase64` → base64 → protobuf: plan "Pro" (field 13→1→2),
      model catalog (field 33). Also `antigravityUnifiedStateSync.userStatus` protobuf →
      `g1-pro-tier` / "Google AI Pro" + model catalog + upgrade URL `antigravity.google/g1-upgrade`.
  - `antigravityUnifiedStateSync.modelCredits` → protobuf → `availableCredits=1000`,
    `minimumCreditAmountForUsage=50`. **NOT the model quota.**
  - `antigravityUnifiedStateSync.oauthToken` present too.
- **Real Model Quota (target) is NOT local.** It's the per-model-group weekly + 5-hour
  limit %s + reset times shown in the Antigravity app / antigravity.google. Fetched live
  from a Google backend with the `ya29` token. **Endpoint unknown — must be discovered.**

### Cursor
- DB: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, `ItemTable`:
  - Plan (offline): `cursorAuth/stripeMembershipType`="pro", `cursorAuth/stripeSubscriptionStatus`="active", `cursorAuth/cachedEmail`.
  - `cursorAuth/accessToken` = JWT bearer (SECURITY: value leaves process only as `Authorization: Bearer` over TLS).
  - `aiCodeTracking.dailyStats.v1.5.<YYYY-MM-DD>` = `{tabAcceptedLines, composerAcceptedLines, …}` (lines, not tokens).
- **Real online endpoint `GET https://api2.cursor.sh/auth/usage`** (Bearer JWT) → verified 200:
  ```json
  { "<model>": {"numRequests":Int,"numRequestsTotal":Int,"numTokens":Int,
                "maxTokenUsage":Int?,"maxRequestUsage":Int?}, ...,
    "startOfMonth":"<ISO8601>" }
  ```
  This account: `gpt-4` 0 requests, `maxRequestUsage:null` (Pro = uncapped). Decoder now
  emits a % gauge only when a model has a real cap, else an honest request-count.
  - Alt: `https://www.cursor.com/api/usage` → HTTP 308 redirect (needs `WorkosCursorSessionToken`
    cookie, not the bearer). Cursor's dashboard "included usage" / plan limits may live here.

## The remaining goal — reverse-engineer live quota
### Primary: Antigravity Google-backend quota endpoint
Find the request the Antigravity app makes to render its "Model Quota" page (weekly/5h %
per model group + reset times), then replay it with the local `ya29` token.
Discovery options (pick, likely combine):
1. **Static scan** the Antigravity app bundle/resources for API URLs
   (`grep -rniE "quota|ratelimit|rate_limit|googleapis|antigravity.google" <app resources>`).
2. **Network capture**: proxy the Antigravity app (Electron/VSCode fork) via mitmproxy /
   Charles with a trusted cert; open the Model Quota page; capture the quota call
   (URL, headers, `Authorization: Bearer ya29…`, body/response JSON).
3. Check for a documented Google/Antigravity API (antigravity.google) for rate-limit/quota.
Then: build `AntigravityQuotaClient` (URLSession, ya29 Bearer), decode weekly + 5h % per
model group + reset timestamps → `QuotaWindow`s (convention: `used` = percent 0–100,
`limit`=100; `resetAt` from the countdown). Gate behind a Settings toggle mirroring
Cursor's (`antigravityOnlineQuotaEnabled`, default OFF). `.providerReported` confidence.

### Secondary: Cursor real quota/limits
Confirm what Cursor's own dashboard shows as "quota" for capped plans; verify whether
`api2.cursor.sh/auth/usage` is the right/complete source or whether `cursor.com/api/usage`
(cookie `WorkosCursorSessionToken` from state.vscdb) is needed for plan limits. Decide if
the current per-model request display satisfies the goal or needs the dashboard endpoint.

## Constraints (carry forward, non-negotiable)
- SECURITY: `state.vscdb` files hold live unencrypted OAuth tokens / JWTs. Read-only.
  Token values leave the process ONLY as a Bearer header to the provider's own TLS
  endpoint. Never log/cache/persist/print them. Antigravity parser already uses SQL
  `json_extract` so the `apiKey` never enters Swift memory — keep that property.
- Paid/live APIs: these are the user's own read-only usage endpoints; a manual live call
  to confirm shape is fine (done for Cursor). Confirm before any write/mutating call.
- Frozen contracts: `UsageProvider` protocol; `ProviderSnapshot` fields + `ModelCodableExtensions.swift`
  (append-only, both edited in the same commit). Plan/tier/credits surface via `ProviderWarning`
  ("Plan: …") + `QuotaWindow` — no new stored field unless truly needed.
- `QuotaWindow` gauge convention: `used` = **percent 0–100**, `limit` = 100 (see `CodexJSONLParser.quotaWindow`).
- Gates green before done: `bash .claude/gates/run-all.sh full`. `xcodegen generate` first.
- UI work → Claude Code + `padzy-os` skill ("aitracker" theme). External agents get theme
  tokens inlined, never "run the skill".

## Suggested next-session orchestration
1. **Scout (research, no code)**: discover the Antigravity quota endpoint (static scan +
   proxy capture). Verify Cursor's best endpoint. Produce a findings doc with exact
   URL/headers/response schema for both. ← do this FIRST; everything depends on it.
2. **Build** (once endpoints known): `AntigravityQuotaClient` + provider wiring +
   Settings toggle (Core, Codex or Claude). Cursor enrichment if needed (Core).
3. **UI**: Claude Code + padzy-os — render the weekly/5h quota gauges + reset countdowns
   on the Antigravity card; ensure Cursor card shows real quota when capped.
4. Verify live in the running app (drive it via `screencapture` + AppleScript
   `click at {x,y}` — a11y works in this session's Mac), gates green, then `/dev-approved`.

Fresh orchestrator prompt for the new session is in this session's final message and
appended below.

---

## Fresh orchestrator prompt (paste into the new cloud session)

> I'm continuing the Tokei (`ai.padzy.tokei`) macOS AI-usage dashboard. You are the
> release engineer / orchestrator. Read `tasks/checkpoints/2026-07-06-connectors-checkpoint.md`
> first — it is the full resume point (repo state, machine-verified data sources, security
> constraints, what's done, what's not).
>
> Goal not yet achieved: show the **real usage/quota** for **Cursor** and **Antigravity**,
> like the app's other providers. Antigravity's real "Model Quota" (per-model weekly +
> 5-hour limit %s with reset countdowns) is fetched live from Google's backend with the
> local `ya29` OAuth token and is NOT in local storage — the endpoint is unknown.
>
> Start by orchestrating a **scout/research phase (no product code)** to reverse-engineer
> the live endpoints:
> 1. Antigravity: find the exact request the app makes to render Model Quota — static-scan
>    the app bundle for API URLs AND/OR proxy-capture its traffic (mitmproxy/Charles) — get
>    URL + headers + response JSON schema. It authenticates with `ya29…` (Bearer).
> 2. Cursor: confirm `api2.cursor.sh/auth/usage` (bearer JWT) is the right source for
>    quota/limits, or whether `cursor.com/api/usage` (WorkosCursorSessionToken cookie) is
>    needed for plan limits. Real api2 schema is in the checkpoint.
> Produce a findings doc with exact endpoints/headers/schemas. Then plan the build phase
> (live quota clients behind opt-in Settings toggles, `.providerReported`) via `/morning-patch`.
>
> SECURITY (non-negotiable): OAuth tokens/JWTs are read-only; they leave the process only
> as a Bearer header to the provider's own TLS endpoint; never log/cache/persist/print them.
> Confirm before any mutating/paid call. dev-branch model; gates green; `xcodegen generate`
> before building.
