

## Result 1
{
 "question": "For a native macOS (Swift/SwiftUI) dashboard monitoring AI coding-assistant usage, determine for each provider (OpenAI Codex, Claude Code, Cursor, Google Antigravity, Cline): available usage/limit/token/spend metrics, data sources (official APIs, undocumented endpoints, local files, CLI), auth methods, update frequency, reliability, implementation complexity, and ToS considerations \u2014 verifying rather than assuming APIs exist, and cataloguing existing open-source reference implementations.",
 "summary": "Split by provider clusters (each has distinct data-access patterns) plus a cross-cutting angle on existing open-source usage-tracker tools whose source code serves as verified reference implementations for local-file parsing and reverse-engineered endpoints.",
 "angles": [
  {
   "label": "Codex CLI local data & rate-limit endpoints",
   "query": "OpenAI Codex CLI ~/.codex auth.json sessions jsonl token usage rate_limits github how to read usage limits programmatically",
   "rationale": "Targets the highest-priority provider: surfaces GitHub issues/source of codex-rs showing session JSONL schema, the rate_limits payload returned by the backend, and community tooling that parses ~/.codex \u2014 the primary/undocumented data sources for ChatGPT plan session and weekly limits."
  },
  {
   "label": "Claude Code usage parsing & credentials",
   "query": "ccusage parse ~/.claude projects jsonl token usage Claude Code macOS Keychain \"Claude Code-credentials\" OAuth /usage 5-hour session weekly limit",
   "rationale": "Covers how ccusage and similar tools compute tokens/cost from local JSONL transcripts, where OAuth creds live on macOS, and whether the /usage command hits a queryable endpoint \u2014 distinguishing subscription-user options from the org-only Admin/Usage API."
  },
  {
   "label": "Cursor usage endpoints & reference extension",
   "query": "cursor-stats extension github cursor.com api/usage api/auth/me usage-summary WorkosCursorSessionToken cookie premium requests state.vscdb",
   "rationale": "Finds the reverse-engineered dashboard endpoints and cookie-auth technique used by cursor-stats, plus newer usage-summary endpoints and local SQLite state \u2014 and clarifies that the official Admin API is team-only, so undocumented endpoints must be flagged as fragile."
  },
  {
   "label": "Antigravity and Cline usage visibility",
   "query": "Google Antigravity usage limits Gemini 3 quota local logs macOS OR Cline app.cline.bot api.cline.bot credits API usage tracking extension globalState",
   "rationale": "Covers the two newest/least-documented providers together: community findings on Antigravity's opaque rate limits and any local log locations, and whatever API backs Cline's credits dashboard \u2014 areas where the answer may legitimately be 'no reliable source exists'."
  },
  {
   "label": "Existing multi-provider menu-bar trackers",
   "query": "github menu bar app macOS AI usage tracker Claude Codex Cursor \"CodexBar\" OR \"vibemeter\" OR \"CCSeva\" open source swift usage limits dashboard",
   "rationale": "Locates prior art (CodexBar, VibeMeter, Claude/Codex menu-bar apps, unified dashboards) whose repos document exactly which files/endpoints/auth each provider exposes \u2014 the fastest way to verify claims and estimate Swift implementation complexity."
  }
 ]
}

## Result 2
{
 "results": [
  {
   "url": "https://github.com/Dwtexe/cursor-stats",
   "title": "Dwtexe/cursor-stats \u2014 Cursor Subscription usage stats in the status bar",
   "relevance": "high",
   "snippet": "The canonical reference extension the research question names. Displays premium-request/usage-based-pricing stats by calling cursor.com dashboard endpoints authenticated with the WorkosCursorSessionToken session cookie, which it extracts from Cursor's local state.vscdb SQLite database. Its source is the best reference implementation of the reverse-engineered endpoint set (usage, usage-based pricing, monthly invoice) \u2014 all undocumented and fragile."
  },
  {
   "url": "https://cursor.com/docs/account/teams/admin-api",
   "title": "Cursor Docs \u2014 Admin API (Teams)",
   "relevance": "high",
   "snippet": "Official primary source confirming the only documented Cursor usage API is the Admin API, which lives under /docs/account/teams/ and requires a team admin API key with Basic auth \u2014 i.e., it is team/business-only and does not serve individual Pro users. This is the doc that justifies flagging all per-user endpoints (api/usage, auth/me, usage-summary) as undocumented/reverse-engineered."
  },
  {
   "url": "https://github.com/Tendo33/cursor-usage-tracker",
   "title": "Tendo33/cursor-usage-tracker \u2014 real-time Cursor quota in the status bar",
   "relevance": "high",
   "snippet": "Documents both the legacy endpoint (GET https://cursor.com/api/usage) and the newer internal endpoint (POST https://api2.cursor.sh/.../GetCurrentPeriodUsage), and reads local Cursor data on the machine to authenticate \u2014 directly mapping the old-vs-new usage-summary endpoint transition the research question asks about."
  },
  {
   "url": "https://github.com/lixwen/cursor-usage-monitor",
   "title": "lixwen/cursor-usage-monitor \u2014 auto-reads auth token from local SQLite",
   "relevance": "high",
   "snippet": "Demonstrates the local-storage technique: automatically reads the Cursor authentication/access token from the local SQLite database (state.vscdb) and detects billing type from the Cursor API, meaning a native macOS app can obtain credentials without asking the user to copy a browser cookie."
  },
  {
   "url": "https://github.com/YossiSaadi/cursor-usage-vscode-extension",
   "title": "YossiSaadi/cursor-usage-vscode-extension \u2014 remaining fast-premium requests via dashboard cookie",
   "relevance": "medium",
   "snippet": "Explicitly states it reuses the same browser session cookie the cursor.com dashboard uses because 'it's the only way to get you the usage data' \u2014 a second independent confirmation of the cookie-auth technique and of the absence of any official per-user API."
  },
  {
   "url": "https://github.com/Sammy970/cursor-usage-extension",
   "title": "Sammy970/cursor-usage-extension \u2014 lightweight remaining-requests indicator",
   "relevance": "medium",
   "snippet": "README spells out the exact mechanism: the Cursor website exposes a usage API at cursor.com/api/usage requiring the WorkosCursorSessionToken browser session cookie set on login \u2014 useful as a minimal, readable example of the request/auth flow to port to Swift."
  }
 ]
}

## Result 3
{
 "results": [
  {
   "url": "https://github.com/steipete/CodexBar",
   "title": "steipete/CodexBar - Show usage stats for OpenAI Codex and Claude Code, without having to login",
   "relevance": "high",
   "snippet": "The closest prior art to the proposed app: a Swift 6, macOS 14+ menu bar tracker covering Codex, Claude, Cursor, Gemini, Copilot and many more providers, with per-provider session/weekly/monthly windows and reset countdowns. 'Without having to login' means it reads existing local credentials (e.g. ~/.codex/auth.json, Claude OAuth) and calls the same rate-limit/usage endpoints the CLIs use \u2014 its source documents exactly which files/endpoints/auth each provider exposes."
  },
  {
   "url": "https://github.com/steipete/VibeMeter",
   "title": "steipete/VibeMeter - Measure costs for Cursor and other AI providers (macOS menu bar)",
   "relevance": "high",
   "snippet": "Named in the research question as a unified multi-provider dashboard. Native macOS menu-bar app tracking Cursor spend via cursor.com session-cookie endpoints plus Claude Code usage via local JSONL log analysis, including the 5-hour rolling window, tiktoken (o200k_base) token counting, and Claude Pro/Max tier modeling \u2014 a direct reference for both the Cursor API technique and Claude local-file parsing."
  },
  {
   "url": "https://github.com/tddworks/ClaudeBar",
   "title": "tddworks/ClaudeBar - macOS menu bar app monitoring Claude, Codex, Antigravity, and Gemini usage quotas",
   "relevance": "high",
   "snippet": "One of the few open-source trackers that explicitly supports Google Antigravity alongside Claude, Codex, and Gemini \u2014 its source is a rare primary reference for how Antigravity quota/limit data can be obtained locally, which was flagged as the least-documented provider in the research question."
  },
  {
   "url": "https://github.com/Iamshankhadeep/ccseva",
   "title": "Iamshankhadeep/ccseva - macOS menu bar app for tracking Claude Code usage in real-time",
   "relevance": "medium",
   "snippet": "CCSeva (named in the query) tracks Claude Code tokens/costs with 30-second updates, plan auto-detection, and 70%/90% threshold notifications. Built on ccusage-style parsing of ~/.claude JSONL transcripts \u2014 a working reference for session-window math and cost estimation, though Claude-only and Electron rather than Swift."
  },
  {
   "url": "https://github.com/handlecusion/tokcat",
   "title": "handlecusion/tokcat - AI token usage monitor for macOS menu bar (Claude Code, Codex, Cursor, Copilot)",
   "relevance": "medium",
   "snippet": "Another multi-provider macOS menu-bar monitor covering Claude Code, Codex, Cursor and Copilot token usage from local agent logs, visualized as a contribution graph \u2014 useful as a cross-check of which local files each provider writes and how token counts are extracted."
  },
  {
   "url": "https://steipete.me/posts/2025/vibe-meter-monitor-your-ai-costs",
   "title": "Vibe Meter: Monitor Your AI Costs \u2014 Peter Steinberger (author write-up)",
   "relevance": "medium",
   "snippet": "The author's own explanation of VibeMeter's architecture and data sources: how Cursor spend is fetched (dashboard endpoints, auth), why Claude Code tracking is done via local log-file analysis, and the reliability trade-offs of these reverse-engineered approaches \u2014 directly answers the ToS/fragility and implementation-complexity questions."
  }
 ]
}

## Result 4
{
 "results": [
  {
   "url": "https://github.com/steipete/CodexBar",
   "title": "steipete/CodexBar \u2014 macOS menu bar app showing Codex + Claude Code usage",
   "relevance": "high",
   "snippet": "The closest reference implementation for the planned Swift dashboard: a native macOS menu bar app that detects Codex auth via ~/.codex/auth.json, prefers the local `codex app-server` RPC to fetch 5h/weekly limits and credits, and falls back to a PTY scrape of `codex /status`. Source code documents exactly which local files and undocumented endpoints work (flag: RPC/status scrape is reverse-engineered, not an official API)."
  },
  {
   "url": "https://github.com/openai/codex/issues/14728",
   "title": "openai/codex issue #14728 \u2014 feat(exec): emit rate_limits in exec mode JSONL output",
   "relevance": "high",
   "snippet": "Primary-source documentation of the rate_limits payload the Codex backend returns inside token_count events: fields include primary/secondary used_percent, window_minutes, and resets \u2014 the exact data needed for session (5h) and weekly meters. Also flags a key limitation: `codex exec` mode writes rate_limits: null in rollout JSONL, so real-time percentages must come from interactive sessions or the app-server."
  },
  {
   "url": "https://github.com/openai/codex/issues/14489",
   "title": "openai/codex issue #14489 \u2014 TokenCount re-emits last_token_usage on rate-limit-only updates",
   "relevance": "high",
   "snippet": "Details the TokenCount event schema in codex-rs (total_token_usage vs last_token_usage alongside rate_limits), including a gotcha that matters for anyone parsing ~/.codex/sessions/**/rollout-*.jsonl: rate-limit-only updates re-emit the previous nonzero last_token_usage, which can cause double counting of input/output/cached tokens."
  },
  {
   "url": "https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan",
   "title": "Using Codex with your ChatGPT plan \u2014 OpenAI Help Center",
   "relevance": "high",
   "snippet": "Official primary source on how ChatGPT-plan Codex limits work: stacked rolling 5-hour window plus weekly window, both measured in tokens/credits by plan tier, and confirmation that /status in the CLI is the sanctioned way to view remaining limits. Establishes the ground truth (and ToS-safe surface) that any dashboard metrics should be validated against."
  },
  {
   "url": "https://github.com/Capedbitmap/codex-hud",
   "title": "Capedbitmap/codex-hud \u2014 macOS menu bar app ingesting local Codex session data",
   "relevance": "medium",
   "snippet": "Second reference implementation: a macOS menu bar app that ingests local ~/.codex session data across multiple accounts and models usage state (weekly reset timing, remaining capacity) with typed domain logic \u2014 useful for cross-checking CodexBar's parsing approach to the sessions JSONL and auth files."
  },
  {
   "url": "https://www.sessionwatcher.com/guides/how-to-check-codex-usage",
   "title": "How to Check Codex Usage \u2014 Monitor Limits, Tokens & 5-Hour Window (SessionWatcher)",
   "relevance": "medium",
   "snippet": "Practical community guide confirming the concrete local data sources: `/status` (and /usage) in an active CLI session, and inspecting ~/.codex/sessions/**/rollout-*.jsonl for token_count events; also notes API responses expose x-ratelimit-* headers. Secondary source \u2014 corroborates but should be verified against codex-rs source before relying on it."
  }
 ]
}

## Result 5
{
 "results": [
  {
   "url": "https://github.com/skainguyen1412/antigravity-usage",
   "title": "skainguyen1412/antigravity-usage - CLI tool to track Antigravity model quota and usage",
   "relevance": "high",
   "snippet": "Reference implementation for Antigravity usage tracking on macOS/Linux. Two data sources: 'Local Mode' reads the running Antigravity IDE's local API, with fallback to the Google Cloud Code API for multi-account/offline use; 'Auto Mode' switches between them. Both paths are undocumented/reverse-engineered \u2014 flag as fragile \u2014 but this repo shows exactly what per-model quota data (usage %, resets) is obtainable."
  },
  {
   "url": "https://github.com/tungcorn/antigravity-usage-checker",
   "title": "tungcorn/antigravity-usage-checker - CLI to check Antigravity quota from terminal",
   "relevance": "high",
   "snippet": "Best documentation of the local-endpoint technique: finds the running Windsurf-derived language server process, reads connection parameters (port/token) from its process arguments, then calls a read-only local API on 127.0.0.1 to parse quota data. Notes the local API only updates at milestone values (0/20/40/60/80%) and can serve cached data when Antigravity isn't running \u2014 key reliability/update-frequency detail for a dashboard."
  },
  {
   "url": "https://github.com/steipete/CodexBar/issues/1178",
   "title": "Support Google Antigravity CLI usage limits - CodexBar issue #1178",
   "relevance": "high",
   "snippet": "Directly connects the multi-provider macOS menu-bar reference app (CodexBar, cited in the research brief) to Antigravity: an open issue discussing how/whether Antigravity CLI usage limits can be surfaced. Useful for citing community-verified data-source approaches and current gaps for a Swift menu-bar implementation."
  },
  {
   "url": "https://docs.cline.bot/api/getting-started",
   "title": "Cline API - Getting Started (docs.cline.bot)",
   "relevance": "high",
   "snippet": "Primary source confirming api.cline.bot exists as an official, documented API: API keys are created at app.cline.bot (Settings > API Keys) and used as Bearer auth against endpoints like POST https://api.cline.bot/api/v1/chat/completions. Establishes the official auth mechanism; the docs cover chat/inference endpoints \u2014 a documented public usage/credits-balance endpoint is not evident here, so credits data likely requires the dashboard's internal endpoints."
  },
  {
   "url": "https://deepwiki.com/cline/cline/11.3-credits-and-billing",
   "title": "Credits and Billing | cline/cline - DeepWiki (source-derived)",
   "relevance": "high",
   "snippet": "Source-code-derived walkthrough of how the open-source Cline extension implements credits/billing: the account view fetches credit balance and a Usage History table (Date, Model, Credits Used), refreshing balance/usage per user or organization context. Since cline/cline is open source, this maps to the exact internal api.cline.bot endpoints and auth token storage (VS Code secrets) a native dashboard would need to replicate \u2014 undocumented for third parties, so treat as reverse-engineered."
  },
  {
   "url": "https://blog.google/feed/new-antigravity-rate-limits-pro-ultra-subsribers/",
   "title": "Google AI Pro and Ultra subscribers now have higher rate limits for Google Antigravity",
   "relevance": "medium",
   "snippet": "Official Google statement of Antigravity quota mechanics: Pro/Ultra subscribers get the highest rate limits with quotas refreshing every five hours, while free-plan users moved to a larger weekly-based limit. No official API for reading these quotas is offered \u2014 this is the authoritative description of the limit model a dashboard would display (5-hour window + weekly reset), complementing the reverse-engineered local API tools."
  }
 ]
}

## Result 6
{
 "results": [
  {
   "url": "https://github.com/ryoppippi/ccusage",
   "title": "ryoppippi/ccusage \u2014 CLI that parses local coding-agent JSONL logs into token/cost reports",
   "relevance": "high",
   "snippet": "The canonical reference implementation: reads ~/.claude/projects/**/*.jsonl (one file per session), aggregates tokens by input/output/cache-creation/cache-read per model, and computes estimated cost via LiteLLM pricing with three modes (auto/calculate/display). Fully offline, no API calls or login \u2014 exactly the local-parsing technique a macOS dashboard would replicate. Now also supports Codex, Gemini CLI, Copilot CLI, and others. See docs/guide/cost-modes.md in the repo for the cost logic."
  },
  {
   "url": "https://github.com/anthropics/claude-code/issues/31637",
   "title": "claude-code issue #31637 \u2014 /api/oauth/usage endpoint aggressively rate limits usage monitoring",
   "relevance": "high",
   "snippet": "Documents the undocumented endpoint behind Claude Code's /usage command: https://api.anthropic.com/api/oauth/usage, authenticated with the subscription OAuth token, returning utilization %, reset time, and 5-hour + weekly limit state. Community findings: polling requires a Claude-Code-like User-Agent (safe at ~180s intervals; wrong UA yields persistent 429s). Flag as reverse-engineered/fragile \u2014 but it is the only queryable limits source for Pro/Max users."
  },
  {
   "url": "https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202",
   "title": "Claude-Code-Usage-Monitor issue #202 \u2014 OAuth Usage API as authoritative window state",
   "relevance": "high",
   "snippet": "A leading community monitor tool discussing switching from local JSONL heuristics (guessing the 5-hour window from timestamps) to the Anthropic OAuth usage endpoint for authoritative, cross-device-accurate session/weekly window state. Useful reference implementation showing both approaches and their tradeoffs for a dashboard."
  },
  {
   "url": "https://dev.to/anicca_301094325e/how-to-recover-claude-code-oauth-token-in-30-seconds-1hd",
   "title": "How to Recover Claude Code OAuth Token in 30 Seconds (macOS Keychain)",
   "relevance": "high",
   "snippet": "Confirms the macOS credential location: a generic password Keychain item with service name 'Claude Code-credentials', retrievable via `security find-generic-password -s 'Claude Code-credentials' -w`, returning JSON with accessToken, refreshToken, and expiresAt. Also note the file fallback ~/.claude/.credentials.json used on headless/SSH systems (per related claude-code issues #9403/#37512). A Swift app would need Keychain access consent to read this."
  },
  {
   "url": "https://github.com/anthropics/claude-code/issues/28197",
   "title": "claude-code issue #28197 \u2014 JSONL usage.input_tokens are placeholder values",
   "relevance": "high",
   "snippet": "Primary-source caveat for any JSONL-parsing dashboard: Claude Code's transcript logs can record usage.input_tokens as a streaming placeholder (often 1) instead of the final count, so input tokens can be ~100x off and output tokens ~10x off in some entries \u2014 affecting ccusage and every tool that parses ~/.claude/projects. Corroborated by https://gille.ai/en/blog/claude-code-jsonl-logs-undercount-tokens/. Accuracy claims in the dashboard must account for this."
  },
  {
   "url": "https://code.claude.com/docs/en/authentication",
   "title": "Claude Code official docs \u2014 Authentication",
   "relevance": "medium",
   "snippet": "Official documentation of Claude Code's OAuth flow for Pro/Max subscribers, `claude setup-token` for long-lived tokens, and CLAUDE_CODE_OAUTH_TOKEN env override. Notably contains no documented usage/limits API for consumer plans \u2014 confirming that the org-only Admin/Usage API (platform.claude.com Rate Limits API, launched Apr 2026, explicitly excludes Pro/Max/Team subscribers) does not apply, so subscription users are limited to local JSONL parsing plus the undocumented oauth/usage endpoint."
  }
 ]
}

## Result 7
{
 "claims": [
  {
   "claim": "The Cursor Admin API is scoped to team data (members, usage, spend), not individual accounts \u2014 an individual-plan user building a personal dashboard cannot rely on it; certain endpoints (user spend limits, member removal) are further restricted to Enterprise plans.",
   "quote": "The Admin API lets you programmatically access your team's data, including member information, usage metrics, and spending details.",
   "importance": "central"
  },
  {
   "claim": "Authentication to the Cursor Admin API uses HTTP Basic Authentication with the API key as the username and an empty password (curl form `-u YOUR_API_KEY:`), against base URL https://api.cursor.com.",
   "quote": "The Admin API uses Basic Authentication with your API key as the username.",
   "importance": "central"
  },
  {
   "claim": "The `/teams/daily-usage-data` endpoint returns per-day, per-member coding-activity metrics \u2014 not session/rate-limit data \u2014 with fields such as totalLinesAdded, acceptedLinesAdded, totalTabsShown, totalTabsAccepted, composerRequests, chatRequests, agentRequests, subscriptionIncludedReqs, usageBasedReqs, mostUsedModel, and clientVersion; queried date ranges cannot exceed 30 days.",
   "quote": "totalLinesAdded, totalLinesDeleted, acceptedLinesAdded, acceptedLinesDeleted, totalApplies, totalAccepts, totalRejects, totalTabsShown, totalTabsAccepted, composerRequests, chatRequests, agentRequests, cmdkUsages, subscriptionIncludedReqs, apiKeyReqs, usageBasedReqs, bugbotUsages, mostUsedModel, and clientVersion",
   "importance": "central"
  },
  {
   "claim": "Token-level and cost-level data is available via `/teams/filtered-usage-events` (per-event tokens consumed and model costs in cents) and `/teams/spend` (current billing-cycle spend per member in cents, split into on-demand `spendCents` and total `overallSpendCents`); the per-event `chargedCents` field reconciles with spend totals.",
   "quote": "includes both the model cost and the Cursor Token Rate",
   "importance": "central"
  },
  {
   "claim": "Polling frequency for a dashboard is constrained by documented per-team rate limits: usage events and audit logs are limited to 20 requests per minute per team (other endpoint groups range from 20 to 250 requests per minute).",
   "quote": "20 requests per minute per team",
   "importance": "supporting"
  }
 ],
 "sourceQuality": "primary",
 "publishDate": ""
}

## Result 8
{
 "claims": [
  {
   "claim": "Cursor per-user usage data can be retrieved by calling the same internal endpoints the Cursor web dashboard uses: legacy GET https://cursor.com/api/usage, newer POST https://api2.cursor.sh/.../GetCurrentPeriodUsage, and GET https://cursor.com/api/auth/stripe for subscription/plan metadata.",
   "quote": "legacy `GET https://cursor.com/api/usage`, newer `POST https://api2.cursor.sh/.../GetCurrentPeriodUsage`, plus `GET https://cursor.com/api/auth/stripe` for plan metadata",
   "importance": "central"
  },
  {
   "claim": "Authentication is done without any official API key: the extension reads the access token from Cursor's local SQLite store (key cursorAuth/accessToken in state.vscdb), finds the user ID in local storage files (newer sentry paths first, e.g. sentry/scope_v3.json), and sends them as a session cookie in the format WorkosCursorSessionToken={userId}%3A%3A{accessToken}.",
   "quote": "It reads `cursorAuth/accessToken` from Cursor's `state.vscdb` ... looks for your Cursor user ID in local storage files, with the newer `sentry` paths checked first. ... Cookie: WorkosCursorSessionToken={userId}%3A%3A{accessToken}",
   "importance": "central"
  },
  {
   "claim": "These Cursor usage endpoints are unofficial and reverse-engineered \u2014 the project itself flags them as internal dashboard endpoints that may break at any time, so any macOS dashboard built on them should be treated as fragile.",
   "quote": "Data comes from the same internal endpoints as the Cursor web dashboard. They are unofficial and subject to change.",
   "importance": "central"
  },
  {
   "claim": "The metrics obtainable via this technique include premium requests used vs. limit (legacy accounts, e.g. 120/500), dollar usage vs. included credit cap (newer USD-credit accounts), token usage, plan name/subscription status, an Auto+Composer vs. API usage split, and the next quota reset / cycle renewal date.",
   "quote": "hover card with requests, token usage, and the next reset date ... Included pool...Total / Auto + Composer / API...Renews: cycle end date",
   "importance": "supporting"
  },
  {
   "claim": "Polling these endpoints every 5 minutes (default refreshInterval of 300 seconds, user-configurable) is a workable update frequency that the extension uses in practice.",
   "quote": "Automatic refresh every 5 minutes by default",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-05-07",
 "sourceQuality": "primary"
}

## Result 9
{
 "claims": [
  {
   "claim": "A Cursor usage monitor can obtain the auth token by reading Cursor's local SQLite database (state.vscdb) at ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb on macOS, extracting the 'cursorAuth/accessToken' JWT key \u2014 no user-supplied credentials needed.",
   "quote": "Key extracted: cursorAuth/accessToken (a JWT) ... macOS: ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb ... The token is \"read from disk on each refresh and never stored by the extension\"",
   "importance": "central"
  },
  {
   "claim": "The extension queries the undocumented endpoint GET https://api2.cursor.sh/auth/usage with a Bearer token, which returns per-model request counts and limits, e.g. {\"gpt-4\": {\"numRequests\": 150, \"maxRequestUsage\": 500}, \"startOfMonth\": ...}.",
   "quote": "GET https://api2.cursor.sh/auth/usage with Bearer token authentication - Returns: {\"gpt-4\": {\"numRequests\": 150, \"maxRequestUsage\": 500}, \"startOfMonth\": \"2026-03-01T00:00:00.000Z\"}",
   "importance": "central"
  },
  {
   "claim": "The api2.cursor.sh endpoint is undocumented/reverse-engineered \u2014 it was discovered by probing Cursor's internal API with the extracted token, and Cursor's official cursor.com/api/usage endpoint requires a browser session cookie unavailable to a Node.js extension.",
   "quote": "By probing Cursor's internal API (api2.cursor.sh) with this token, the correct endpoint was found ... Documented but inaccessible: cursor.com/api/usage requires browser session cookie (unavailable to Node.js extension)",
   "importance": "central"
  },
  {
   "claim": "The metrics surfaced are limited to fast/premium request counts (used, remaining, max) plus billing-month start date \u2014 it shows remaining fast requests such as 'Fast requests used: 150 / 500' and 'Remaining: 350', not token-level input/output/cached breakdowns.",
   "quote": "\"\u26a1 Fast requests used: 150 / 500\" ... \"\u2705 Remaining: 350\" ... Start of billing month date",
   "importance": "supporting"
  },
  {
   "claim": "The extension refreshes usage data automatically every 5 minutes in the background, with manual on-demand refresh via clicking the status bar item.",
   "quote": "Auto-refresh: Every 5 minutes in background - Manual refresh: Click status bar item to refresh on-demand",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-03-15 (created; last pushed 2026-04-01)",
 "sourceQuality": "secondary"
}

## Result 10
{
 "claims": [
  {
   "claim": "A per-user Cursor usage endpoint exists at cursor.com: the extension fetches individual usage counts and reset dates from /api/usage?user=USER_ID after resolving the user via /api/auth/me \u2014 these are undocumented dashboard endpoints, not an official public API, so this integration is fragile/reverse-engineered.",
   "quote": "The extension only makes authenticated requests to these Cursor endpoints: `/api/auth/me` - to get your user information; `/api/usage?user=USER_ID` - to get your individual usage data and reset dates; `/api/dashboard/teams` - to get your team list; `/api/dashboard/team` - to get your user ID within teams; `/api/dashboard/get-team-spend` - to get team usage data",
   "importance": "central"
  },
  {
   "claim": "Authentication to these Cursor dashboard endpoints is done with the WorkosCursorSessionToken browser session cookie, which the user must manually copy from cursor.com via browser DevTools and paste into the extension (stored via VS Code SecretStorage) \u2014 i.e., session-cookie auth, no OAuth flow or API key.",
   "quote": "Find `WorkosCursorSessionToken` and copy its value",
   "importance": "central"
  },
  {
   "claim": "As of this repo's writing (mid-2025), Cursor's official API only issues API tokens to team Admin roles, meaning individual 'Team Member' users have no official programmatic way to check their own usage \u2014 which is why community tools resort to the session-cookie/dashboard-endpoint workaround.",
   "quote": "Currently, Cursor's API only provides API tokens to users with 'Admin' roles. This means that if you're a 'Team Member,' there's no official way to programmatically check your usage stats.",
   "importance": "central"
  },
  {
   "claim": "The metrics obtainable via this approach include remaining fast-premium requests (status bar shows e.g. '\u26a1 247'), usage reset dates, and usage-based spend vs. spend limit (e.g. '$1.52/$150.00' from get-team-spend); data is refreshed by polling with a configurable interval defaulting to 30 minutes.",
   "quote": "`cursorUsage.pollMinutes` | `30` | How often to refresh the count (in minutes).",
   "importance": "supporting"
  },
  {
   "claim": "The project is a small, possibly stale reference implementation: created July 1, 2025, last pushed August 3, 2025, 16 stars, MIT-licensed, no published releases \u2014 so its 'fast-premium requests' framing predates Cursor's later move away from request-count quotas and its endpoint list may no longer match current cursor.com behavior.",
   "quote": "Created: July 1, 2025 ... Last Pushed: August 3, 2025 ... Stars: 16 ... Archived: No",
   "importance": "supporting"
  }
 ],
 "publishDate": "2025-07-01 (repo created; last pushed 2025-08-03)",
 "sourceQuality": "primary"
}

## Result 11
{
 "claims": [
  {
   "claim": "cursor-stats authenticates to Cursor's backend by reconstructing a session cookie named WorkosCursorSessionToken, sending it as a Cookie header on requests to cursor.com \u2014 i.e. it reuses the logged-in Cursor session rather than an official API key.",
   "quote": "All requests use: 'Cookie': 'WorkosCursorSessionToken=${token}' where token is extracted from URL-encoded format (e.g., token.split('%3A%3A')[0]).",
   "importance": "central"
  },
  {
   "claim": "It obtains the auth token by reading Cursor's local VS Code SQLite database (state.vscdb) \u2014 on macOS at User/globalStorage/state.vscdb \u2014 running the query SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken', then parsing the JWT's sub claim for the user id and building the token as ${userId}%3A%3A${token}.",
   "quote": "The code executes this SQL query against the database: \"SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'\" ... Constructs the session token as: \"${userId}%3A%3A${token}\"",
   "importance": "central"
  },
  {
   "claim": "The extension pulls usage metrics from undocumented cursor.com dashboard endpoints, including https://cursor.com/api/usage (GPT-4 request counts, maxRequestUsage, numTokens, startOfMonth), plus /api/dashboard/get-monthly-invoice, /api/dashboard/get-hard-limit, and /api/dashboard/get-usage-based-premium-requests.",
   "quote": "https://cursor.com/api/usage | Get current request counts | CursorUsageResponse containing GPT-4 and GPT-4-32k numRequests, maxRequestUsage, numTokens, startOfMonth",
   "importance": "central"
  },
  {
   "claim": "The extension polls for updated stats on a configurable interval that defaults to 60 seconds.",
   "quote": "The refreshInterval configuration defaults to 60 seconds for statistic updates.",
   "importance": "supporting"
  },
  {
   "claim": "The project is no longer maintained \u2014 it was archived (March 8, 2026), with the maintainer citing constant changes in Cursor's pricing policy, signaling the fragility of the reverse-engineered endpoint approach.",
   "quote": "Archived on March 8, 2026; marked \"No more maintained\" due to \"constant changes in Cursor's pricing policy\"",
   "importance": "supporting"
  }
 ],
 "publishDate": "2025-06-06 (v1.1.4 latest release); repo last pushed 2025-09-25; archived 2026-03-08",
 "sourceQuality": "primary"
}

## Result 12
{
 "claims": [
  {
   "claim": "The extension auto-detects the Cursor auth token by reading the local SQLite database state.vscdb (on macOS at ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb) and querying the ItemTable key 'cursorAuth/accessToken', using sql.js (pure-JS SQLite) with a sqlite3 CLI fallback \u2014 no manual login needed.",
   "quote": "macOS: `{homeDir}/Library/Application Support/Cursor/User/globalStorage/state.vscdb` ... The code queries the SQLite database with: \"SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'\" ... Uses sql.js (pure JavaScript SQLite implementation) ... Falls back to `sqlite3` command if available.",
   "importance": "central"
  },
  {
   "claim": "The tool fetches usage data from undocumented cursor.com endpoints: GET /api/usage?user={userId}, GET /api/auth/stripe (billing/plan type), POST /api/dashboard/get-filtered-usage-events (per-request events), plus team endpoints POST /api/dashboard/teams and POST /api/dashboard/get-team-spend \u2014 all reverse-engineered from the Cursor web dashboard, not an official API.",
   "quote": "Usage endpoint: `GET /usage?user={userId}` ... Team info endpoint: `POST /dashboard/teams` ... Team spend endpoint: `POST /dashboard/get-team-spend` ... Billing endpoint: `GET /auth/stripe` ... Usage events endpoint: `POST /dashboard/get-filtered-usage-events`",
   "importance": "central"
  },
  {
   "claim": "Authentication to these endpoints is done by sending the session token as a browser cookie header 'Cookie: WorkosCursorSessionToken={value}', where the token has the format user_XXXXX::JWT and the '::' separator must be URL-encoded as %3A%3A; the same value can be manually copied from the WorkosCursorSessionToken cookie on cursor.com/settings.",
   "quote": "The authentication header uses: `'Cookie': 'WorkosCursorSessionToken={cookieValue}'` ... The cookie value is URL-encoded with `::` becoming `%3A%3A` if needed. ... \"Find `WorkosCursorSessionToken` and copy its value\" ... \"Make sure to copy the complete token value (including `user_XXXXX::` prefix)\"",
   "importance": "central"
  },
  {
   "claim": "The /api/usage response yields per-model fields numRequests and maxRequestUsage plus startOfMonth for the billing cycle (end computed as startOfMonth + 1 month), and usage events carry per-request model, token counts, cost, and millisecond timestamps \u2014 enough to show requests used/limit, today's spend, and cycle reset date.",
   "quote": "startOfMonth (string, converted to Date object) ... endOfMonth (calculated as startOfMonth + 1 month) ... maxRequestUsage (premium request limits per model) ... numRequests (usage count per model) ... Activity history displays \"model, tokens, and cost.\"",
   "importance": "supporting"
  },
  {
   "claim": "The tool polls with a configurable refresh interval defaulting to 60 seconds (minimum 60), and its README asserts that as of early 2026 all Cursor plans (Free, Pro, Business, Team) use token/usage-based billing rather than the old 500-premium-request quota.",
   "quote": "\"Refresh interval in seconds (minimum 60)\" with a default of 60 seconds, configurable via `cursorUsage.refreshInterval` ... \"All Cursor plans (Free, Pro, Business) now use **usage-based billing** (token-based).\"",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-01-22 (repo created; v0.1.3 released 2026-01-22; last push 2026-03-26)",
 "sourceQuality": "primary"
}

## Result 13
{
 "claims": [
  {
   "claim": "CodexBar retrieves OpenAI Codex usage by calling the undocumented ChatGPT backend endpoint GET https://chatgpt.com/backend-api/wham/usage with a Bearer token read from ~/.codex/auth.json (or $CODEX_HOME/auth.json), and a companion endpoint /backend-api/wham/rate-limit-reset-credits for reset credits.",
   "quote": "GET https://chatgpt.com/backend-api/wham/usage ... Authorization: Bearer <token> ... GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits ... Reads OAuth tokens from ~/.codex/auth.json (or $CODEX_HOME/auth.json)",
   "importance": "central"
  },
  {
   "claim": "For Claude Code, CodexBar's preferred method calls Anthropic's OAuth usage endpoint GET https://api.anthropic.com/api/oauth/usage with header 'anthropic-beta: oauth-2025-04-20', using credentials from ~/.claude/.credentials.json or the Keychain entry labeled 'Claude Code-credentials'; the response maps to five_hour session, seven_day weekly, and seven_day_sonnet/seven_day_opus model windows plus extra_usage monthly spend.",
   "quote": "GET https://api.anthropic.com/api/oauth/usage ... Authorization: Bearer <access_token> ... anthropic-beta: oauth-2025-04-20 ... ~/.claude/.credentials.json ... fallback to the Claude CLI Keychain entry labeled Claude Code-credentials ... session window (five_hour), weekly window (seven_day), model-specific windows (seven_day_sonnet / seven_day_opus), and extra_usage \u2192 Extra usage cost (monthly spend/limit)",
   "importance": "central"
  },
  {
   "claim": "CodexBar offers multiple fallback data sources for Claude usage beyond the OAuth API: a cookie-based web API (claude.ai/api/organizations/{orgId}/usage using the sessionKey cookie from Safari/Chrome/Firefox), a CLI PTY method that runs `claude` and parses /usage and /status output, local JSONL cost scanning of message.usage entries, and the Anthropic Admin API (cost_report / usage_report).",
   "quote": "GET https://claude.ai/api/organizations/{orgId}/usage \u2192 session/weekly/opus percentages ... CodexBar runs claude in a pseudo-terminal session, sending /usage and /status commands ... scans JSONL files in Claude's project directories for type: \"assistant\" and message.usage entries ... /v1/organizations/cost_report ... /v1/organizations/usage_report/messages",
   "importance": "central"
  },
  {
   "claim": "CodexBar is a native macOS menu-bar app written almost entirely in Swift (98.6%) with SwiftUI and WidgetKit widgets, MIT-licensed by Peter Steinberger, at v0.40.0 (Jul 5, 2026) with ~16.3k stars, supporting 57+ providers including Codex, Claude, Cursor, Gemini, Copilot, and Antigravity/Windsurf.",
   "quote": "Written in Swift (98.6%) ... WidgetKit widgets for supported providers ... MIT \u2022 Peter Steinberger ... v0.40.0 (Jul 5, 2026) ... Stars: 16.3k ... 57+ providers listed, including: Codex, OpenAI, Claude, Cursor, Gemini, Copilot",
   "importance": "supporting"
  },
  {
   "claim": "CodexBar avoids requiring a login by reusing existing provider sessions (OAuth tokens, device flow, API keys, browser cookies, local files) and reads only a known set of file locations rather than crawling the filesystem, with configurable refresh presets of manual/1m/2m/5m/15m.",
   "quote": "Privacy-first. Reuses existing provider sessions \u2014 OAuth, device flow, API keys, browser cookies, local files \u2014 so no passwords are stored ... it reads a small set of known locations ... Refresh cadence presets (manual, 1m, 2m, 5m, 15m)",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-07-05",
 "sourceQuality": "primary"
}

## Result 14
{
 "claims": [
  {
   "claim": "CCSeva obtains Claude Code usage data by parsing local JSONL transcripts under ~/.claude, specifically reading the glob ~/.claude/projects/**/*.jsonl with incremental scanning and deduplication \u2014 confirming that per-session token/cost data for Claude Code can be derived entirely from local files with no API or authentication.",
   "quote": "reads `~/.claude/projects/**/*.jsonl` directly with incremental scanning and dedup",
   "importance": "central"
  },
  {
   "claim": "CCSeva additionally queries an undocumented Claude Code OAuth usage endpoint to get server-side ('server-truth') 5-hour session and weekly limit utilization, which captures usage from other devices that local file parsing would miss. This is a reverse-engineered/undocumented endpoint (the same one Claude Code's own /usage relies on), so it should be flagged as fragile.",
   "quote": "reads Claude Code's OAuth usage endpoint for real 5-hour and weekly utilization (including usage from other devices)",
   "importance": "central"
  },
  {
   "claim": "CCSeva handles the fragility of the undocumented OAuth endpoint by falling back to locally estimated usage when the endpoint is unavailable \u2014 a concrete reliability pattern for a dashboard that mixes server-truth and local-file data sources.",
   "quote": "automatic local-estimation fallback when the endpoint is unavailable",
   "importance": "supporting"
  },
  {
   "claim": "CCSeva was originally an Electron/React app that delegated Claude Code data extraction to the ccusage npm package (github.com/ryoppippi/ccusage), before being rewritten as a native Swift 6.1 + SwiftUI + AppKit (NSStatusItem/NSPopover) menu bar app with zero runtime dependencies \u2014 establishing both ccusage as a reference parser and precedent for a native Swift implementation of ~/.claude JSONL parsing.",
   "quote": "built with Electron 36, React 19, TypeScript 5, Tailwind CSS 3, and Radix UI, using the [`ccusage`](https://github.com/ryoppippi/ccusage) package",
   "importance": "supporting"
  },
  {
   "claim": "CCSeva's update model is file-change-driven with a periodic fallback poll (no fixed interval documented), and the project explicitly disclaims official status ('This is an unofficial tool for tracking Claude Code usage'), requiring an existing Claude Code installation; the app displays 5-hour block tokens, burn rate, reset countdown, weekly token/cost rollups, and per-model/per-project cost breakdowns.",
   "quote": "refreshes on file changes (with a periodic fallback poll)",
   "importance": "supporting"
  }
 ],
 "sourceQuality": "primary",
 "publishDate": "2025-07-22 (latest release v1.3.0; repo actively maintained, 797 stars, MIT license)"
}

## Result 15
{
 "claims": [
  {
   "claim": "Tokcat obtains historical AI usage data by parsing local on-device session logs for nine coding clients \u2014 Claude Code, Codex CLI, Cursor IDE, OpenCode, Gemini CLI, Copilot CLI, Amp, Droid, and Hermes \u2014 rather than provider APIs, confirming local log files are a viable primary data source including for Cursor.",
   "quote": "Tokcat reads Claude Code, Codex CLI, Cursor IDE, OpenCode, Gemini CLI, Copilot CLI, Amp, Droid, and Hermes logs. ... Usage history comes from local session logs read on-device.",
   "importance": "central"
  },
  {
   "claim": "For real-time quota/limit data, Tokcat reads the user's existing locally-stored Codex and Claude Code OAuth credentials and calls OpenAI's and Anthropic's own usage endpoints to fetch quota windows \u2014 confirming such usage endpoints exist for both providers and are accessible with the CLI OAuth tokens (an undocumented/reverse-engineered technique, since these endpoints are not public APIs).",
   "quote": "For agent-limit cards, Tokcat reads existing Codex and Claude OAuth credentials and asks those vendors' usage endpoints for quota windows.",
   "importance": "central"
  },
  {
   "claim": "The Codex and Claude quota data retrievable this way includes session-window limits, weekly limits, per-model limits, reset times, and remaining amounts \u2014 matching the metrics the research question asks about (session usage/limit/reset and weekly usage/limit/reset).",
   "quote": "Agent limits: Codex and Claude OAuth quota cards show session, weekly, model, reset, and remaining-limit windows",
   "importance": "central"
  },
  {
   "claim": "Authentication is delegated entirely to the vendors' CLI login flows \u2014 expired credentials are refreshed by re-running `codex login` or `claude`, meaning a third-party monitor need not implement its own OAuth flow.",
   "quote": "Run `codex login` or `claude` to refresh those credentials",
   "importance": "supporting"
  },
  {
   "claim": "Live/near-real-time activity is achieved by tailing JSONL session log files as they grow, confirming the supported clients' session logs are JSONL-format and can be watched for incremental updates; Tokcat itself is built with Tauri 2 (Rust + React), not Swift/SwiftUI.",
   "quote": "a JSONL tailer tracks recent growth in supported session logs ... Built with Tauri 2 (Rust shell + React/Vite frontend)",
   "importance": "supporting"
  }
 ],
 "sourceQuality": "primary",
 "publishDate": "2026-07-05 (latest release v0.1.33)"
}

## Result 16
{
 "claims": [
  {
   "claim": "As of June 2025, Cursor exposes no public API for individual-account cost/usage monitoring, so VibeMeter obtains Cursor spend data by reverse-engineering the cursor.com web dashboard \u2014 extracting session cookies and calling internal, undocumented endpoints. This data source is fragile/reverse-engineered by definition and could break if Cursor changes its web interface.",
   "quote": "Since Cursor lacks a public API, we reverse-engineered their web interface, extracted cookies, and called internal endpoints.",
   "importance": "central"
  },
  {
   "claim": "Cursor's internal usage/cost endpoints differ between enterprise (team) accounts and individual accounts, meaning any dashboard integration must implement and maintain two distinct endpoint paths depending on account type.",
   "quote": "Cursor has no public API for cost control, and it was somewhat messy because I have an enterprise account while many people have individual accounts, and the API endpoints are quite different.",
   "importance": "central"
  },
  {
   "claim": "VibeMeter's reference polling strategy against Cursor's undocumented endpoints is a 5-minute default refresh interval with exponential backoff on errors \u2014 a concrete update-frequency/reliability data point for a similar macOS dashboard.",
   "quote": "The BackgroundDataProcessor refreshes data every 5 minutes by default, but backs off exponentially if errors occur.",
   "importance": "supporting"
  },
  {
   "claim": "VibeMeter is an open-source (MIT-licensed) native macOS menu-bar app written in Swift 6/SwiftUI (repo: github.com/steipete/VibeMeter) whose codebase uses a protocol-based multi-provider abstraction (MultiProviderDataOrchestrator), making it a directly reusable reference implementation for a Swift/SwiftUI multi-provider AI-usage dashboard.",
   "quote": "The MultiProviderDataOrchestrator and protocol-based design make adding OpenAI or Anthropic straightforward when the time comes.",
   "importance": "supporting"
  },
  {
   "claim": "At publication (June 4, 2025), VibeMeter supported only Cursor; OpenAI and Anthropic support was architected for but deliberately not shipped, so VibeMeter cannot be cited as an existing working example of Anthropic/OpenAI usage tracking at that date.",
   "quote": "But I knew if I started adding providers, I'd never ship. So I built the architecture to support it but forced myself to ship with just Cursor. This is definitely coming in a future update.",
   "importance": "supporting"
  }
 ],
 "publishDate": "2025-06-04",
 "sourceQuality": "blog"
}

## Result 17
{
 "claims": [
  {
   "claim": "Codex CLI obtains rate-limit/usage data from HTTP response headers on API responses \u2014 specifically x-codex-primary-used-percent and x-codex-secondary-used-percent \u2014 parsed in the open-source file codex-rs/codex-api/src/rate_limits.rs into a RateLimitSnapshot. This identifies the underlying data source a dashboard could tap (response headers, not a standalone usage endpoint); verifiable against the openai/codex repo source.",
   "quote": "`codex-rs/codex-api/src/rate_limits.rs` parses `x-codex-primary-used-percent`, `x-codex-secondary-used-percent`",
   "importance": "central"
  },
  {
   "claim": "Codex's rate_limits payload exposes two windows matching ChatGPT-plan limits: a 'primary' ~5-hour window (window_minutes: 299) and a 'secondary' ~weekly window (window_minutes: 10079), each with used_percent and resets_in_seconds \u2014 i.e., current-session usage percent and reset time, plus weekly usage percent and reset time, are available (observed in VS Code extension mode on a ChatGPT Team plan, Codex v0.114.0).",
   "quote": "\"rate_limits\": { \"primary\": {\"used_percent\": 0.0, \"window_minutes\": 299, \"resets_in_seconds\": 17940}, \"secondary\": {\"used_percent\": 6.0, \"window_minutes\": 10079, \"resets_in_seconds\": 275281} }",
   "importance": "central"
  },
  {
   "claim": "In non-interactive `codex exec` mode (as of Codex CLI v0.114.0), the rate_limits field is always null in both the rollout/session JSONL files and TokenCount events \u2014 so a dashboard parsing ~/.codex session JSONL from exec-mode runs cannot get usage percentages from those files, even though the handler code for emitting them exists (event_processor_with_jsonl_output.rs).",
   "quote": "`codex exec` mode always yields `rate_limits: null` in rollout JSONL and in `TokenCount` events",
   "importance": "central"
  },
  {
   "claim": "Codex session JSONL token_count events do carry cumulative token usage split by input and output tokens (total_token_usage with input_tokens and output_tokens), so token accounting is locally parseable from JSONL even when rate_limits is null.",
   "quote": "\"payload\": { \"type\": \"token_count\", \"info\": {\"total_token_usage\": {\"input_tokens\": 12065, \"output_tokens\": 3253}}, \"rate_limits\": null }",
   "importance": "supporting"
  },
  {
   "claim": "As of this issue (Codex CLI v0.114.0, March 2026), no `codex usage` subcommand or --show-rate-limits flag exists for exposing rate-limit data outside the interactive TUI/IDE flow \u2014 the issue author requests one as a feature, confirming a monitoring tool must rely on interactive-mode data or reverse-engineered headers instead of an official CLI usage command.",
   "quote": "add an alternative mechanism (e.g., a `--show-rate-limits` flag or a `codex usage` subcommand)",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-03-15",
 "sourceQuality": "forum"
}

## Result 18
{
 "claims": [
  {
   "claim": "VibeMeter obtains Cursor usage/spending data from undocumented cursor.com dashboard endpoints \u2014 GET /api/auth/me (user info), POST /api/dashboard/teams (team info), POST /api/dashboard/get-monthly-invoice with body {\"month\": Int, \"year\": Int, \"teamId\": Int?, \"includeUsageEvents\": Bool} (spend), and GET /api/usage?user={userId} (per-model usage) \u2014 authenticated via a session cookie rather than any official API key.",
   "quote": "public static let apiBaseURL = URL(string: \"https://www.cursor.com/api\")! ... /// Monthly invoice endpoint - Fetches spending data for a specific month. /// - Method: POST /// - Body: `{\"month\": Int, \"year\": Int, \"teamId\": Int?, \"includeUsageEvents\": Bool}` ... public static let monthlyInvoice = \"dashboard/get-monthly-invoice\" ... /// Cookie name for the authentication token. /// - Note: Cursor uses cookie-based authentication instead of Bearer tokens. public static let sessionCookieName = \"WorkosCursorSessionToken\"",
   "importance": "central"
  },
  {
   "claim": "For Claude (Claude Code) tracking, VibeMeter uses no network API at all: it parses local JSONL transcripts under ~/.claude/projects, gaining sandbox access via a security-scoped bookmark to the user's home directory granted through an NSOpenPanel.",
   "quote": "Unlike other providers, ClaudeProvider reads local log files instead of using network APIs. ... private let logDirectoryName = \".claude/projects\" ... \"Please select your home directory to grant VibeMeter access to the ~/.claude folder for reading usage data.\"",
   "importance": "central"
  },
  {
   "claim": "VibeMeter computes Claude's 5-hour session window usage entirely client-side from the local logs, exposing it as a 0-100% gauge (percentage used plus token count), with a 5-minute cache validity on parsed daily usage \u2014 demonstrating that session-window metrics can be reconstructed without any Anthropic endpoint.",
   "quote": "// Use real-time window usage for accurate gauge updates\n        let fiveHourWindow = await logManager.getCurrentWindowUsage() ... return ProviderUsageData(\n            currentRequests: percentageAsInt, // Pass percentage (0-100) for gauge\n            totalRequests: fiveHourWindow.tokensUsed, // Keep actual token count for display ... private let cacheValidityDuration: TimeInterval = 300 // 5 minutes",
   "importance": "central"
  },
  {
   "claim": "VibeMeter is a Swift 6 / SwiftUI menu-bar app requiring macOS 15.0+ that refreshes spending data every 5 minutes, authenticates via the provider's own web login (WebView) without storing passwords, and keeps sensitive tokens in the macOS Keychain \u2014 a directly relevant reference architecture for the planned dashboard.",
   "quote": "\"Updates spending data every 5 minutes\" ... \"Built with Swift 6, optimized for performance\" ... \"macOS 15.0 or later (Sequoia)\" ... \"Login credentials never stored, uses secure web authentication\" and \"Encrypted storage - Sensitive data protected using macOS Keychain\"",
   "importance": "supporting"
  },
  {
   "claim": "VibeMeter is deprecated and its repository was archived (read-only) on May 3, 2026, with steipete/CodexBar named as the successor project \u2014 the last release was v1.1.0 on June 10, 2025 \u2014 so its Cursor endpoint details are a historical reference implementation and CodexBar is the maintained codebase to study.",
   "quote": "\"This project is deprecated. Successor: CodexBar.\" ... The repository was \"archived by the owner on May 3, 2026\" and is \"now read-only.\" Latest release: \"VibeMeter 1.1.0 Latest Jun 10, 2025\"",
   "importance": "central"
  }
 ],
 "publishDate": "2025-06-10 (last release v1.1.0); repository archived 2026-05-03",
 "sourceQuality": "primary"
}

## Result 19
{
 "claims": [
  {
   "claim": "Codex CLI's TokenCount event (recorded as token_count entries in session JSONL rollouts) serves double duty: it carries both real token-usage updates and rebroadcasts of the latest rate-limit snapshot, meaning rate-limit window data is embedded in the same event stream as token counts.",
   "quote": "`EventMsg::TokenCount` currently serves two different purposes: 1. reporting a real token-usage update 2. rebroadcasting the latest rate-limit snapshot",
   "importance": "central"
  },
  {
   "claim": "When only rate limits change, the Codex CLI emits a new TokenCount event that repeats the previous nonzero last_token_usage with an unchanged total_token_usage, so a parser that treats last_token_usage as a per-event incremental delta will double-count usage from session JSONL files.",
   "quote": "When only rate limits change, Codex emits a new `TokenCount` event with unchanged `total_token_usage` and the previous nonzero `last_token_usage`.",
   "importance": "central"
  },
  {
   "claim": "Existing community usage-accounting tools that parse Codex session JSONL rollouts \u2014 specifically slopmeter and @ccusage/codex \u2014 over-reported token usage on the author's real session logs because of this re-emission behavior, so a macOS dashboard must sum from total_token_usage snapshots (or dedupe) rather than summing last_token_usage per event.",
   "quote": "This affects tools that parse session JSONL rollouts for usage accounting. A reasonable implementation is to treat each `token_count` event as a new usage snapshot and `last_token_usage` as the incremental usage for that event.",
   "importance": "central"
  },
  {
   "claim": "The Codex codebase contains an internal comment saying rate-limit handling should defer emission to avoid duplicate TokenCount events, but the implementation immediately calls sess.update_rate_limits and emits anyway \u2014 a code/comment mismatch indicating the duplicate-emission behavior is unintentional-looking but real.",
   "quote": "The comment says rate-limit handling should defer sending 'to avoid duplicate `TokenCount` events', but the implementation immediately calls `sess.update_rate_limits(&turn_context, snapshot).await`",
   "importance": "supporting"
  },
  {
   "claim": "OpenAI closed this issue as 'not planned' (status as of fetch on 2026-07-05), so the ambiguous TokenCount/last_token_usage re-emission behavior should be assumed to persist in current Codex CLI versions and any JSONL parser must defensively handle it.",
   "quote": "Status: Closed as not planned",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-03-12",
 "sourceQuality": "forum"
}

## Result 20
{
 "claims": [
  {
   "claim": "ClaudeBar obtains Claude Code session and weekly quota data by calling the undocumented Anthropic OAuth usage endpoint https://api.anthropic.com/api/oauth/usage with a Bearer token and the 'anthropic-beta: oauth-2025-04-20' header, parsing five_hour.utilization/resets_at, seven_day.utilization/resets_at, model-specific seven_day_sonnet/seven_day_opus fields, and extra_usage credits in cents. This endpoint is not in Anthropic's public docs and should be treated as reverse-engineered/fragile.",
   "quote": "Usage endpoint: \"https://api.anthropic.com/api/oauth/usage\" (GET) ... Beta header: \"anthropic-beta\": \"oauth-2025-04-20\" ... five_hour.utilization and five_hour.resets_at (session quota) ... seven_day.utilization and seven_day.resets_at (weekly quota) ... seven_day_sonnet and seven_day_opus (model-specific limits)",
   "importance": "central"
  },
  {
   "claim": "ClaudeBar obtains OpenAI Codex rate-limit/usage data by calling the undocumented ChatGPT backend endpoint https://chatgpt.com/backend-api/wham/usage, authenticating with the OAuth access token from ~/.codex/auth.json plus a ChatGPT-Account-Id header, and parsing primary_window/secondary_window used_percent, reset_at/reset_after_seconds, plan_type (PLUS/PRO/FREE), and credits balance (also exposed via x-codex-*-used-percent and x-codex-credits-balance response headers).",
   "quote": "Usage endpoint: \"https://chatgpt.com/backend-api/wham/usage\" ... Authentication uses OAuth credentials stored in ~/.codex/auth.json ... Rate limits: primary_window and secondary_window containing used_percent ... Reset timing: reset_at (timestamp) or reset_after_seconds ... Headers: x-codex-primary-used-percent, x-codex-secondary-used-percent, x-codex-credits-balance ... Plan type: plan_type field identifying tiers (PLUS, PRO, FREE)",
   "importance": "central"
  },
  {
   "claim": "ClaudeBar reads provider credentials from local CLI credential stores and refreshes them itself: Claude credentials come from ~/.claude/.credentials.json or the macOS Keychain and are refreshed via POST to https://platform.claude.com/v1/oauth/token using the Claude Code CLI client ID 9d1c250a-e61b-44d9-88ed-5944d1962f5e; Codex tokens are refreshed via https://auth.openai.com/oauth/token using client_id app_EMoamEEZ73f0CkXaXp7hrann when older than 8 days.",
   "quote": "Primary: ~/.claude/.credentials.json file. Secondary: Keychain storage ... Token refresh endpoint: \"https://platform.claude.com/v1/oauth/token\" (POST) ... Client ID: \"9d1c250a-e61b-44d9-88ed-5944d1962f5e\" (Claude Code CLI) ... Uses client_id = \"app_EMoamEEZ73f0CkXaXp7hrann\" with refresh tokens via POST to the token endpoint [auth.openai.com/oauth/token]. Automatically refreshes tokens when lastRefresh exceeds 8 days",
   "importance": "central"
  },
  {
   "claim": "ClaudeBar is a working multi-provider reference implementation covering at least Claude, Codex, Gemini, GitHub Copilot, Antigravity, Z.ai, Kimi, Kiro, Amp, and OpenCode Go (with Cursor, Bedrock, Mistral, MiniMax, and Alibaba provider modules also present in the source tree), displaying session, weekly, and model-specific usage percentages; Antigravity is auto-detected when running locally rather than queried via a documented API, and OpenCode usage is read from a local SQLite DB.",
   "quote": "Monitor Claude, Codex, Gemini, GitHub Copilot, Antigravity, Z.ai, Kimi, Kiro, Amp, and OpenCode Go quotas ... View Session, Weekly, and Model-specific usage percentages ... Antigravity: \"Auto-detected when running locally\" ... OpenCode: \"Tracks OpenCode Go usage windows (5hr/$12, weekly/$30, monthly/$60) via local SQLite DB\"",
   "importance": "central"
  },
  {
   "claim": "A native Swift/SwiftUI macOS menu-bar dashboard for these providers is feasible and actively maintained: ClaudeBar targets macOS 15+ with Swift 6.2+, ships code-signed/notarized under the MIT license, has ~1.3k GitHub stars, released v0.4.70 on July 2, 2026, and polls quotas at user-configurable intervals with local JSONL parsing (SessionJSONLParser.swift, ClaudeDailyUsageAnalyzer.swift, ModelPricing.swift) for cost estimation alongside the API probes.",
   "quote": "macOS: 15+ ... Swift: 6.2+ ... License: MIT ... Stars: 1.3k ... Latest Release: v0.4.70 (July 2, 2026) ... \"Automatically updates quotas at configurable intervals\"",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-07-02 (latest release v0.4.70; repo created 2025-12-20)",
 "sourceQuality": "primary"
}

## Result 21
{
 "claims": [
  {
   "claim": "Antigravity usage quota can be read programmatically from a local API server that the Antigravity/Windsurf language server exposes on 127.0.0.1 \u2014 no external Google endpoint is required. This is an undocumented, reverse-engineered local API (not documented by Google), so it should be treated as fragile.",
   "quote": "Local only: \"It connects to the local Antigravity server on `127.0.0.1`\" ... \"reads quota information from the local Antigravity/Windsurf API and prints it in a terminal-friendly format.\"",
   "importance": "central"
  },
  {
   "claim": "The connection details for Antigravity's local quota API are discovered by finding the running Windsurf language server process and parsing its command-line arguments; no stored OAuth token, cookie, or config-file credential is needed, but Antigravity must be running for the data to be available.",
   "quote": "1. \"Finds the running Windsurf language server process\" 2. \"Reads the local connection parameters from process arguments\" 3. \"Calls the Antigravity local API on `127.0.0.1`\" 4. \"Parses quota data and displays it in the terminal\"",
   "importance": "central"
  },
  {
   "claim": "Antigravity's local API has coarse update granularity: usage statistics typically only refresh at milestone percentages (0%, 20%, 40%, 60%, 80%), which limits the real-time precision any monitoring dashboard can achieve for this provider.",
   "quote": "\"The Antigravity local API usually updates usage statistics at milestone values such as 0%, 20%, 40%, 60%, and 80%.\"",
   "importance": "central"
  },
  {
   "claim": "Antigravity quota is organized into pools, some of which are shared across models \u2014 the tool explicitly deduplicates shared quota pools when computing totals, implying the local API returns multiple per-model quota entries that can point at the same underlying pool.",
   "quote": "\"Smart total calculation\": Detects and deduplicates shared quota pools",
   "importance": "supporting"
  },
  {
   "claim": "The tool is a Go CLI (installable via curl script on macOS/Linux, supporting macOS Intel/ARM) that offers machine-readable output via `agusage --json`, making it a usable reference implementation or even a subprocess data source for a native macOS dashboard; it is read-only and makes no external network calls.",
   "quote": "agusage --json       # JSON output ... \"No external runtime network calls: The application does not send usage data to external servers.\" ... Read-only: \"It reads local process information and quota data; it does not modify your Antigravity setup\"",
   "importance": "supporting"
  }
 ],
 "sourceQuality": "primary",
 "publishDate": "Latest release v2.2.4 dated 2026-02-23 per repo (initial publish date not shown on page)"
}

## Result 22
{
 "claims": [
  {
   "claim": "As of CodexBar main/v0.29.1 (May 2026), CodexBar already tracks Google Antigravity usage via two data sources: probing the locally running Antigravity language server for quota/model windows, and a Google OAuth flow that calls the (undocumented, reverse-engineered) Cloud Code / Code Assist quota APIs and maps per-model quotas into named rate windows in the menu bar.",
   "quote": "Current `main` already has Antigravity as a separate provider with two usage sources: Local IDE API, which probes the running Antigravity language server for quota/model windows. Google OAuth, which calls the Cloud Code / Code Assist quota APIs and maps all model quotas into the menu via named extra rate windows.",
   "importance": "central"
  },
  {
   "claim": "The Antigravity CLI (`agy`) fetches quota from the same undocumented Google Cloud Code backend endpoints (https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist and v1internal:fetchAvailableModels) that CodexBar's existing Antigravity OAuth source already calls, so the CLI exposes no quota data beyond that reverse-engineered API; these are internal Google endpoints and fragile.",
   "quote": "From the CLI logs, `agy` calls: https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels ... These are the **same `v1internal` Cloud Code endpoints** `AntigravityRemoteUsageFetcher` already calls \u2014 so the CLI exposes **no quota data the existing Antigravity OAuth source can't already see**.",
   "importance": "central"
  },
  {
   "claim": "A running `agy` process (tested v1.0.5 on macOS Apple Silicon) serves a local loopback Connect-RPC endpoint POST /exa.language_server_pb.LanguageServerService/GetUserStatus that returns per-model quota (quotaInfo.remainingFraction for 8 models including Claude and GPT-OSS) plus userTier.availableCredits, and \u2014 unlike the IDE's language server \u2014 requires no X-Codeium-Csrf-Token header.",
   "quote": "curl -sk -X POST \"https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/GetUserStatus\" ... # 200 OK -> userStatus.cascadeModelConfigData.clientModelConfigs (8 models incl. Claude / GPT-OSS, each with quotaInfo.remainingFraction) + userTier.availableCredits (GOOGLE_ONE_AI)",
   "importance": "central"
  },
  {
   "claim": "On macOS, Antigravity CLI stores its OAuth credential in the macOS Keychain under service name 'antigravity' (falling back to a plaintext file ~/.gemini/antigravity-cli/antigravity-oauth-token only when no OS keyring is available), keeps all other local state under ~/.gemini/antigravity-cli/ (settings.json, history.jsonl, conversations/*.pb, cache/, log/cli-*.log), and does NOT reuse the legacy Gemini CLI's ~/.gemini/oauth_creds.json.",
   "quote": "**Normal macOS:** stored in the **macOS Keychain**, service name **`antigravity`** ... No credential file is written under `~/.gemini/`. **Fallback (no OS keyring ...):** a plaintext file `~/.gemini/antigravity-cli/antigravity-oauth-token` ... It does **not** reuse `~/.gemini/oauth_creds.json` (removing that file had no effect on `agy`).",
   "importance": "central"
  },
  {
   "claim": "The Antigravity CLI (v1.0.3) exposes no non-interactive usage or quota command \u2014 its only top-level subcommands are changelog/help/install/plugin/update, with login and quota handled inside the interactive TUI \u2014 so a dashboard cannot get usage by shelling out to the CLI; additionally, Google is ending Gemini CLI / Gemini Code Assist for individuals on June 18, 2026, migrating users to Antigravity CLI.",
   "quote": "Top-level subcommands are only `changelog / help / install / plugin / update` \u2014 there is **no** `usage`/`quota`/`login`/`auth` subcommand. Login and quota are handled inside the interactive TUI; quota itself is fetched internally ... not exposed as a non-interactive command.",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-05-27 (issue opened; key technical comments 2026-05-29 to 2026-06-04; closed as completed 2026-06-07)",
 "sourceQuality": "primary"
}

## Result 23
{
 "claims": [
  {
   "claim": "An undocumented endpoint GET https://api.anthropic.com/api/oauth/usage exists and returns Claude usage data when called with a valid Claude Code OAuth Bearer token plus the header 'anthropic-beta: oauth-2025-04-20'.",
   "quote": "Call `GET https://api.anthropic.com/api/oauth/usage` with a valid `Bearer` token and `anthropic-beta: oauth-2025-04-20`",
   "importance": "central"
  },
  {
   "claim": "Claude Code itself uses this same /api/oauth/usage endpoint to display usage in its statusline, so third-party monitoring tools calling it are replicating Claude Code's own internal data source.",
   "quote": "Claude Code itself exposes usage in its statusline via this endpoint \u2014 users building on that same API get frozen/stale data and cannot reliably monitor their quota.",
   "importance": "central"
  },
  {
   "claim": "The /api/oauth/usage endpoint aggressively rate limits external polling: even 30\u201360 second intervals trigger HTTP 429 rate_limit_error responses, making it unreliable as an update source for a dashboard.",
   "quote": "The `https://api.anthropic.com/api/oauth/usage` endpoint returns `rate_limit_error` (HTTP 429) so aggressively that it makes it effectively impossible to poll usage data \u2014 even at very low intervals.",
   "importance": "central"
  },
  {
   "claim": "Once rate limited, the endpoint returns 429 with no Retry-After header and the block persists indefinitely (observed 30+ minutes), so exponential backoff does not recover; the reporter's tool got stuck at its 300s backoff cap.",
   "quote": "Once stuck at the 300s cap, the endpoint continues returning 429 for the entire session (observed for 30+ minutes continuously)",
   "importance": "supporting"
  },
  {
   "claim": "Claude Code OAuth credentials on the reporter's macOS system were read from the file ~/.claude/.credentials.json (rather than exclusively from the macOS Keychain), and the issue was closed as 'not planned'/'invalid' with no maintainer response, signaling Anthropic does not officially support third-party polling of this endpoint.",
   "quote": "Authenticate via OAuth (standard Claude Code credentials in `~/.claude/.credentials.json`) ... Status: Closed as not planned ... Labels: `invalid`, `stale`",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-03-06",
 "sourceQuality": "forum"
}

## Result 24
{
 "claims": [
  {
   "claim": "Cline exposes a documented public API backed by api.cline.bot, with an OpenAI-compatible chat completions endpoint at https://api.cline.bot/api/v1/chat/completions \u2014 confirming api.cline.bot is the API host behind the Cline platform.",
   "quote": "https://api.cline.bot/api/v1/chat/completions",
   "importance": "central"
  },
  {
   "claim": "Authentication to the Cline API uses API keys created manually in the app.cline.bot dashboard (Settings > API Keys) and sent as bearer tokens in the Authorization header \u2014 not OAuth \u2014 so a dashboard-monitoring app would need the user to generate and paste a key.",
   "quote": "Click **Create API Key**. Copy the key immediately. ... Treat your API key like a password. Do not commit it to version control or share it publicly.",
   "importance": "central"
  },
  {
   "claim": "Cline billing is credit-based: API requests fail with a 402 Payment Required error when the account runs out of credits, and credits are added via the app.cline.bot dashboard, confirming the credits model behind Cline subscriptions.",
   "quote": "Your account has insufficient credits. Add credits at app.cline.bot",
   "importance": "supporting"
  },
  {
   "claim": "Token consumption is only surfaced per-request via the `usage` field in each chat completion response; the getting-started documentation (sections: Prerequisites, Create an API Key, Make Your First Request, Verify the Response, Try Streaming, Try a Free Model, Troubleshooting, Next Steps) documents no endpoint for checking account balance, remaining credits, or aggregated usage history \u2014 meaning a usage dashboard cannot rely on this documented API for account-level metrics.",
   "quote": "The `usage` field shows how many tokens were consumed.",
   "importance": "central"
  },
  {
   "claim": "Cline offers free models usable through the API without consuming credits, which affects how spend/credit-burn metrics should be interpreted (not all API usage draws down credits).",
   "quote": "To test without spending credits, use one of the free models",
   "importance": "tangential"
  }
 ],
 "sourceQuality": "primary",
 "publishDate": "unknown"
}

## Result 25
{
 "claims": [
  {
   "claim": "Codex is available on all ChatGPT plans (Free, Go, Plus, Pro, Business, Edu, Enterprise), and its usage limits are not fixed message counts per plan but draw from a shared 'agentic usage limit' also consumed by ChatGPT for Excel and Workspace Agents, with per-message consumption varying by task size/complexity \u2014 so a dashboard cannot assume a static messages-per-window quota.",
   "quote": "Codex usage limits depend on your plan and count toward your agentic usage limit. Usage from Codex, ChatGPT for Excel, and Workspace Agents counts toward agentic usage. The number of Codex messages you can send within these limits varies based on the size and complexity of your coding tasks, and where you execute tasks.",
   "importance": "central"
  },
  {
   "claim": "The officially documented ways for individual users to check remaining Codex usage are the web 'Codex usage page' and in-product limit banners; some Plus and Pro users can purchase credits to continue past the limit. No public per-user usage/limits API is documented in this article, implying any programmatic per-user usage retrieval for a dashboard relies on undocumented endpoints or local data.",
   "quote": "If you are nearing or have reached your Codex limit, check the Codex usage page or the limit banner for the options available on your plan. Some Plus and Pro users can add credits to continue using Codex; other users may need to upgrade or wait for the limit to reset.",
   "importance": "central"
  },
  {
   "claim": "Authentication for all Codex clients (Codex app, Codex CLI, Codex IDE extension, Codex web) when used with a ChatGPT plan is ChatGPT account sign-in (not an API key), which is the credential a monitoring tool would need to reuse (e.g. tokens stored in ~/.codex/auth.json).",
   "quote": "Sign in with your ChatGPT account. ... Launch your preferred Codex client and follow the instructions to sign in with ChatGPT: Codex app Codex CLI Codex IDE extension Codex web",
   "importance": "supporting"
  },
  {
   "claim": "OpenAI exposes Codex usage logs \u2014 including local CLI and IDE extension usage \u2014 through its Compliance API, but this is an enterprise/workspace-admin surface, not something an individual Plus/Pro subscriber can use for a personal usage dashboard.",
   "quote": "Codex usage, including local clients such as the CLI and IDE extension as well as web or cloud-delegated usage, is available in the Compliance API .",
   "importance": "supporting"
  },
  {
   "claim": "A documented programmatic analytics surface, the Codex Enterprise Analytics API, exists but is restricted to Enterprise workspaces and requires an organization API key with specific access \u2014 confirming there is no official usage-analytics API for individual subscription users.",
   "quote": "Access to Codex Enterprise Analytics is available to Enterprise workspaces with Codex enabled. To use the Codex Enterprise Analytics API, use an organization API key that has Codex Enterprise Analytics access.",
   "importance": "supporting"
  }
 ],
 "sourceQuality": "primary",
 "publishDate": "~2026-06-23 (page states \"Updated: 12 days ago\" as of the 2026-07-05 Wayback snapshot used; live page returned HTTP 403)"
}

## Result 26
{
 "claims": [
  {
   "claim": "The Cline VS Code extension fetches credit and billing data from Cline API REST endpoints of the form /api/v1/users/${uid}/balance, /api/v1/users/${uid}/usages, /api/v1/users/${uid}/payments, and /api/v1/organizations/${id}/balance, implemented in a ClineAccountService class (methods fetchBalanceRPC, fetchUsageTransactionsRPC, fetchPaymentTransactionsRPC, fetchOrganizationCreditsRPC).",
   "quote": "`/api/v1/users/${uid}/balance` | \"Fetch user's current credit balance\" ... `ClineAccountService` \u2014 \"handles the underlying HTTP requests to the Cline API\"",
   "importance": "central"
  },
  {
   "claim": "These credit/usage requests are session-authenticated: they go through an authenticated axios client (authenticatedRequest) that depends on the user session established by Cline's authentication flow, rather than a public unauthenticated API.",
   "quote": "Requests use \"an authenticated axios client via `authenticatedRequest`\" ... \"For the authentication flow that establishes the user session required by these features, see Authentication System\"",
   "importance": "central"
  },
  {
   "claim": "Cline's usage data is per-request transaction-level, exposing model name, credits used, timestamp, operation, and token counts (prompt_tokens and completion_tokens), with credits_used stored in microcredits and converted to dollars by dividing by 1,000,000 \u2014 meaning a dashboard can compute spend and input/output token splits, but Cline's billing model is credits, not session/weekly rate-limit windows.",
   "quote": "**Usage Transactions** \u2014 `UsageTransaction` proto message with: `ai_model_name`, `credits_used` (microcredits; converted to dollars via `/1,000,000`), `created_at`, `operation`, `prompt_tokens`, `completion_tokens`",
   "importance": "central"
  },
  {
   "claim": "The extension's account view refreshes credit data on a polling interval (React useInterval in ClineAccountView, webview-ui/src/components/account/AccountView.tsx) and caches per-entity data in a Map keyed by user or organization ID, so near-real-time balance polling is the extension's own established pattern.",
   "quote": "\"The component uses `useInterval` to periodically refresh credit data\" ... `dataCache` (Map) stores per-entity data (keyed by UID or org ID)",
   "importance": "supporting"
  },
  {
   "claim": "The web-facing credits dashboard lives at app.cline.bot (e.g. https://app.cline.bot/dashboard/account?tab=credits), and the extension exposes a gRPC AccountService (proto/cline/account.proto) with RPCs getUserCredits, getOrganizationCredits, setUserOrganization, and getRedirectUrl for credit purchase redirects back to the IDE.",
   "quote": "**Personal dashboard**: `https://app.cline.bot/dashboard/account?tab=credits&redirect=true` ... `getUserCredits` (EmptyRequest \u2192 `UserCreditsData`)",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-05-24 (DeepWiki last indexed, commit 8a6441fd)",
 "sourceQuality": "secondary"
}

## Result 27
{
 "claims": [
  {
   "claim": "Claude Code stores its OAuth credentials in the macOS Keychain under the generic-password service name 'Claude Code-credentials'.",
   "quote": "**Service Name:** `Claude Code-credentials`",
   "importance": "central"
  },
  {
   "claim": "The Claude Code OAuth token can be extracted from the macOS Keychain via the command `security find-generic-password -s 'Claude Code-credentials' -w`.",
   "quote": "security find-generic-password -s 'Claude Code-credentials' -w",
   "importance": "central"
  },
  {
   "claim": "The stored Keychain credential is a JSON object containing accessToken (prefixed sk-ant-oat01-), refreshToken, and expiresAt (ISO 8601 timestamp) fields.",
   "quote": "{\"accessToken\":\"sk-ant-oat01-[REDACTED]\",\"refreshToken\":\"[REDACTED]\",\"expiresAt\":\"[REDACTED]\"}",
   "importance": "supporting"
  },
  {
   "claim": "Claude Code reads the CLAUDE_CODE_OAUTH_TOKEN environment variable in preference to the Keychain-stored credential when authenticating.",
   "quote": "Claude Code prioritizes the CLAUDE_CODE_OAUTH_TOKEN environment variable over Keychain.",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-03-06",
 "sourceQuality": "blog"
}

## Result 28
{
 "claims": [
  {
   "claim": "The antigravity-usage CLI (TypeScript, MIT, ~344 stars) obtains Google Antigravity quota via a dual-fetch strategy: it first queries the Antigravity Language Server running locally inside the IDE, and falls back to Google's Cloud Code API if the local connection fails or when managing multiple accounts.",
   "quote": "First, it tries to connect to the Antigravity Language Server running inside your IDE. ... If Local Mode fails (or if managing multiple accounts), it uses the Google Cloud Code API.",
   "importance": "central"
  },
  {
   "claim": "Cloud mode hits undocumented private Google endpoints \u2014 POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist (with metadata.ideType 'ANTIGRAVITY') and /v1internal:fetchAvailableModels \u2014 authenticated with 'Authorization: Bearer {token}'; responses expose availablePromptCredits, planInfo.monthlyPromptCredits, currentTier, and per-model quotaInfo.remainingFraction / quotaInfo.isExhausted. The 'v1internal' path marks this as a reverse-engineered, fragile data source with no ToS blessing.",
   "quote": "src/google/cloudcode.ts: 'https://cloudcode-pa.googleapis.com' ... '/v1internal:loadCodeAssist' ... request body { \"metadata\": { \"ideType\": \"ANTIGRAVITY\", \"platform\": \"PLATFORM_UNSPECIFIED\", \"pluginType\": \"GEMINI\" } } ... '/v1internal:fetchAvailableModels' ... quotaInfo.remainingFraction and quotaInfo.isExhausted",
   "importance": "central"
  },
  {
   "claim": "Local mode speaks the Connect RPC protocol over HTTP to the Antigravity Language Server on a dynamically discovered localhost port (via process detection and port probing in src/local/process-detector.ts, port-detective.ts, port-prober.ts), calling the Codeium-derived method exa.language_server_pb.LanguageServerService/GetUserStatus with headers 'Connect-Protocol-Version: 1' and 'X-Codeium-Csrf-Token' \u2014 a viable no-auth data path for a macOS dashboard while the IDE is running, but entirely undocumented/reverse-engineered.",
   "quote": "src/local/connect-client.ts: '/exa.language_server_pb.LanguageServerService/GetUserStatus' ... 'Connect-Protocol-Version': '1' ... 'X-Codeium-Csrf-Token' (CSRF token, if available)",
   "importance": "central"
  },
  {
   "claim": "Cloud-mode authentication is a Google OAuth login flow initiated by 'antigravity-usage login' (with a --manual headless option); OAuth tokens are stored locally, on macOS under ~/Library/Application Support/antigravity-usage/.",
   "quote": "Login with Google ... All tokens stored locally on your machine, never sent to third-party servers. (Storage: macOS ~/Library/Application Support/antigravity-usage/)",
   "importance": "supporting"
  },
  {
   "claim": "The tool surfaces per-model quota usage and reset times (~5-hour reset windows) for models including claude-sonnet-4-5, gemini-3-flash, and gemini-3-pro-low (hiding 'autocomplete' models unless --all-models), caches quota data for 5 minutes (bypass with --refresh), and offers JSON output via --json \u2014 indicating Antigravity quota is per-model fraction-based rather than token-count-based.",
   "quote": "View quota usage and reset times for all accounts in a single table ... Quota data is cached for **5 minutes**. Use the `--refresh` flag to force a new fetch ... By default, `antigravity-usage` hides 'autocomplete' models",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-02-14 (latest release v0.2.8; repo last updated then)",
 "sourceQuality": "primary"
}

## Result 29
{
 "claims": [
  {
   "claim": "An undocumented Anthropic endpoint, GET https://api.anthropic.com/api/oauth/usage, returns server-side authoritative usage-window state (utilization percentage, reset time, weekly limits) \u2014 the same data behind Claude Code's /usage command \u2014 making it a reverse-engineered but community-verified data source for a usage dashboard.",
   "quote": "There's an undocumented Anthropic OAuth endpoint that returns **server-side** usage window state. It provides the authoritative utilization percentage, reset time, and weekly limits \u2014 the same data that powers Claude Code's `/usage` command.",
   "importance": "central"
  },
  {
   "claim": "The endpoint's JSON response exposes exactly the session/weekly metrics a dashboard needs: a `five_hour` object (5-hour session window), `seven_day` (weekly all-models limit), `seven_day_opus`/`seven_day_sonnet` (per-model weekly limits, null if unused), and `extra_usage` (credit overages), each with `utilization` (0\u2013100 percent) and `resets_at` (ISO 8601 UTC timestamp).",
   "quote": "`utilization` = percentage used (0\u2013100), 0 when no active window ... `five_hour` = the 5-hour session window ... `seven_day` = weekly limit (all models combined) ... `seven_day_opus` / `seven_day_sonnet` = per-model weekly limits (null if unused)",
   "importance": "central"
  },
  {
   "claim": "On macOS the OAuth access token is stored in the login Keychain under the item \"Claude Code-credentials\" and can be read with `security find-generic-password -s \"Claude Code-credentials\" -w`, yielding JSON with claudeAiOauth.accessToken, refreshToken, and expiresAt (epoch milliseconds); Linux/Windows use ~/.claude/.credentials.json, and CLAUDE_CODE_OAUTH_TOKEN is an env-var alternative.",
   "quote": "**macOS Keychain:**\n```bash\nsecurity find-generic-password -s \"Claude Code-credentials\" -w\n```\nReturns JSON with `claudeAiOauth.accessToken`, `claudeAiOauth.refreshToken`, `claudeAiOauth.expiresAt` (epoch milliseconds).",
   "importance": "central"
  },
  {
   "claim": "Calling the endpoint requires the headers `anthropic-beta: oauth-2025-04-20` and `User-Agent: claude-code/<version>`; omitting the User-Agent triggers persistent HTTP 429s, while with it polling at 180-second intervals is reliable (rate limiting is per-access-token), which dictates a ~3-minute cache/refresh cadence for any monitoring app.",
   "quote": "**Critical:** The `User-Agent: claude-code/<version>` header is required. Without it, you hit an aggressively rate-limited bucket and get persistent 429s. With it, the limit is much more generous. ... With correct `User-Agent`: safe at 180-second intervals. Several community tools use this.",
   "importance": "supporting"
  },
  {
   "claim": "OAuth access tokens expire roughly every 60 minutes and are auto-refreshed only while Claude Code runs (`claude update` also forces a refresh), and local JSONL parsing is unreliable across devices \u2014 the issue reports local parsing showing a different utilization than the server for the same window \u2014 so server API data should be treated as authoritative over ~/.claude JSONL-derived window math.",
   "quote": "Access tokens expire every ~60 minutes. ... Claude Code auto-refreshes using the refresh token when it's running. ... ccm currently calculates window boundaries from local JSONL files. This is fast and works well for single-device use, but it produces incorrect results when activity happens on multiple devices",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-04-11",
 "sourceQuality": "forum"
}

## Result 30
{
 "claims": [
  {
   "claim": "Claude Code writes streaming placeholder values (typically 1 or 0) into the usage.input_tokens field of its ~/.claude JSONL transcript entries, and these values are never updated to the final token counts after the request completes.",
   "quote": "75% of JSONL entries have `usage.input_tokens` of 1 or 0 \u2014 these are streaming placeholder values that never get updated to the final count.",
   "importance": "central"
  },
  {
   "claim": "Deduplicated JSONL token sums systematically undercount real usage compared with Claude Code's own statusbar totals: input tokens by roughly 100-174x and output tokens by roughly 10-17x across the author's measured sessions (e.g., Feb 20: 41,444 input tokens in JSONL vs 7,199,162 in statusbar).",
   "quote": "The 100-174x input divergence and 10-17x output gap indicate systematic undercounting in JSONL.",
   "importance": "central"
  },
  {
   "claim": "Third-party usage trackers that parse the JSONL transcripts, explicitly including ccusage, inherit this undercounting and produce systematically incorrect input/output token accounting.",
   "quote": "Tools like [ccusage](https://github.com/ryoppippi/ccusage) that read JSONL are affected by the same issue",
   "importance": "central"
  },
  {
   "claim": "Cache-related fields in the JSONL (cache_read_input_tokens, cache_creation_input_tokens) do roughly match the statusbar (~0.7-1.1x), so cached-token metrics read from JSONL are comparatively reliable even though input/output counts are not; additionally, JSONL output_tokens exclude thinking tokens and the same requestId can appear 2-10 times with identical placeholder values, requiring deduplication.",
   "quote": "Cache metrics match (~1x), confirming both sources track the same API calls. ... The same `requestId` appears 2-10 times with identical placeholder values ... Output tokens in JSONL don't include thinking tokens (which the statusbar does), explaining the 10-17x gap",
   "importance": "supporting"
  },
  {
   "claim": "Anthropic closed the issue as 'not planned' (labels: area:cost, enhancement, stale) with no visible maintainer commitment to write final usage values into the JSONL, meaning a dashboard built on JSONL parsing cannot expect this data source to be fixed and should treat JSONL-derived input/output token totals as unreliable.",
   "quote": "Status: Closed as not planned ... Labels: `area:cost`, `enhancement`, `stale` ... No visible maintainer/Anthropic responses are shown",
   "importance": "supporting"
  }
 ],
 "publishDate": "2026-02-24",
 "sourceQuality": "forum"
}

## Result 31
{
 "claims": [
  {
   "claim": "ccusage derives all token/cost metrics purely by parsing local files that coding-agent CLIs already write to disk \u2014 it makes no authenticated API calls to providers, so a dashboard using this technique needs no OAuth/session tokens and works read-only/offline.",
   "quote": "ccusage reads the local usage files that coding CLIs already generate ... 100% Local - All analysis happens on your machine ... Read-Only - ccusage only reads files, never modifies them",
   "importance": "central"
  },
  {
   "claim": "For Claude Code specifically, ccusage reads usage data from the directories ~/.config/claude/projects/ and ~/.claude/ (i.e., the local project transcript logs), confirming that Claude Code session JSONL transcripts on disk are a viable data source for per-session token accounting.",
   "quote": "Claude Code | `claude` | `~/.config/claude/projects/`, `~/.claude/`",
   "importance": "central"
  },
  {
   "claim": "ccusage supports local-log-based usage tracking for 15+ agents including both OpenAI Codex and Claude Code and Gemini CLI, implying Codex also writes parseable local usage/session data (relevant to the ~/.codex sessions/*.jsonl hypothesis in the research question).",
   "quote": "Claude Code, Codex, OpenCode, Amp, Droid, Codebuff, Hermes Agent, pi-agent, Goose, OpenClaw, Kilo, Kimi, Qwen, GitHub Copilot CLI, and Gemini CLI",
   "importance": "central"
  },
  {
   "claim": "ccusage models Anthropic's 5-hour rolling session window by grouping locally logged usage into 5-hour billing blocks (its 'blocks' report), meaning session-window tracking can be approximated from local logs without any Anthropic limits endpoint.",
   "quote": "5-Hour Blocks Report: Track usage within Claude's billing windows",
   "importance": "supporting"
  },
  {
   "claim": "ccusage's dollar figures are estimates computed locally from LiteLLM's model-pricing dataset (cacheable for offline use), not actual billing data from provider APIs; it also breaks tokens out into cache-creation and cache-read categories separately from input/output.",
   "quote": "use `--offline` to use pre-cached pricing data without network connectivity ... Tracks and displays cache creation and cache read tokens separately",
   "importance": "supporting"
  }
 ],
 "publishDate": "Actively maintained; latest release v20.0.14 dated 2026-06-15 on the repo page",
 "sourceQuality": "primary"
}