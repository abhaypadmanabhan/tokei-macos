# Findings — Cursor + Antigravity live quota endpoints (2026-07-06)

Scout/research output. Reverse-engineered the live endpoints that render each tool's
**real usage/quota**. All machine-verified on this Mac, 2026-07-06. NO product code written.

**Headline:** Antigravity's Model Quota (the previously-unknown blocker) is fully solved —
and via a **local, token-free** path, not the remote Google backend the checkpoint assumed.
Captured the real response live.

---

## 1. Antigravity — Model Quota (SOLVED, live-captured)

### How it actually works (architecture)
Antigravity bundles a 119 MB Go binary — the Codeium/Windsurf "Cascade" language server
(codename `exa`/`jetski`) at:
`/Applications/Antigravity.app/Contents/Resources/bin/language_server`

When the app runs, that binary launches with (from live `ps`, PID varies):
```
language_server --standalone --override_ide_name antigravity --subclient_type hub \
  --https_server_port 0 --csrf_token <UUID> --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com --enable_sidecars
```
- It exposes a **local HTTPS connect-rpc server** on `127.0.0.1:<port>` (auto-assigned; two
  ports listen — one is TLS, the other LSP).
- The workbench UI calls that local server (authed with the `--csrf_token`) to render the
  Model Quota page. The local server fetches the real numbers from Google
  (`cloud_code_endpoint`) internally using the `ya29` token — **so we never touch ya29.**
- Prod host is `cloudcode-pa.googleapis.com`; this user is on the **daily** channel
  (`daily-cloudcode-pa…`). Irrelevant to us — we use the local path.

### THE ENDPOINT (recommended integration — local, no token egress)
```
POST https://127.0.0.1:<httpsPort>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary
Headers:
  Content-Type: application/json
  x-codeium-csrf-token: <csrf>
Body: {}          # empty request works; server already has the user context
TLS: self-signed  → skip cert validation for 127.0.0.1 ONLY
```
Protocol = Connect (buf connect-rpc), unary, JSON. `/exa.<pkg>.<Service>/<Method>` path shape.

### Discovery (how the client learns port + csrf — no manifest file exists on disk)
- **csrf**: read `--csrf_token <UUID>` from the language_server process args (`ps`).
  Rotates every app launch. Localhost-only, low sensitivity — still never log/persist.
- **httpsPort**: `lsof -nP -iTCP -sTCP:LISTEN -p <language_server pid>` → it listens on 2
  ports; probe each with the TLS connect-rpc call and use whichever returns HTTP 200
  (the other throws `wrong version number` = not TLS). Robust, self-correcting.
- Process match: `pgrep -f 'language_server --standalone'`.

### REAL RESPONSE (captured live, port 61515, HTTP 200, application/json)
```json
{ "response": {
  "groups": [
    { "displayName": "Gemini Models",
      "description": "Models within this group: Gemini Flash, Gemini Pro",
      "buckets": [
        { "bucketId": "gemini-weekly", "displayName": "Weekly Limit",
          "description": "You have used some of your weekly limit, it will fully refresh in 4 days, 12 hours.",
          "window": "weekly", "remainingFraction": 0.9150608, "resetTime": "2026-07-11T18:48:56Z" },
        { "bucketId": "gemini-5h", "displayName": "Five Hour Limit",
          "description": "You have used some of your 5-hour limit, it will fully refresh in 4 hours, 30 minutes.",
          "window": "5h", "remainingFraction": 0.8757648, "resetTime": "2026-07-07T10:45:03Z" } ] },
    { "displayName": "Claude and GPT models",
      "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
      "buckets": [
        { "bucketId": "3p-weekly", "displayName": "Weekly Limit", "window": "weekly",
          "remainingFraction": 1, "resetTime": "2026-07-14T06:14:13Z" },
        { "bucketId": "3p-5h", "displayName": "Five Hour Limit", "window": "5h",
          "remainingFraction": 1, "resetTime": "2026-07-07T11:14:13Z" } ] } ],
  "description": "Within each group, models share a weekly limit and a 5-hour limit. Quota is consumed proportionally to the cost of the tokens…" } }
```

### Schema
| Path | Type | Meaning |
|---|---|---|
| `response.groups[]` | array | one per model group |
| `groups[].displayName` | string | e.g. `Gemini Models`, `Claude and GPT models` |
| `groups[].description` | string | which models are in the group |
| `groups[].buckets[]` | array | the limit windows for the group |
| `buckets[].bucketId` | string | stable id: `gemini-weekly`/`gemini-5h`/`3p-weekly`/`3p-5h` |
| `buckets[].displayName` | string | `Weekly Limit` / `Five Hour Limit` |
| `buckets[].description` | string | human countdown text; **omitted when full** (remainingFraction=1) |
| `buckets[].window` | string | `weekly` \| `5h` |
| `buckets[].remainingFraction` | float 0–1 | **fraction REMAINING** (1 = untouched) |
| `buckets[].resetTime` | ISO8601 UTC | when the window fully refreshes |

Confirms the checkpoint's "Gemini 92%/88%": the app shows `remainingFraction` as a %.
This capture: Gemini **91.5% wk / 87.6% 5h** remaining; Claude&GPT **100% / 100%**.

### Mapping to Tokei's `QuotaWindow` (convention: `used` = percent 0–100, `limit` = 100)
- `used = round((1 - remainingFraction) * 100)`, `limit = 100`, `resetAt = resetTime`.
- One `QuotaWindow` per bucket (2 per group). Label from `displayName` + group `displayName`.
- Decide in build: show **remaining %** (what the app shows) vs **used %** (Tokei gauge
  convention). Recommend gauge fill = used, label = "N% left".

### Bonus: plan/tier enrichment via the SAME local channel (no ya29)
`POST …/exa.language_server_pb.LanguageServerService/GetUserStatus` (same headers, body `{}`) →
```json
{"userStatus":{"name":"…","email":"…","planStatus":{"planInfo":{
  "teamsTier":"TEAMS_TIER_PRO","planName":"Pro","monthlyPromptCredits":50000,
  "monthlyFlowCredits":150000,"maxNumChatInputTokens":"16384", …},"availablePromptCredi…"}}}
```
Richer than the local protobuf plan ("Pro"). Optional card enrichment.

### Related RPCs seen in the binary (for reference)
`GetPlanStatus`, `GetUserSubscription` (on `exa.seat_management_pb.SeatManagementService`),
`GetUserAnalyticsSummary`, `GetModelStatuses`. Not needed for the quota goal.

---

## 2. Cursor — usage/quota (confirmed: current endpoint is correct)

Base host `api2.cursor.sh` (bearer JWT from `cursorAuth/accessToken`). Uses both REST and
connect-rpc (`/aiserver.v1.<Service>/<Method>`).

### THE ENDPOINT (already wired — confirmed the right/complete source for quota)
```
GET https://api2.cursor.sh/auth/usage
Authorization: Bearer <JWT>
```
Response (verified in checkpoint): per-model `{numRequests, numRequestsTotal, numTokens,
maxTokenUsage?, maxRequestUsage?}` + `startOfMonth`. `max*Usage` = the cap (null = uncapped).
This IS the usage/quota source. For this Pro account `maxRequestUsage:null` (uncapped) → little
to show, but the decoder correctly emits a % gauge only when a real cap exists.

### Plan enrichment (same bearer, NO cookie / NO cursor.com needed) — CAPTURED LIVE
`GET https://api2.cursor.sh/auth/full_stripe_profile` (Bearer JWT) → HTTP 200, real response:
```json
{"membershipType":"pro","subscriptionStatus":"active","individualMembershipType":"pro",
 "isYearlyPlan":false,"isOnBillableAuto":true,"customerBalance":null,"isTeamMember":false,
 "teamMembershipType":null,"trialEligible":false,"trialLengthDays":7,"verifiedStudent":false,
 "lastPaymentFailed":false,"pendingCancellationDate":null,"paymentRecoveryAction":null}
```
**CORRECTION (verified):** this endpoint carries plan/billing metadata **only — NO quota or
included-request number.** It does *not* enable a usage gauge. Useful solely for an accurate
plan label: e.g. `Pro · monthly · auto-billing on`. Fields: `membershipType`/`individualMembershipType`
(pro), `subscriptionStatus` (active), `isYearlyPlan` (bool), `isOnBillableAuto` (usage-based auto),
`customerBalance` (credit, null here), `pendingCancellationDate`, `lastPaymentFailed`.

Other client endpoints (`GetHardLimit`, `getUsageBasedPremiumRequests`, `usage-based`,
`/dashboard/analytics`) are usage-based-pricing / dollar-spend-limit territory — a $ cap, not a
request quota. Not relevant unless the user is on usage-based billing (this account: uncapped Pro).

### Verdict
`GET api2.cursor.sh/auth/usage` is the correct, complete quota source and is already wired.
For this **uncapped Pro** account, **no request limit is exposed by any endpoint** — the honest
display is per-model request counts with no gauge (`maxRequestUsage:null` = truth). `cursor.com/api/usage`
(WorkosCursorSessionToken cookie) is NOT needed. `full_stripe_profile` adds only a richer plan
label, not a gauge — include it just to show plan/billing accurately.

---

## 3. Recommended build architecture (deviates from checkpoint — decision needed)

Checkpoint assumed: remote ya29 → Google backend. **Discovery says: use the local
language_server connect-rpc instead.**

| | Local connect-rpc (RECOMMENDED) | Remote ya29 → cloudcode-pa |
|---|---|---|
| ya29 handling | **none** — token never enters Tokei | must read/refresh/send ya29 |
| Data | full, real, identical to app | must reverse remote proto path/encoding (unknown) |
| Auth | localhost csrf (rotates, low-risk) | OAuth bearer (high-sensitivity) |
| Works when app closed | **no** (needs running app) | yes — but ya29 refresh also needs the app |
| Complexity | low (captured & proven) | high (not captured; would need mitmproxy) |

Local wins decisively: safer, simpler, proven. The only tradeoff is "app must be running" —
acceptable for a usage dashboard, and consistent with reading other providers' live state.

### Build shape (for /morning-patch)
1. **Core**: `AntigravityQuotaClient` — discover pid/csrf/httpsPort (ps + lsof, probe TLS),
   `POST RetrieveUserQuotaSummary`, decode groups→buckets → `QuotaWindow[]`
   (`used=(1-remainingFraction)*100`, `limit=100`, `resetAt=resetTime`), `.providerReported`.
   Optionally `GetUserStatus` for plan enrichment. Behind Settings toggle
   `antigravityOnlineQuotaEnabled` (default OFF), mirroring Cursor's toggle.
2. **Core (optional)**: Cursor `full_stripe_profile` for included-usage limit — only if wanted.
3. **UI** (Claude Code + padzy-os): render 2 groups × 2 windows as gauges + reset countdowns
   on the Antigravity card; ensure Cursor card shows real quota when capped.
4. Verify live in running app; gates green (`xcodegen generate` first); `/dev-approved`.

### Security (carry forward)
- Local path: no ya29 for quota. csrf is localhost-only + rotates — never log/persist/print.
- TLS cert-skip must be scoped to `127.0.0.1` only, never global.
- No mutating calls. All endpoints here are reads of the user's own state.
