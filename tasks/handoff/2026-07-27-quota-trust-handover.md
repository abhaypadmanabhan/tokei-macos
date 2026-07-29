# Handover — quota-trust fix landed, follow-on work identified

**Date:** 2026-07-27 · **Branch:** `dev` · **Commit:** `f725bac` · **Version:** 0.7.1
**Full diagnosis:** `/tmp/tokei-diagnosis.md` (regenerate if gone — findings summarized below)

---

## What just landed (`f725bac`, 22 files, +1368/−108)

`tokei status --json` was recommending fan-out work to `claude_code` on a **stale
cached 0%** (served during a 429 cooldown, `confidence: local_estimate`) over Codex's
real 75%. Root cause was the *consumer*: `AgentRecommendationEngine.recommend` ranked
purely on `usedPercent` and never read the `confidence` that `Utilization` already
carried.

Five fixes, all TDD, `test.sh` + `build.sh` green, **verified in the packaged app**:

1. **P1** — `routeTo` gated on `routableConfidences` + ≥2 trusted readings + 30m
   `maxRoutableAge`. `avoid` still uses *every* reading (asymmetric on purpose).
   Exclusions named in `reason`.
2. **P2** — `observedAt` added to `QuotaWindow` → `Utilization` → `AgentWindow`.
   Staleness is now a number, not a `" (stale)"` string suffix. Additive; schemaVersion
   stays 1; old caches decode.
3. **P3** — partially-expired cache now returns nothing instead of the loosest surviving
   window (short windows expire first and short windows are the tight ones, so the
   survivors always flattered the provider). `maxStaleInterval` 7d → 2h.
4. **P4** — honours `Retry-After` > 30s (one request, not three). Logging added on
   429/401/non-2xx; the fetch path previously logged **nothing**.
5. **P5** — multi-account Claude. `ClaudeAccount` derives the per-`CLAUDE_CONFIG_DIR`
   Keychain service (`Claude Code-credentials-<sha256(path)[0:8]>`, unsuffixed for
   default), discovers sibling `~/.claude-*` dirs holding `projects/`, and keys caches
   per account. `ClaudeCodeProvider` sums tokens, takes headline quota from the account
   with **most headroom**, and preserves per-account detail via
   `ProviderAccountUsage` / `AgentAccount`.

**Live proof (packaged app, not tests):**
- stale 0% → `recommendation: null` (refuses to route)
- real data → `routeTo: claude_code, 7%` (routes normally)
- 3 accounts reported separately, 277M tokens summed, per-account cache files on disk

---

## Outstanding work (candidates for this patch)

Ordered by my read of severity. All evidence verified this session — no speculation.

### P0 — Release build is unlaunchable
`dist/Tokei.app` built by `scripts/build-app.sh` dies at load:
```
dyld: Library not loaded: @rpath/AIUsageDashboardCore.framework/…
Reason: … mapping process and mapped file (non-platform) have different Team IDs
```
Framework signs Developer ID (`project.yml` Core target, Release config), app binary
does not match. **Pre-existing, unrelated to `f725bac`, and it blocks the next
release.** Debug config is unaffected. Start at `project.yml` Release `CODE_SIGN_IDENTITY`
/ `DEVELOPMENT_TEAM` across the Core, App, and `tokei` targets.

### P1 — CursorUsageClient has the same retry-storm bug
`AIUsageDashboardApp/Core/Network/CursorUsageClient.swift:129`
```swift
await sleep(min(retryAfter ?? cooldownStore.defaultCooldownInterval, Self.maxRetrySleepInterval))
```
Identical to the Claude bug fixed in P4: sleeps its own 30s ceiling and retries against
an arbitrarily long `Retry-After`. Apply the same early-exit
(`if let retryAfter, retryAfter > maxRetrySleepInterval { throw .rateLimited(...) }`)
plus the missing logging. **Note:** Cursor does *not* serve a stale quota cache, so it
has no P3-style decay and no stale-routing exposure — this is retry behaviour only.

### P2 — AntigravityQuotaClient doesn't set `observedAt`
`AIUsageDashboardApp/Core/Network/AntigravityQuotaClient.swift:182` still hand-appends
`"antigravity-local-rpc (stale)"`. It *does* downgrade to `confidence: .estimated`, so
P1's gate already blocks routing to it — this is not a live routing bug. But it should
adopt `observedAt` so its age is structured like Claude's. Nothing enforces the
convention; consider a shared helper so the next client can't forget.

### P3 — Three route-target heuristics still disagree
Documented as FOLLOW-UP in `AgentRecommendationEngine.swift:1-20`:
- `AgentRecommendationEngine.recommend` — now trust-gated, 85% avoid, no spread gate
- `MaxxerMath.routeTarget` (UI chip) — requires ≥15-point spread, **not trust-gated**
- `DashboardView.routeTargetProviderID` — no threshold at all, **not trust-gated**

Only the first feeds agents, so the bug is fixed where it mattered, but the two UI
heuristics can still point at a stale reading. `MaxxerMath` lives under `UI/MenuBar/`
and isn't in the Core framework, so reconciling needs it moved into Core first — that's
picking one canonical policy, not deleting a duplicate.

### P4 — Recommendation `reason` doesn't name the account
With multi-account live, `reason` reads "route to Claude Code (tightest window 7%)"
without saying *which* account that 7% belongs to. The data is in `accounts[]`
(`AgentAccount.id` is the path to set `CLAUDE_CONFIG_DIR` to), but the human-readable
line should name it.

### P5 — `discoverLogSources()` now swallows errors
`ClaudeCodeProvider.discoverLogSources()` unions across accounts with `try?` per
account, so a genuinely broken directory no longer throws. `fetchSnapshot` still warns
correctly via the private per-account path. Decide whether the public
`LocalLogProvider` contract should surface partial failure.

---

## Environment state (not code defects)

- **`~/.claude-account-2` OAuth token is expired** (2026-07-26T19:14Z). Tokei reads but
  never refreshes — refreshing would race the Claude CLI's own rotation. Run
  `CLAUDE_CONFIG_DIR=~/.claude-account-2 claude` once. `account-1` rotated itself during
  verification and now reports live quota, so the path is proven.
- **A Debug Tokei is running** from `AIUsageDashboard/build/dev/Build/Products/Debug/Tokei.app`
  (same path it was running from before). Kill with
  `pkill -f "build/dev.*Contents/MacOS/Tokei"`.
- **Uncommitted, pre-existing:** five deleted PNGs under `tasks/brand/` and
  `tasks/handoff/`. Deleted before this session, deliberately left unstaged.

## Ruled out — do not re-investigate

- **Anthropic edge TLS-fingerprinting / 403 "Request not allowed" is NOT happening.**
  Tested live with identical headers: system `curl` → 200, Node `fetch` → 200, Swift
  `URLSession` → 200. The staleness was a genuine 429 cooldown plus the P3 decay.
- **Empty `windows[]` handling was already correct** — a provider with no computable
  window is absent from `peakByProvider` and cannot be routed to. Never the bug.

---

## Guardrails for this patch

- Tests are the contract: `./.claude/gates/test.sh` (scheme `AIUsageDashboardCore`).
  `AgentRecommendationEngineTests` encodes the trust-gating rules — if a change makes
  those fail, the change is wrong, not the tests.
- The asymmetry is deliberate: **`avoid` from all readings, `routeTo` from trusted
  only.** Do not "simplify" it into one filter.
- `peak-then-gate` ordering in `recommend()` is deliberate and commented — a provider
  whose *tightest* window is untrusted must not be routable on a looser trusted one.
- Verify in the real artifact, not just tests. Release config can't launch (see P0), so
  use the Debug build for runtime checks until that's fixed.
