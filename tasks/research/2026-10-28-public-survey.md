STATUS: READY

# Public survey: AI usage trackers vs Tokei 0.10.0 (2026-10-28)

Read-only study. Clones are in `/private/tmp/claude-501/-Users-abhayp-Downloads-Projects/04360742-b00d-4738-9d1f-5eb253893cef/scratchpad/survey/`
(read, never run). Probe scripts for the local proofs are in `.../scratchpad/probe/` and printed numbers only, no conversation text.
"Verified" = read in source or reproduced on this Mac. "Unverified" = taken from a doc or inferred. Paths below are relative to each repo unless they start with `Tokei:`.

## 1. Repos studied

| Repo | License | Last commit | Stars | Why it matters |
|---|---|---|---|---|
| steipete/CodexBar | MIT (`LICENSE`) | 2026-10-26 (0.82.0 released 10-26) | 22.9k | 110 providers, menu bar + WidgetKit + CLI (`usage`, `cost`, `guard`, `hooks`, `serve`). No MCP server. |
| ccusage/ccusage (was ryoppippi/ccusage) | MIT in `LICENSE` (GitHub detector says NOASSERTION) | 2026-10-29 03:27Z | 19.2k | Local-log reports; Rust rewrite; blocks, burn rate, projection, statusline. MCP package frozen at 18.x. |
| junhoyeo/tokscale | MIT | 2026-10-26 | 5.8k | ~60 local-log adapters, parsed-message cache, TUI with Usage tab, retention warnings. |
| robinebers/openusage | MIT | 2026-10-28 (0.7.16) | 4.5k | Swift menu bar app; sign-in per account, API-reported values only; `openusage` JSON CLI. |
| douglasmonsky/codex-usage-tracker | MIT | 2026-08-20 on default branch (other branches pushed 10-14; rewrite in progress, 0.28.0 frozen) | 196 | Only repo with a real MCP design (6 tools, graded answers). Slowing. |
| Maciek-roboblog/Claude-Code-Usage-Monitor | MIT | 2026-06-27 | 8.8k | Python TUI. Borderline stale (4 months); read only for P90 limit guess and rolling burn rate. |
| janekbaraniewski/openusage | MIT | 2026-10-26 | 236 | Go TUI; mirrors ccusage reports (`daily`, `blocks`, `statusline install`). Skimmed, no unique technique found. |

Skipped as abandoned or thin: ZhangHanDong/cc-monitor-rs (2025-07), Sapeet/claude-code-usage-monitor-macos, ports of CodexBar to Windows/Linux.

## 2. Ranked gap table

Ranking = value to a Tokei user x (1 / effort), then risk. Effort: S = under a day, M = 1-3 days, L = a week or more.
"Risk" names network, credentials and ToS exposure. Anything touching credentials, cookies or an undocumented endpoint is marked **FLAG**.

| # | Capability Tokei lacks | Who does it | Source file (technique) | Value to a Tokei user | Effort | Risk |
|---|---|---|---|---|---|---|
| 1 | Price Claude cache writes by TTL tier (5m = 1.25x, 1h = 2x input) | tokscale | `crates/tokscale-core/src/sessions/claudecode.rs:460-522` (`cache_write_1h`); LiteLLM field `cache_creation_input_token_cost_above_1hr` (230 models carry it, verified) | High: Tokei prices every cache write at the 5m rate (`Tokei: Core/Providers/PricingService.swift:267-292`, `Parsing/ClaudeJSONLParser+RecordParsing.swift:177` reads only `cache_creation_input_tokens`). On this Mac 64.6% of Claude cache-write tokens in the logs are the 1h tier (425M of 658M raw, duplicates not removed). Order of magnitude: 425M x (10.00 - 6.25)/M = about $1.6k at Opus 4.5 rates against the audited $9.2k MTD; true figure is lower, unverified | S | None. Local logs + existing pricing fetch |
| 2 | Official Claude 5h and 7d quota from Claude Code's statusLine hook, no token read, no network | none of the repos (found in Claude Code docs; ccusage shows the hook plumbing) | `https://code.claude.com/docs/en/statusline`: stdin JSON has `rate_limits.five_hour.{used_percentage,resets_at}`, `rate_limits.seven_day.*`, `cost.total_cost_usd`, `context_window.used_percentage`, `fast_mode`, `effort.level`, `prompt_cache`, `session_id`. ccusage reads the same stdin at `rust/crates/ccusage/src/commands/mod.rs:310` (`run_statusline`) but not `rate_limits` | High: replaces the opt-in OAuth endpoint with `official` confidence and zero credentials. Limits: only Pro/Max, only after the first API response, only fresh while a session runs, Claude has one statusLine slot (must wrap the user's existing command, never overwrite), and writing `settings.json` needs the user's yes. Docs-verified only, not run | M | None for credentials. Touches `~/.claude/settings.json` (ask first) |
| 3 | Antigravity token counts from local conversation databases | ccusage, tokscale | `rust/adapters/antigravity/src/parser.rs:545-638` (protobuf in `gen_metadata.data`: root f1 -> chat model; f4 usage {f2 input, f3 total output, f4 cache write, f5 cache read, f9 reasoning, f10 visible output, f1 model id}; f17 retries; f9 timestamp); tokscale `sessions/antigravity_cli.rs` | High: closes `tasks/BACKLOG.md` P3 "no local per-message log", which this disproves. Reproduced on this Mac: `~/.gemini/antigravity/conversations/17647890-...db`, 123 rows, all decode: 760,786 input, 120,527 output, 13,751,634 cache read, 33,089 reasoning. 161 entries in that folder (.db, -wal, -shm, .pb). Roots to scan: `~/.gemini/{antigravity,antigravity-cli,antigravity-ide,antigravity-backup,antigravity-acp}/conversations/`, `~/.config/antigravity/conversations/` | M (Tokei already has `MiniProtobufReader.swift`, `SQLiteSidecarCopy.swift`) | None (local). Read `gen_metadata` only; other tables hold chat text. Model-id to name map and dedupe by response id needed |
| 4 | GitHub Copilot CLI tokens and AI credits from local session logs | ccusage, tokscale | `rust/adapters/copilot/src/parser.rs:68-200`; `docs/guide/copilot/index.md`. `~/.copilot/session-state/<id>/events.jsonl`, event `session.shutdown`: `data.modelMetrics.<model>.usage.{inputTokens,outputTokens,cacheReadTokens,cacheWriteTokens,reasoningTokens}`, `.requests.count`, `data.totalNanoAiu`, `data.totalPremiumRequests`. Shutdowns are cumulative per session/model; a resume emits another, so take deltas | High: Tokei Copilot reports nothing (`Tokei: Core/Providers/CopilotProvider.swift:3-12`, `capabilities: []`). Verified here: 15 `session.shutdown` events over 17 sessions with real per-model usage and `totalNanoAiu` | M | None (local). tokscale's `~/.copilot/session-store.db` is absent on this Mac, so use session-state |
| 5 | Claude overage ("extra usage") dollars | CodexBar, OpenUsage | Same endpoint Tokei already calls: `extra_usage` {`monthly_limit`,`used_credits`,`utilization`,`currency`} and `spend` {`used.amount_minor`,`limit.amount_minor`,`percent`,`enabled`,`disabled_reason`}. OpenUsage `docs/providers.md` "Extra Usage" row. `tasks/research/claude-usage-response.json` shows $21.52 of $50.00 (43%) | Med-High: tells users how much overage budget is burned. grep finds `extra_usage` only in `Tests/Fixtures/Fixtures.swift`, no app code (verified) | S | None new (same opt-in OAuth call) |
| 6 | Run-out ETA, "lasts until reset", predictive and reset notifications | CodexBar | `Sources/CodexBarCore/UsagePace.swift:64-139` (rate = used/elapsed; eta = (100-used)/rate; `willLastToReset` when eta >= time to reset; 7-stage delta; `dailyTarget` = remaining / local days to reset); `Sources/CodexBar/PredictivePaceWarnings.swift` (notify once per window when not `willLastToReset` and eta > 0); `LimitResetNotifications.swift` | High: Tokei pace is 3-state only (`Tokei: Core/Utilization/QuotaPace.swift`), notifications are fixed 80/95 (`NotificationEngine.swift:198`). "Runs out in 2h10m" is the question users ask | S | None |
| 7 | `tokei guard`: exit-code gate for scripts and agents | CodexBar | `Sources/CodexBarCLI/CLIGuardCommand.swift` (`--min-remaining 10`, `--window session|weekly`, exit 0 safe, 1 below, 64 bad args, 69 unavailable; read-only) | Med: orchestrators without MCP can branch on exit code; Tokei's `status --json` needs parsing | S | None |
| 8 | MCP surface upgrade: `structuredContent` + `outputSchema`, `title`, tool `annotations`, version negotiation; new read-only tools `get_pace`, `get_history`, `get_status` | codex-usage-tracker (graded answers, closed templates); ccusage MCP 18.x (history tools); spec 2025-06-18 | `src/codex_usage_tracker/kernel/interfaces/mcp/catalog.py` (6 tools); `@ccusage/mcp` 18.0.11 `dist/index.js:385-445` (daily, session, monthly, blocks, codex-daily, codex-monthly; shells out to the CLI per call, no annotations). Spec fields `title`, `outputSchema`, `structuredContent` verified at modelcontextprotocol.io/specification/2025-06-18/server/tools. Tokei hardcodes `2024-11-05` and has no annotations (`Tokei: TokeiCLI/MCPServer.swift:26`, grep for annotations/outputSchema empty) | Med: typed output lets agents read numbers without parsing text; history tool answers "what did I burn this week" | S-M | None (read-only, snapshot file) |
| 9 | Provider incident status | CodexBar | `Sources/CodexBarCore/ProviderStatusFetcher.swift` (`GET <statuspage>/api/v2/status.json`, 10 s timeout); `docs/status.md`. Verified 200 with `status.indicator` from `status.claude.com`, `status.openai.com`, `www.githubstatus.com`; `status.cursor.com` answered 301 (not followed). Gemini/Antigravity use `https://www.google.com/appsstatus/dashboard/incidents.json` | Med: explains a stuck or failing quota reading as "provider incident", not a Tokei bug. Tokei has no status code (grep empty) | S-M | Network to third-party status pages, no credentials. Make it a setting like CodexBar's "Check provider status" |
| 10 | Durable per-day history keyed by calendar day, not by a `Date` | CodexBar, tokscale | CodexBar `Sources/CodexBarCore/Vendored/CostUsage/CostUsageStore*.swift` (SQLite, day strings, retention); tokscale `crates/tokscale-core/src/bucket_tz.rs`, `docs/ratchet-inflation-recovery.md` (timezone rescan inflated stored totals), README:1660-1666 (Claude Code deletes logs after 30 days by default, unverified vs Anthropic docs; 0 of 2,472 Claude log files here are older than 30 days, consistent) | Med-High: Tokei writes only "today" on each sync (`Tokei: Core/Storage/UsageStore.swift:87-101`, key = `startOfToday` Date), so days Tokei did not run are lost, no per-model day rows, and a timezone change can split a day. Impact on real users unverified | M | None |
| 11 | Same-origin HTTPS redirect guard on credentialed requests | CodexBar | `Sources/CodexBarCore/ProviderHTTPClient.swift:198-250` (`willPerformHTTPRedirection` allows only https + same scheme/host/port) | Med (security): Tokei's Claude and Cursor clients use `URLSession.shared` (`ClaudeUsageClient.swift:258,275`; `CursorUsageClient.swift:50`) and no redirect policy exists in `Core/Network` (grep empty). Whether Bearer or explicit Cookie headers survive a cross-origin redirect: unverified. Cheap to remove the question | S | None |
| 12 | Session-equivalent forecast ("this week lasts N more 5-hour sessions") | CodexBar | `Sources/CodexBar/SessionEquivalentForecast.swift` (median weekly % per completed session, needs >= 3 samples, partial sessions normalised, #2301); `docs/ui.md:251` | Med: converts abstract % into "can I start another long run" | M (needs `QuotaSeriesStore` samples) | None |
| 13 | Cache hit ratio and turn timing | CodexBar | `Sources/CodexBarCore/CostUsageTurnPerformance.swift`; `docs/spend-turn-performance-validation.md` (median first-token latency, output throughput, cached-input reuse, shown with sample counts). Claude: statusLine `prompt_cache` | Med: cache hit % is a free metric from tokens Tokei already stores; it explains cost jumps | S (hit %), M (latency) | None |
| 14 | Codex regression fixture for forked or interleaved sessions | CodexBar | `docs/issue-2037-ultra-fork-overcount-spec.md`: interleaved `total_token_usage` lineages recounted ~268M real tokens as 3.29B. Tokei sums `last_token_usage` and keeps a cumulative signature (`Tokei: Core/Parsing/CodexJSONLParser.swift:733-777`) so it likely avoids the worst case; replayed parent context across files: unverified | Med: a test that can fail guards the biggest possible error | S | None |
| 15 | Local 5-hour block inference with burn rate and projection (fallback when quota is unavailable) | ccusage, Claude-Code-Usage-Monitor | `rust/crates/ccusage/src/blocks.rs:53-104` (block start = first message floored to the hour, ends 5 h later, gap blocks), `:567-600` (burn = tokens / (last - first entry); projection = tokens + rate x minutes left). Monitor uses a rolling last-hour rate (`core/calculations.py:94`) which reacts faster | Med: gives a clock for users who skip OAuth; confidence must be `local_estimate`. Lower once #2 ships | S-M | None |
| 16 | Codex Fast and Flex service-tier pricing | ccusage | `docs/guide/codex/index.md:69-79`: `thread_settings_applied` events carry `service_tier` (`priority`/`fast`, `flex`, `default`); 2x for GPT-5.6 Sol/Terra/Luna. Tokei has no handling (grep empty). Event exists in 112 local Codex files here, all 152 say `default`, so zero effect on this Mac | Low here, Med for Fast-mode users | S-M | None |
| 17 | Tiered pricing above 200k tokens per request | tokscale, LiteLLM | `crates/tokscale-core/src/pricing/custom.rs:56-61`; LiteLLM `input_cost_per_token_above_200k_tokens` (20 gpt-5/6 and claude entries, verified). Tokei has no tier logic (grep empty). Impact on this Mac unmeasured | Unknown | M | None |
| 18 | Burn-down chart and widget (recorded quota %, dashed even-use line) | CodexBar | `Sources/CodexBar/QuotaBurndownModel.swift`, `PlanUtilizationHistoryStore.swift` (hourly compaction keeps peaks and reset boundaries, 17,520 samples cap), `Sources/CodexBarWidget/BurnDownWidgetViews.swift`; `docs/widgets/burndown-proof.md` | Med: Tokei already stores samples (`QuotaSeriesStore.swift`) but shows a 30-day token trend, not the shape of a window | M | None |
| 19 | Low Power Mode throttle for background work | CodexBar | `Sources/CodexBar/BackgroundWorkPowerPolicy.swift:3-12` (interval >= 30 min in Low Power Mode). Tokei: no `isLowPowerModeEnabled` anywhere (grep empty) | Low-Med: laptop battery, small fix | S | None |
| 20 | Event hooks on quota transitions | CodexBar | `Sources/CodexBarCore/Hooks/` and `docs/configuration.md` "External event hooks": opt-in, absolute path, no shell, env allowlist, 0.1-300 s timeout, 600 s rate limit, edge-triggered, no config via HTTP | Low-Med: Tokei already notifies; hooks add automation | M | Runs user-chosen programs; only copy the whole safety contract |
| 21 | More local-log providers: Goose, Kimi CLI, Qwen CLI, Droid, Pi, Kilo CLI, Zed, Junie | tokscale | `README.md` rows, `crates/tokscale-core/src/sessions/*.rs`; ccusage `rust/adapters/*` | Low-Med (depends on Tokei user base) | M each | None (local) |
| 22 | `tokei serve` local HTTP and web UI | CodexBar | `Sources/CodexBarCLI/CLILocalHTTPServer.swift`, `docs/dashboard-api.md` (loopback only, Host-header check, bearer token required off-loopback) | Low: MCP and CLI already cover agents | L | Opens a socket; **do not add** without a threat model |

## 3. Credential, cookie and undocumented-endpoint flags

Tokei is local-first and never reads browser cookies. Do not import these techniques:

| Technique | Where | Why flagged |
|---|---|---|
| Browser cookie import for Claude web, Cursor, Codex dashboard, OpenCode, ~40 other providers | CodexBar `Sources/CodexBarCore/BrowserCookie*.swift`, `ChromiumSafeStorage.swift`, `Providers/Claude/ClaudeWeb/` | **FLAG cookies.** Decrypts Chromium cookies via the browser's Safe Storage Keychain item; needs Full Disk Access for Safari. Hard no. |
| Codex quota via ChatGPT backend with the Codex CLI's stored token | CodexBar `Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift` (`https://chatgpt.com/backend-api/wham/usage`, `/wham/rate-limit-reset-credits`); OpenUsage and tokscale the same | **FLAG credentials + undocumented endpoint.** Tokei's `codex app-server` probe is the better design (Codex holds its own credential). Keep it. |
| Copilot quota via `GET api.github.com/copilot_internal/user` with a device-flow token | CodexBar `Providers/Copilot/CopilotDeviceFlow.swift:9` uses VS Code's OAuth client id `Iv1.b507a08c87ecfe98`; token kept in plain `~/.codexbar/config.json` (`docs/copilot.md`); OpenUsage same endpoint; tokscale reads the `gh` token | **FLAG undocumented endpoint + impersonated client id + plaintext token.** Use #4 (local logs) instead. |
| Gemini quota via `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` | CodexBar `GeminiStatusProbe.swift:189-194` | **FLAG undocumented endpoint + CLI credential.** Tokei already does this (`Tokei: Core/Network/GeminiUsageClient.swift:320-324`); keep it opt-in. |
| Claude `api.anthropic.com/api/oauth/usage` with Claude Code's token | CodexBar `ClaudeOAuthUsageFetcher.swift:61-92` (beta header `oauth-2025-04-20`, `?cedar_ember=1`); Tokei same, opt-in | **FLAG undocumented endpoint.** CodexBar also falls back to running `claude` in a PTY and scraping `/usage` (`Providers/Claude/ClaudeStatusProbe.swift:75`): credential-free but screen-scraping, brittle. #2 is cleaner. |
| Cursor JWT from `state.vscdb` / Keychain, `cursor.com/api/*` | tokscale README:917, CodexBar `CursorStatusProbe*.swift` | **FLAG credential + undocumented.** Tokei already has an opt-in; no change. |
| Third-party OAuth client ids and mandatory telemetry | OpenUsage `Sources/OpenUsage/Providers/*/…UsageClient.swift`; `docs/privacy.md` ("anonymous daily ping and crash reports ... not optional") | **FLAG ToS + privacy.** Opposite of Tokei's stance. |
| `tokscale submit` uploads usage to a public leaderboard | tokscale README | **FLAG exfiltration by design.** Never. |
| Saving copies of other tools' logins for multi-account switching | tokscale `codex import` (README:913, 938); CodexBar managed Codex accounts (`ManagedCodexAccountStore.swift`, what it copies: unverified) | **FLAG credentials.** Out of scope. |

Guardrail note: one grep of CodexBar source for the literal name of Codex's credential file was blocked by `guard-bash.sh` (secrets rule). I did not retry it. The Codex credential path above comes from `docs/codex.md` in CodexBar ("OAuth API (auth.json credentials)"), not from source I read.

## 4. What each repo measures that Tokei does not (and how)

**CodexBar** (Swift, `Sources/CodexBarCore`, `Sources/CodexBar`, `Sources/CodexBarWidget`)
- Pace with ETA, work-day-aware weekly pace (`UsagePace.swift:81-139`), learned historical pace and run-out probability (`Sources/CodexBar/HistoricalUsagePace.swift`, 966 lines), predictive warnings, session-equivalent forecast, reset notifications.
- Quota history and burn-down (`PlanUtilizationHistoryStore.swift`), widget families: Switcher, Usage, Account Usage, Accounts, History, Metric, Burn Down, Combined Burn Down (`docs/widgets.md`).
- Costs per project and per session/turn with tool activity and turn timing (`CostUsageSessionBreakdown.swift`, `SessionToolActivity*.swift`); `codexbar cost --group-by project`.
- Status pages (#9). Rate-limit reset credits inventory (`ClaudeRateLimitResetCredits.swift`, Codex `/wham/rate-limit-reset-credits`); Tokei already has `CodexResetBankSnapshot` for Codex only.
- Adaptive refresh 2-30 min with an opt-in agent-aware mode (`docs/predictive-refresh-policy.md`, `AdaptiveRefreshCore`); Tokei's fixed 5 min plus file events is already cheap (0.5% idle), so low priority.
- CLI: `usage`, `cards`, `cost`, `guard`, `hooks watch`, `serve`, `dashboard`, `sessions`, `--format toon` (token-cheaper JSON for agents, `ToonFormatter.swift`).
- Live agent session list with Stay Awake (`LocalAgentSessionScanner.swift`, `docs/agent-sessions-design.md`).
- MCP tools exposed: none.

**ccusage** (Rust workspace under `rust/`, npm launcher in `apps/ccusage`)
- Reports: daily, weekly, monthly, session, blocks, statusline (`docs/guide/*.md`); `--instances` groups Claude by project; `--timezone`; `--breakdown` per model.
- Blocks: 5-hour windows, gap blocks, burn rate, projection, `--token-limit max` (`blocks.rs`). Live monitor was removed in v18.
- Pricing: cost modes `auto|calculate|display`, `pricingOverrides` in `ccusage.json` with `fastMultiplier`/`flexMultiplier`, Codex speed tiers (#16).
- Adapters for ~17 tools including Copilot CLI (#4) and Antigravity (#3), `rust/adapters/README.md`.
- MCP: none at HEAD. Last published `@ccusage/mcp` 18.0.11 (2026-04-19) exposes `daily`, `session`, `monthly`, `blocks`, `codex-daily`, `codex-monthly` over stdio or HTTP (verified from the npm tarball, not executed).

**tokscale** (Rust `crates/tokscale-core`, `crates/tokscale-cli`)
- Parsed-message cache with explicit format versions and wire migrations (`message_cache.rs`): bincode shards, per-client parser versions, "Claude entries are the only copy of compacted history". Pattern for #10 and for file efficiency.
- TUI views: Overview, Usage (subscription quotas), Models, Daily, Hourly, Monthly, Sessions, Projects, Stats, Agents; group-by picker (model, client+model, workspace+model, session+model); per-model per-day trend with ms/1K and cost/1M; subagent roll-up toggle.
- `tokscale usage` subscription table (README:891-925): vendor-reported, credential-based (see flags).
- `mcp.rs` is not an MCP server; it lists configured MCP server names for the leaderboard payload.

**OpenUsage (robinebers)** (Swift, `Sources/OpenUsage`)
- Reads nothing from other tools; own sign-in per account, own Keychain service. Shows only API-reported limits.
- Claude windows: Session, Weekly, Sonnet, Fable, Extra Usage, Rate Limit Resets (spend a reset from the app).
- `openusage` CLI prints the last saved fetch as `openusage.limits.v1` JSON, exit 4 when nothing fetched, includes `expiresAt`, `stale`, `windowSeconds` (`docs/cli.md`). Same idea as Tokei's snapshot reader.
- Refresh rules worth copying (`docs/refreshing.md`): last snapshot shown at launch; failures keep last good values with a warning icon; per-account backoff 5 min doubling to 1 h; `Retry-After` honoured for every trigger including manual refresh; catch-up pass on wake.

**codex-usage-tracker** (Python, `src/codex_usage_tracker/kernel`)
- Exact Codex session, turn, call, tool and allowance facts in SQLite; MCP tools `usage_status`, `usage_refresh`, `usage_query`, `usage_evidence`, `usage_allowance`, `usage_job_status`.
- Answer grades on every field: `exact`, `deterministic`, `configured_estimate`, `model_inference`, `unsupported` (`docs/product/SUPPORTED_QUESTION_CONTRACTS.md`). Tokei's `confidence` (official / local_estimate / unavailable) is the same idea; add `deterministic` vs `estimated` only if a field needs it.
- Design rule "the host waits; the model never polls" (`docs/product/AGENT_SETUP_AND_MCP_EXPERIENCE.md`): not needed for Tokei, whose tools read a file.

## 5. UI patterns worth copying

| Pattern | From | Source | Note |
|---|---|---|---|
| Bar colour = where pace lands at reset: blue on course, orange inside the last 10%, red with a flame when you would run out first; hover explains | OpenUsage | `README.md` Features section | Fits Tokei's elapsed tick; form carries state, colour carries urgency (matches the UI rules). Needs #6 |
| Click a value to flip used/left; click a reset to flip countdown/exact time | OpenUsage, CodexBar (`usageBarsShowUsed`, reset-time style) | OpenUsage README; CodexBar `docs/cli.md` serve section | Per-user preference, tiny |
| Star up to two metrics per provider for the menu bar | OpenUsage | `docs/menu-bar.md` | Tokei menu bar is a total only |
| Highest-usage provider auto-selected for the menu bar icon; dimmed icon when stale or errored, incident overlay | CodexBar | `Sources/CodexBar/AutomaticQuotaSelection.swift`, `IconRenderer.swift` | Pairs with #9 |
| Burn-down chart with capture age and a dashed even-use line; no line extended past the last capture | CodexBar | `docs/widgets/burndown-proof.md` | Honest about gaps |
| "Next update in ..." footer, per-account spinner, warning icon with reason in tooltip | OpenUsage | `docs/refreshing.md` | Error state with what happened, what was kept, one fix |
| Daily target for monthly allowances ("remaining / days left") | CodexBar | `UsagePace.dailyTarget` | Good for Cursor and Copilot monthly credits |
| Share-as-image of one provider card with email left out | OpenUsage, CodexBar (`ShareStatsRenderer.swift`) | OpenUsage README | Optional, low |
| Project and session drill-down with sort by cost, tokens, recency; group-by picker | CodexBar `Usage & Spend`, tokscale TUI | `docs/cost-reporting-periods.md`; tokscale README:302-330 | Matches `tasks/BACKLOG.md` "Session drill-down" |
| Provider-pinned and multi-account widgets, "+N more" overflow row | CodexBar | `docs/widgets.md` | Tokei already has WidgetKit; add the account widget when multi-account matters |

## 6. Suggested patch slices (each with its proof)

1. Claude cache-write tiers (#1). Proof: a fixture with 1h and 5m tokens priced by hand; run the app and compare MTD Claude value before and after against an independent recount (as done for 0.10.0).
2. Claude `spend` and `extra_usage` (#5) plus run-out ETA and reset notification (#6). Proof: unit tests on `QuotaPace`; the app against the saved real response `tasks/research/claude-usage-response.json`; one real notification.
3. Antigravity tokens (#3) and Copilot CLI tokens (#4). Proof: totals equal an independent decode of the same files (numbers above are the baseline), both through the real app.
4. MCP upgrade (#8) and `tokei guard` (#7). Proof: `tools/list` shows `outputSchema`; `tokei guard` exit codes 0/1/69 against a fixture snapshot.
5. Statusline relay (#2) after Abhay approves editing `~/.claude/settings.json`; it is the only item that changes a file outside Tokei.

Ask-first items: #2 (writes another tool's settings), #9 (new third-party network calls), #22 (new socket).

## 7. Not verified

- #2 end to end: the hook payload is documented but I did not run a Claude Code session with a hook. Whether `rate_limits` updates often enough between prompts is unknown.
- #1 dollar impact: raw log lines include streaming duplicates and mixed models; the $1.6k figure is an upper-bound order of magnitude, not a measurement.
- #10: "Claude deletes logs after 30 days" comes from the tokscale README; 0 of 2,472 local files older than 30 days is consistent, not proof.
- #11: whether `URLSession` forwards an explicit `Authorization` or `Cookie` header on a cross-origin redirect.
- #14: Tokei behaviour on forked or interleaved Codex sessions; no fixture was run.
- #16, #17 impact on real bills; LiteLLM field coverage per model was counted, not priced.
- Cursor status page (`status.cursor.com`) returned 301; its JSON path was not confirmed.
- Spec field `readOnlyHint` inside `annotations`: the fetched page lists `annotations` but not the hint names.
- CodexBar provider docs beyond Claude, Codex, Cursor, Gemini, Copilot, Antigravity were skimmed, not read.
- I did not read Tokei's UI code; UI rows compare against the changelog and `Core/` only.
- Probe note: the Antigravity decode opened databases with `immutable=1`, which ignores uncommitted WAL pages, so counts may lag the live app slightly. Tokei should use `SQLiteSidecarCopy`.
