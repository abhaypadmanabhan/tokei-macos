Tokei 0.11.0 makes the numbers right, puts dollars on the main screen, and gets lighter on your disk.

**Dollars, front and centre**
- A new **Cost** view on Overview: today's API-equivalent value, a daily dollar chart for 7, 30 or 90 days, and dollars per agent.
  Days Tokei cannot price are shown as gaps, never as $0, and the change against the previous period is only shown when both
  periods are fully priced.
- Run-out forecasts on every quota gauge: "Runs out ~3:40 PM, 6 h before reset", "Lasts to reset" or "Out until 9:00 PM".
- Claude's extra usage (overage) budget appears in the Claude drill-in and on Value.

**More accurate numbers**
- **Codex:** recent Codex versions compress older session logs (`.jsonl.zst`), which Tokei could not read, so Codex tokens and
  value were badly undercounted (on the audited Mac, October showed $190 instead of about $2,048). Tokei now reads them with a
  built-in decoder; its October total matches an independent recount within 0.03 %. The first sync after launching takes longer
  while it reads those logs; later refreshes are unchanged.
- **Claude:** 1-hour cache writes are priced at their real rate (2x input instead of the 5-minute 1.25x).
- **Antigravity:** real token counts and value from its local conversation history (previously unavailable).
- **GitHub Copilot CLI:** token counts per model from its local session logs, counting a resumed session once.
- Fast and priority service tiers are priced at their own rates; models with no public price stay marked as unpriced.

**Lighter and safer**
- Tokei no longer copies Cursor's large database on every refresh when nothing changed, and rewrites its own files only when
  their contents change.
- Opening Tokei shows your last saved numbers straight away, with their age, instead of a blank page while it reads logs.
- Tokei's files are private to your user account (0600, folder 0700); network requests no longer keep a disk cache and refuse
  redirects to another host; Gemini quota is checked at most every 10 minutes, with a switch in Settings.
- Quota history is kept per account, so pace never compares one Claude account against another.

**Settings and alerts**
- Alert levels per tool, a warning before a quota runs out, and Open at login.

**For agents (MCP and CLI)**
- The MCP server negotiates protocol versions, describes its tools (read-only, structured output) and adds pace and run-out
  forecasts to every window. `get_usage` can filter by provider.
- New `tokei guard --min-headroom 15` exits 0 when there is room, 1 when not, 69 when no fresh reading exists.

**Look**
- No small uppercase labels anywhere: headings and captions are plain sentences.
- Keyboard: Cmd-1/2/3 for the tabs, Cmd-[ or Esc to go back, Cmd-R to sync.
