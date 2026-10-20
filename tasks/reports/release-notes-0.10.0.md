## [0.10.0] — 2026-10-20

Build 10. Adopts T3 Code v2's usage-measurement techniques where Tokei's own numbers were off.
Audit trail: `tasks/patch-bibles/2026-10-20.md` (measurement table, three work packages),
`tasks/checkpoints/2026-10-20-t3-parity-checkpoint.md`, `tasks/reports/2026-10-20-wp{1,2,3}.result.md`
and `tasks/reports/release-2026-10-20.md`. Every package was reviewed by a different model than its
author (Codex ↔ Claude); every CHANGES verdict led to a fix round and a delta review.

### Fixed — what your plan is worth
- **Value was priced as if every token came from one model.** Claude was priced entirely at
  `claude-sonnet-4-6` (+10 % on the audited Mac, where 78 % of tokens are `claude-opus-5-5`) and
  Codex at `gpt-5` (−36 %). Each record now keeps the model that served it (Claude
  `message.model`; Codex carries the latest `turn_context` model, kept across incremental appends),
  and month-to-date value is priced per model per day. On the audited Mac the running app's
  per-model tokens and dollars equal an independent recount of the logs exactly
  (Claude $9,168.69, Codex $322.11 month to date).
- **`<synthetic>` Claude records no longer count as usage.**
- **Prices:** exact model rates from the LiteLLM table with an offline seed for current models
  (`claude-opus-5-5`, `claude-opus-5`, `claude-fable-5-1`, `claude-sonnet-5-5`, `claude-haiku-5-5`,
  `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`); `[1m]` and date suffixes normalised; an exact slug
  always wins over a family prefix; a model with no public rate stays unpriced and says so.

### Added
- **Live Codex quota.** Tokei asks your installed `codex` CLI (`codex app-server`,
  `account/rateLimits/read`) for the account's real windows instead of trusting the newest log
  line, which could be an hour old and so not routable. A fresh reading makes the account
  `eligible` for agents that read Tokei's snapshot. At most one probe per account every 5 minutes,
  a hard 5 s timeout, the whole process tree killed on every exit, bounded output; Tokei still
  never reads Codex credentials. A failed probe keeps the last good reading until the logs are
  newer, and never hides a tighter limit the logs report (spend caps). **On by default**: it runs
  your Codex CLI, which talks to OpenAI with your ChatGPT sign-in. Turn it off in Settings → Codex.
- **Quota refresh every 5 minutes** while Tokei runs, coalesced with file-event refreshes; a
  change that lands mid-refresh triggers exactly one more.
- **Pace on every quota gauge.** Used share against the share of the window that has passed: an
  elapsed tick on each bar; "room to use" or "ahead of the clock" in words in Overview, the drill-in
  and the popover headline; a small state arrow on each menu-bar row. No pace when the window
  length, reset time or reported usage is unknown.
- **Value by model** in the Claude and Codex drill-ins: model, tokens and API-equivalent $ this month.

### Performance
- **Less CPU while your agents are busy.** Each Claude record's day and hour are now computed once,
  when it is parsed, instead of for all ~142k records on every refresh. Release build, window
  closed, one log line every 5 s: 10.5 % CPU vs 13.1 % for 0.9.0 (−20 %). With no agent activity:
  0.5 % (0.9.0: 0.2 %; the difference is the new 5-minute quota refresh). The live Codex probe runs
  the CLI for about 0.8 s at most once per account every 5 minutes; that process is not in these numbers.

### Security (release review, all low)
- A broken or planted `codex` can no longer crash Tokei with non-finite numbers, absurd reset
  dates or huge credit counts; a hostile price row can no longer overflow costs to infinity
  (rates are capped at $100,000 per million tokens).
- Accepted: the `codex` binary is resolved from your user-writable install folders (fnm, nvm,
  npm, bun, `~/.local/bin`) before Homebrew; an attacker who can write there already runs as you.

### Known
- A Tokei launched hidden (for example a login item set to hide) does not start syncing until its
  window or menu-bar popover is first shown. Pre-existing; follow-up.
- In the narrow drill-in column the pace sentence can truncate ("room to…"); the full sentence is
  in the tooltip and the accessibility label.
- Follow-ups: Antigravity token counts from its conversation databases, Codex priority-tier
  pricing, reported cost for Cline/opencode in the value engine, pace in the MCP snapshot.
