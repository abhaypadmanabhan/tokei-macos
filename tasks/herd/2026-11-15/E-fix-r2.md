# WP-E fix round 2 (review: /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-review-r2.md, "New findings", probes included)

Each with a test that fails on your current code first:
- S7 (blocker): a Codex individual spending cap must never count as "capacity about to reset unused", on any
  path, whatever type it was rebuilt with. Make it ineligible in `ExpiringHeadroomFinder` itself. Add the
  reviewer's probe as a test asserting the route row, the policy, the chip input and the exported snapshot
  recommendation all agree. Then grep every other consumer of expiring headroom (burn nudges, `tokei burn`,
  `get_burn_opportunities`, the Burn tab's use-it-or-lose-it list) and add one test showing the cap never
  appears there either; say what you found for each.
- S8 (should): a genuine multi-provider reason (the app's own sentences joined by "; ") must pass unchanged:
  check each clause, cap the clause count, fall back only when a clause fails. Test: an eight-provider generated
  reason stays byte-identical; a tampered clause still gets the fallback.
Rerun the touched classes plus the Codex quota, burn/expiring-headroom, route, MCP, CLI status and sanitiser
classes, then the fast gate. Append "Fix round 2" to your result file, then
`echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-fix-r2.done` and run
`hc send t1d "E fix r2 done"`.
