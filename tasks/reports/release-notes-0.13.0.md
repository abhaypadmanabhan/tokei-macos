Tokei 0.13.0 tells you, and your coding agents, which plan to send the next task to, and it runs lighter while your agents work.

**Send work here next**
- The menu bar and Overview now show one plan to use next, with the reason in a sentence. A plan whose window is about to reset with room left comes first, then the plan with the most room for its pace. Plans that are nearly used up go last.
- "Show the next 2" lists the runners-up. With one plan, stale readings or everything nearly used up, Tokei says so plainly instead of guessing.
- The ranking never points at credits or overage, and pay-per-token keys are never recommended.

**Your agents can ask the same question**
- A new MCP tool, `get_route`, gives a connected agent the same ranked list, so it can pick a plan before it starts a batch of work. It can also ask about one agent: "is this a good place right now?"
- From a terminal: `tokei route` (add `--json` for scripts, `--for <agent>` to ask about one). Exit codes say whether there is a recommendation, every plan is used up, or the data is missing.
- The menu bar, the Overview chip and the agent tools all use one rule, so they cannot disagree. Existing tools and commands are unchanged.

**Lighter while your agents work**
- A change in one agent's logs now refreshes that agent only, instead of all of them. With no Tokei window open, a busy agent is re-read at most every 15 seconds; opening the menu bar or the window catches up at once.
- Measured on one Apple silicon Mac (Release build, a synthetic agent writing every second, no window open, median of three 120-second runs): CPU 1.58% → 0.48%. Memory footprint over the same runs: 66.9 MB.
- The benchmark ships in the repository (`scripts/perf-bench.sh`) with a 1% CPU budget, so a slower build fails the check.
- Countdown clocks stop ticking while the window is off screen.

**Fixes**
- Plans with unusual window lengths are ranked by their real pace.
- After fixing a sign-in problem, Refresh shows the result straight away.
- `tokei version` now always matches the app's version.
