# WP-W round 2c: pass-2 captures with the route row

`~/Library/Developer/TokeiWork/proof/route-ui/site-captures/` was refreshed (read `snapshots.md`; `*-content.png`;
demo fixture, checked by the orchestrator). New: `popover-route` (popover with "Send work here next" open),
`overview-usage-tall` (chart, route row, agent tiles), `overview-route`, `provider-codex-route-chip`.
1. Set `ROUTE_CAPTURE` so the "which plan" section shows the real route row beside or under the demo once
   `route` ships (popover-route is the tight one). Because `route` is still `shipped: false`, the hero and other
   sections must keep showing only captures that are true of 0.12.0 until the flip: a capture containing the
   "Send work here next" row belongs behind the claims file too. Arrange it so the release flip swaps the hero
   to the 0.13.0 captures (`overview-usage-tall` plus `popover`) in the same one-file change; the gate checks both sets.
2. Review nit S2 (`W-review-r2.md`): unknown rows sort by id like the app.
Rebuild with all gates, page-check, and take full-page screenshots in BOTH states (claims off, and a local
build with the three claims flipped on, not committed) into `shots-r2c/`. Append "Round 2c" to your result,
then `echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-fix-r2c.done` and run
`hc send t1d "W round 2c done"`.
