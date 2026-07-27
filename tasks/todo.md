# Tokei — stale-quota routing bug + multi-account Claude tracking

Source diagnosis: `/tmp/tokei-diagnosis.md` (2026-07-27).
Approach: TDD per patch — RED (watch it fail) → GREEN (minimal) → REFACTOR.
Test gate: `./.claude/gates/test.sh` (scheme `AIUsageDashboardCore`).

Previous todo (herdr dispatch, DONE 2026-07-24) archived — see git history.

## P1 — gate routing on trust  (root cause of the reported bug)
- [x] RED: stale/`local_estimate` 0% must NOT win `routeTo` over an official 75%
- [x] RED: `avoid` still lists an untrusted provider at/over threshold (asymmetric)
- [x] RED: `routeTo` nil when fewer than 2 *trusted* readings; reason names the exclusion
- [x] GREEN: `routableConfidences` gate in `AgentRecommendationEngine.recommend`
- [x] Existing `AgentRecommendationEngineTests` still green

## P2 — make staleness structural
- [x] RED: stale serve stamps `observedAt` from the cache's `fetchedAt`; live stamps now
- [x] RED: `AgentWindow.observedAt` emitted; additive, schemaVersion stays 1
- [x] GREEN: `observedAt` on `QuotaWindow` → `Utilization` → `AgentWindow` (+ Codable, back-compat)
- [x] GREEN: `maxRoutableAge` (30m) backstop for official-but-old readings

## P3 — stop the tight-window decay
- [x] RED: partially-expired cache must report nothing, not the loosest window
- [x] GREEN: `cachedWindows` refuses a partial set outright
- [x] GREEN: `maxStaleInterval` 7 days → 2 hours

## P4 — honour Retry-After + observability
- [x] RED: `Retry-After: 3537` makes exactly ONE request, no 30s-sleep retries
- [x] GREEN: break the retry loop when `retryAfter > maxRetrySleepInterval`
- [x] GREEN: `Logger` on 429 / 401 / non-2xx (fetch path previously logged nothing)
- [x] Updated the existing test whose assertions encoded the old retry-storm

## P5 — multi-account Claude (`~/.claude`, `-account-1`, `-account-2`)
- [x] RED+GREEN: `ClaudeAccount` — keychain service = `sha256(path)[0:8]`, default unsuffixed
- [x] RED+GREEN: discovery finds sibling `~/.claude-*` dirs holding `projects/`
      (correctly skips `~/.claude-worktrees`)
- [x] RED+GREEN: per-account credentials reader; per-account cache/cooldown files
- [x] RED+GREEN: `ClaudeCodeProvider(accounts:usageClientFactory:)` — tokens SUM,
      headline quota = account with MOST HEADROOM, per-account detail preserved
- [x] RED+GREEN: `ProviderAccountUsage` + `AgentAccount` in the public schema (additive)
- [x] GREEN: `ProviderRegistry` + `FileWatcher` use `ClaudeAccount.discover()`
- [x] GREEN: Accounts section in the app's provider drill-in

## Verify
- [x] `./.claude/gates/test.sh` green
- [x] `./.claude/gates/build.sh` green
- [x] Real artifact: `recommendation` went from `routeTo: claude_code` (stale 0%) to `null`
- [x] Real artifact: all 3 accounts tracked with separate token totals
- [x] Real artifact: per-account warnings correctly attribute cooldown vs expired creds
- [ ] Real artifact: live quota window returns after the default account's cooldown (05:42Z)

## Known real-world state (not defects)
- `account-1` / `account-2` OAuth access tokens are **expired** (03:56Z / yesterday 19:14Z).
  Tokei reads but never refreshes them — refreshing would race the Claude CLI's own
  rotation. Run `CLAUDE_CONFIG_DIR=~/.claude-account-N claude` once to rotate.
- Release-config `dist/Tokei.app` fails to launch: framework signed Developer ID, app
  binary a different Team ID. Pre-existing; unrelated to this work. Debug build is fine.
