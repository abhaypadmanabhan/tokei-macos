# WP-C fix round 1 (review: /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/C-review-r1.md, read it fully)

- S1 (should, accepted): the two chips keep the shipped quieting rule. The route row always shows
  `RoutePlan`'s recommendation; a chip shows only when the existing human presentation policy
  (`RouteTargetPolicy.human`: spread and ceiling gates) would show one, and when it shows it marks the same plan
  the row recommends. Tests that fail on your current code: two equal plans → row recommends, no chip; 83% vs
  84% → no chip; a clear spread → chip on the row's plan.
- Then `git merge dev` (WP-D merged: `tokei route` text polish, CLI only), rebuild, rerun your test classes and
  the fast gate. Recapture only the screens the chip rule changes, if any (the demo fixture has a clear spread,
  so probably none; say which).
Append "Fix round 1" to your result file, then
`echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/C-fix-r1.done` and run
`hc send t1d "C fix r1 done"`.
