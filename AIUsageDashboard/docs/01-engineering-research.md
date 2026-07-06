# Engineering Research: AI Usage Dashboard

## Provider Landscape

There is no single, officially documented per-user usage API that spans OpenAI Codex, Anthropic Claude Code, Cursor, Antigravity, and Cline. Each provider stores quota and usage in a different place: local logs, private web dashboards, browser cookies, or undocumented endpoints. The product must therefore be local-first and honest about confidence.

## Core Research Findings

1. **Local files/logs are the most reliable backbone.** They are on the user's machine, do not require API credentials, and can be watched in real time.
2. **Undocumented/private endpoints are useful but fragile.** They should live behind isolated provider adapters and never in shared core code.
3. **Every metric must carry a confidence label.** Users must be able to tell the difference between exact provider-reported numbers and locally parsed estimates.
4. **Quota models differ across providers.** Claude Code and Codex lean toward session/weekly limits; Cursor is monthly-budget oriented; Cline is credit/subscription based; Antigravity is largely unknown.

## Provider Notes

### Claude Code
- Primary source: `~/.claude/projects/<encoded-project-path>/<session-id>.jsonl`.
- JSONL contains assistant messages with `usage` blocks: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`.
- Logs may be retained only ~30 days unless `cleanupPeriodDays` is changed in `~/.claude/settings.json`.
- Must deduplicate by message/request/session ID, stream large files, and parse defensively.

### OpenAI Codex
- Reference: CodexBar community implementation.
- Possible sources: `~/.codex/auth.json`, local Codex logs, CLI/RPC, cost scanning, and optional authenticated provider endpoints.
- `rate_limits` may be null in some execution modes.
- Private endpoints change frequently; keep assumptions in an adapter.

### Cursor
- Usage lives in a web dashboard; no stable public API.
- Local source: `state.vscdb` in Cursor storage, key likely `cursorAuth/accessToken`.
- Community trackers often use browser cookie `WorkosCursorSessionToken`.
- Usage is monthly budget oriented: included, bonus, on-demand, model breakdowns.
- Model as monthly budget rather than forcing weekly/session shapes.

### Cline / Cline Pass
- Dashboard at `https://app.cline.bot/dashboard/subscription`.
- Credit/subscription based.
- Likely requires web dashboard or local extension state plus user authentication.
- Treat as credits quota window; most metrics unavailable in MVP.

### Antigravity
- Least documented.
- Likely local logs/config, web/app endpoints, per-model quota fractions.
- MVP is skeleton only; do not invent fake implementation.

## Confidence Model

All metrics must be labeled with one of:

- `exact`: computed from fully known values with no ambiguity.
- `providerReported`: returned by an official or provider endpoint.
- `localParsed`: parsed from local logs on the user's machine.
- `estimated`: inferred from partial or incomplete data.
- `unavailable`: no data source currently exists.

The product must never display estimates as exact.

## Decision Log

- **Local-first architecture:** Local logs and files are the primary data source. Private endpoints are secondary and opt-in.
- **Provider abstraction:** Each provider returns a normalized `ProviderSnapshot`, but adapters handle their own auth and raw data formats.
- **Flexible quota windows:** Do not force every provider into session/weekly/daily. Support `session`, `daily`, `weekly`, `monthly`, `credits`, `perModel`, and `lifetime`.
- **Security:** Credentials live in Keychain. Raw provider responses are stored only in debug/dev builds.
- **Honest UI:** Confidence badges are first-class UI elements, not afterthoughts.
