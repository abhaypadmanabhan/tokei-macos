# Provider Research — Distilled

## OpenAI Codex

### Local Data Sources
- **Session JSONL**: `~/.codex/sessions/**/rollout-*.jsonl`
  - Fields: `token_count` events containing `total_token_usage` (cumulative), `last_token_usage` (per-event), `input_tokens`, `output_tokens`, `rate_limits` (primary/secondary windows)
  - Gotcha: `rate_limits` is always `null` in `codex exec` mode; in interactive mode contains `used_percent`, `window_minutes`, `resets_in_seconds`
  - Gotcha: `rate_limits`-only updates re-emit previous `last_token_usage`, causing double-counting if summing linearly; use `total_token_usage` snapshots instead

- **Auth**: `~/.codex/auth.json` (ChatGPT plan OAuth token)

### Network Endpoints
- **Interactive rate limits**: Embedded in HTTP response headers on API responses (`x-codex-primary-used-percent`, `x-codex-secondary-used-percent`) and in TokenCount events
- **Usage output**: No official `codex usage` CLI subcommand exists; `/status` in interactive TUI is the sanctioned way
- **Undocumented ChatGPT backend**: `GET https://chatgpt.com/backend-api/wham/usage`
  - Auth: Bearer token from `~/.codex/auth.json`
  - Returns: `primary_window`/`secondary_window` `used_percent`, `reset_at`, `plan_type` (PLUS/PRO/FREE), `credits_balance`
  - Headers also expose: `x-codex-primary-used-percent`, `x-codex-secondary-used-percent`, `x-codex-credits-balance`

### Metrics Available
- 5-hour rolling window (primary): `used_percent`, `window_minutes` (~299), `resets_in_seconds`
- Weekly window (secondary): `used_percent`, `window_minutes` (~10079), `resets_in_seconds`
- Per-event tokens: `input_tokens`, `output_tokens`
- Plan tier & credits balance (via backend endpoint)

### Reliability Notes
- Session JSONL rate_limits null in exec mode (fragile)
- Backend endpoint `/wham/usage` undocumented/reverse-engineered
- Codex usage is shared with ChatGPT for Excel and Workspace Agents; quota is not fixed message-count per plan

### Reference Implementations
- CodexBar: https://github.com/steipete/CodexBar (Swift menu bar, reads ~/.codex, calls /wham/usage)
- codex-hud: https://github.com/Capedbitmap/codex-hud (macOS menu bar, local session parsing)

---

## Claude Code

### Local Data Sources
- **Session JSONL**: `~/.claude/projects/**/*.jsonl` (or `~/.config/claude/projects/` on Linux)
  - Fields: `message.usage` (contains `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`)
  - Gotcha: `usage.input_tokens` streaming placeholders (1 or 0) never updated to final; input_tokens undercounted ~100–174x vs statusbar, output_tokens ~10–17x (cache metrics ~0.7–1.1x reliable)
  - Gotcha: same `requestId` appears 2–10 times with identical placeholder values; requires deduplication

- **Auth (macOS)**: Keychain item service name `Claude Code-credentials`
  - Retrieve: `security find-generic-password -s 'Claude Code-credentials' -w`
  - Returns JSON: `{accessToken: "sk-ant-oat01-[REDACTED]", refreshToken: "[REDACTED]", expiresAt: "[REDACTED]"}`
  - Fallback: `~/.claude/.credentials.json` (Linux/Windows) or `CLAUDE_CODE_OAUTH_TOKEN` env var

### Network Endpoints
- **Official OAuth usage**: `GET https://api.anthropic.com/api/oauth/usage`
  - Auth: Bearer token + header `anthropic-beta: oauth-2025-04-20` + User-Agent `claude-code/<version>`
  - Returns: `five_hour` (session window), `seven_day` (weekly), `seven_day_sonnet`/`seven_day_opus` (per-model), `extra_usage` (overages)
  - Each window has `utilization` (0–100%), `resets_at` (ISO 8601 UTC)
  - Fragile: aggressively rate-limits (429 at even 30–60s intervals); omitting User-Agent causes persistent 429s; 180s intervals reliable

### Metrics Available
- 5-hour session window: utilization %, reset time
- Weekly limit (all models): utilization %, reset time
- Per-model weekly limits (Sonnet, Opus): utilization %, reset time
- Input/output/cached tokens (from JSONL, with caveats)
- Extra usage credits (monthly spend/limit)

### Reliability Notes
- OAuth endpoint undocumented; heavily rate-limited; closed as "not planned" by Anthropic
- JSONL token counts unreliable (streaming placeholders, 100x undercount)
- OAuth tokens expire ~60min; auto-refreshed only while Claude Code runs
- Local JSONL window math incorrect across devices (use OAuth endpoint as authoritative)

### Reference Implementations
- ccusage: https://github.com/ryoppippi/ccusage (CLI, JSONL parser, supports 15+ agents)
- CodexBar: https://github.com/steipete/CodexBar (Swift menu bar, reads Keychain, calls OAuth endpoint)
- ClaudeBar: https://github.com/tddworks/ClaudeBar (multi-provider, refreshes OAuth tokens)
- CCSeva: https://github.com/Iamshankhadeep/ccseva (Swift menu bar, file-change-driven + OAuth fallback)
- VibeMeter (deprecated): https://github.com/steipete/VibeMeter (Swift menu bar, archived May 2026; successor: CodexBar)

---

## Cursor

### Local Data Sources
- **SQLite state**: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  - Query: `SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'`
  - Returns: JWT token; parse `sub` claim for user ID
  - Session token format: `{userId}%3A%3A{accessToken}` (URL-encoded `::` separator)

### Network Endpoints
- **Official Admin API** (team/business-only): https://api.cursor.com
  - Auth: HTTP Basic (username=API key, password="")
  - Endpoints: `/teams/daily-usage-data`, `/teams/filtered-usage-events`, `/teams/spend`
  - Individual users: no official API; only team admins can generate API keys
  - Rate limit: 20 req/min per team (usage events/audit logs); 20–250 req/min other endpoints

- **Undocumented per-user endpoints** (reverse-engineered from web dashboard):
  - Legacy: `GET https://cursor.com/api/usage` (per-model request counts, token usage, monthly cycle dates)
  - Newer: `POST https://api2.cursor.sh/.../GetCurrentPeriodUsage` (per-model request counts, limits)
  - Auth: Cookie header `WorkosCursorSessionToken={token}` (extracted from state.vscdb)
  - Also: `GET https://cursor.com/api/auth/stripe` (plan metadata), `GET https://api2.cursor.sh/auth/usage` (per-model usage)
  - Billing: `POST /api/dashboard/get-monthly-invoice` (spend data)

### Metrics Available
- Per-model request counts (used vs. limit) or token usage (newer plans)
- Dollar spend vs. cap (USD-credit accounts)
- Plan name, subscription status, auto+composer vs. API split
- Monthly cycle dates / next reset
- Billing cycle spend (from /get-monthly-invoice)

### Reliability Notes
- No official per-user API; all endpoints reverse-engineered (fragile, subject to change)
- cursor-stats (canonical reference) archived March 8, 2026; maintainer cited "constant changes in Cursor's pricing policy"
- Different endpoint sets for team vs. individual accounts; must auto-detect

### Reference Implementations
- cursor-stats: https://github.com/Dwtexe/cursor-stats (VS Code extension, session cookie auth, archived)
- cursor-usage-tracker: https://github.com/Tendo33/cursor-usage-tracker (status bar, legacy + newer endpoints)
- cursor-usage-monitor: https://github.com/lixwen/cursor-usage-monitor (auto-reads token from state.vscdb)
- CodexBar: https://github.com/steipete/CodexBar (Swift menu bar, supports Cursor)
- ClaudeBar: https://github.com/tddworks/ClaudeBar (Swift menu bar, Cursor support)

---

## Google Antigravity

### Local Data Sources
- **Running IDE local API**: Connect RPC on 127.0.0.1 (port auto-discovered)
  - Endpoint: `POST /exa.language_server_pb.LanguageServerService/GetUserStatus`
  - Auth: Header `X-Codeium-Csrf-Token` (if available); no OAuth needed
  - Returns: `userStatus.cascadeModelConfigData.clientModelConfigs[]` (per-model), each with `quotaInfo.remainingFraction`, `quotaInfo.isExhausted`; `userTier.availableCredits`

### Network Endpoints
- **Google Cloud Code (reverse-engineered)**: https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist
  - Auth: Bearer token (OAuth)
  - Returns: `availablePromptCredits`, `planInfo.monthlyPromptCredits`, `currentTier`, per-model `quotaInfo`

- **Fallback Google endpoint**: `POST /v1internal:fetchAvailableModels`

### Metrics Available
- Per-model remaining quota (fraction-based, not tokens)
- Per-model exhausted status
- Available credits, monthly credit limit
- ~5-hour reset window (official Google statement)

### Reliability Notes
- Local IDE API: only available while Antigravity runs; update granularity coarse (milestones: 0%, 20%, 40%, 60%, 80%)
- Cloud endpoints marked `v1internal` (private Google APIs; fragile, reverse-engineered)
- Antigravity CLI (`agy`) has no non-interactive quota/usage subcommand (login/quota handled in interactive TUI only)
- Gemini CLI/Gemini Code Assist ending for individuals June 18, 2026; users migrating to Antigravity CLI

### Reference Implementations
- antigravity-usage: https://github.com/skainguyen1412/antigravity-usage (TypeScript CLI, local + Cloud modes, JSON output)
- ClaudeBar: https://github.com/tddworks/ClaudeBar (Swift menu bar, Antigravity support via local API probing)
- agusage: Go CLI (curl installable), per-model quota, JSON output, reads process args for port discovery

---

## Cline

### Network Endpoints
- **Official public API**: https://api.cline.bot (OpenAI-compatible)
  - Documented endpoint: `POST /api/v1/chat/completions` (chat completions)
  - Auth: API key (Bearer token) created at app.cline.bot (Settings > API Keys)
  - No documented balance/usage/credits endpoint in public docs

- **Undocumented internal endpoints** (from VS Code extension source):
  - `GET /api/v1/users/{uid}/balance` (credit balance)
  - `GET /api/v1/users/{uid}/usages` (usage transactions)
  - `GET /api/v1/users/{uid}/payments` (payment history)
  - `GET /api/v1/organizations/{id}/balance` (org credits)
  - Auth: Session-authenticated (via `authenticatedRequest` axios client); requires active user session

### Metrics Available
- Credit balance (current)
- Usage transactions: per-request (model name, credits used in microcredits, timestamp, token counts)
- Org credit balance
- No session/weekly rate-limit windows (credits-based billing only)

### Reliability Notes
- Public API documented; internal balance/usage endpoints undocumented/reverse-engineered (fragile)
- Billing is credit-based (402 Payment Required when exhausted)
- Free models available (no credit consumption); affects spend interpretation
- VS Code extension refreshes on polling intervals (React useInterval)

### Reference Implementations
- Cline (official VS Code extension): https://github.com/cline/cline (proto/cline/account.proto defines internal RPCs)
- DeepWiki: https://deepwiki.com/cline/cline/11.3-credits-and-billing (source-code-derived walkthrough)

---

# Open Questions / Unverified Claims

1. **Codex agentic usage sharing**: Claims Codex usage is shared with ChatGPT for Excel and Workspace Agents, consuming from a single "agentic usage limit" per plan. Flagged as unverified because official OpenAI docs vary by plan tier and the exact consumption model is not consistently documented.

2. **Anthropic Admin API for Pro/Max users**: Research note cites "platform.claude.com Rate Limits API (launched Apr 2026)" but states it "explicitly excludes Pro/Max/Team subscribers." Verify current Anthropic API surface and which user tiers can access usage data.

3. **Cursor pricing model transition**: cursor-stats archived maintainer stated "constant changes in Cursor's pricing policy" (Mar 2026). Verify whether Cursor still uses "premium request" quotas vs. pure token/usage-based billing as of Jul 2026.

4. **Gemini CLI sunset**: Research cites Google ending Gemini CLI/Gemini Code Assist for individuals on June 18, 2026, migrating to Antigravity CLI. Verify migration timeline and whether legacy Gemini CLI is still functional.

5. **Claude JSONL streaming placeholders**: Claims input_tokens undercounted ~100–174x; closed as "not planned" by Anthropic. Verify whether this behavior persists in current Claude Code versions.

6. **Cursor endpoint deprecation risk**: Multiple cursor-* projects (cursor-stats, cursor-usage-monitor) rely on undocumented dashboard endpoints. No way to monitor for breakage short of polling all endpoints regularly or subscribing to Cursor status page.

7. **Antigravity local API authentication**: Some references indicate X-Codeium-Csrf-Token header requirement; others suggest it's optional. Confirm exact auth semantics for the local Connect RPC endpoint.

8. **Cline internal endpoints**: Balance/usage endpoints documented in VS Code extension source but not in official api.cline.bot docs. Verify stability/support status.
