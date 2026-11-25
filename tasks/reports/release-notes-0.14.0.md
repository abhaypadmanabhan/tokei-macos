Tokei 0.14.0 reads three more plans from their official sources, and counts a shared pool once.

**SuperGrok**
- Turn on Grok in Settings › Live quota and Tokei shows your SuperGrok weekly pool, using the sign-in the Grok CLI already has. Tokei never changes that sign-in; if it has expired, Tokei asks you to run `grok` once.
- Grok and a Cursor Super plan share one pool. Tokei now counts it once in totals, routing, alerts and what your agents see.
- Cursor 3.x keeps its sign-in encrypted. Instead of a confusing error, Tokei now says why it cannot read Cursor's number and, on a Super plan, points you to the Grok row.

**Copilot and OpenCode Go, with a key you paste**
- Copilot: paste a GitHub fine-grained token with Plan: Read-only. Tokei shows this month's premium requests, AI credits and billed dollars. GitHub does not share your allowance, so Tokei shows counts, not a percent.
- OpenCode Go: paste your API key to see the 5-hour, weekly and monthly windows.
- Both are off until you turn them on. Keys stay in Tokei's own Keychain, are never shown again, and Remove deletes them.

**Privacy**
- Warnings about unreadable log files no longer include your folder paths.
