Tokei 0.12.0 turns the AI plans you already pay for into a game, warns you before unused capacity expires, and connects to your agents in one click.

**Burn it all**
- A new **Burn** tab (⌘2): a daily ring against your break-even goal (your plans' monthly price spread over the month), a second lap when you go past it, a streak of goal days, records (best day, best week, best month, longest streak), 13 badges with one plain rule each, this week's agents ranked, and how much of your recent windows you left on the table.
- The menu bar shows the same ring, today's burn, your streak and the next window about to reset.
- New badges, broken records and tier ups (all the way to Goblin mode) get a short celebration. Reduce Motion shows a still highlight instead.
- **Share my week** makes a card with your week's value, multiple, tier, streak and top agent, to copy or save. It never includes account names, emails or folders.

**Use it or lose it**
- When a plan window resets soon with 40% or more left, Tokei sends one quiet notification so you can spend it first. Badge and record moments share the same budget: at most 2 notifications a day, once per window. Settings › Burn nudges turns them off.
- Only usage on your plans counts: agents you set a plan price for, or, if you set none, Claude Code, Codex, Cursor, Antigravity and Copilot. Pay-per-token keys never count, and Tokei never points you at credits or overage. One limit: Claude's extra usage is logged together with plan usage, so Tokei cannot separate it yet.

**Your agents can see it too**
- Settings › Connect agents: one click connects Tokei's MCP server to Claude Code, Codex or Cursor, and one click installs the `tokei` command. From a terminal: `tokei mcp install`, `tokei install`, `tokei burn`.
- A new MCP tool, `get_burn_opportunities`, tells an agent which plan windows to spend first. `get_usage` has a compact summary mode (about 80% smaller). Existing tools are unchanged.
- Connecting never overwrites your settings: an existing different setup is left alone, symlinked dotfiles stay links, and the original file is backed up.

**Smoother**
- The menu bar item redraws only when its text changes, and the Value view does its math once per screen update instead of about fifteen times. On the test Mac, idle CPU with the window closed dropped from 3.7% to 2.2%, and launch to window from 335 ms to 293 ms.
- Tabs, drill-ins and Settings share one spring animation (instant with Reduce Motion).
