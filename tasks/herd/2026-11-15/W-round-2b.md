# WP-W round 2b: final captures and 0.13.0 data

1. Captures: `~/Library/Developer/TokeiWork/proof/route-ui/site-captures/` (read `snapshots.md`; use the
   `*-content.png` files; all demo fixture data, checked by the orchestrator). Replace the Burn-only set: the
   hero shows the app (Overview quota or the popover beside a window, your call in the layout you have); "Pace
   and value" shows the quota bars with the pace tick (`overview-quota`) and Value; keep Burn in its own section.
   Every image stays listed in `lib/captures.ts` with source and safety note. A pass 2 (popover and Overview with
   the new "Send work here next" row) arrives later; leave the route section able to take one capture.
2. `tokei route` output: build the CLI from `~/src/tokei-macos` at `dev` (dbdc98e or later) into your own
   DerivedData, run it through `scripts/cli-sample.mjs` with a fictional snapshot that includes the new `route`
   block (see `AIUsageDashboard/AIUsageDashboardApp/Core/Agent/AgentRoute.swift` and the CLI tests for its
   shape), and put the verbatim lines in `routeCli.output`. Keep `shipped: false`.
3. Footprint data (from the speed lane's harness, `tasks/herd/2026-11-15/A-speed.result.md` "Fix round 1";
   quote from there, not from this note): CPU while one agent writes every second, no window open, median of
   three 120 s runs, Release build, synthetic workload, one Apple silicon Mac: 0.478% (0.12.0 behaviour on the
   same rig: 1.583%). Mean memory footprint, same runs: 66.9 MB. Fill `footprint` with these and the method line.
   Keep `shipped: false`. Do not claim a memory improvement; state the figure only.
4. Check `lib/route.ts` (the demo's rule) against the merged `Core/Utilization/RoutePlan.swift`: the score is
   elapsed minus used with unknown pace as zero elapsed, expiring capacity leads only when the plan's tightest
   window has at least 25% left, 85% used is avoid. Make the demo agree and say what changed.
5. The page names the agent tool: 0.12.0 shipped `get_route_recommendation`; 0.13.0 adds `get_route` (ranked
   list). Wording behind the claims file accordingly.

Rebuild with all gates, page-check at 390 and 1440, new full-page screenshots. Append "Round 2b" to your result
file, then `echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-fix-r2b.done` and run
`hc send t1d "W round 2b done"`.
