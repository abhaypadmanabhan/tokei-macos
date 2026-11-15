# WP-W round 2a (from review r1: /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-review-r1.md)

1. S1 (should): below 560 px the three scenario buttons in `components/route-demo.tsx` have no accessible name
   (long label hidden, short label `aria-hidden`). Give each button a name at every width, and add a check that
   would have failed: a gate or test asserting every `button` in the served HTML has a non-empty accessible
   name. Show it red on the old code (`~/agent-kit/bin/prove-red`).
2. Leave the three asset deletions uncommitted; that one waits for Abhay's yes (the guard is his).
3. A later round 2b brings the final demo-data captures and the 0.13.0 strings; do not wait for it now.

Rebuild with all gates, rerun page-check at 390. Append a "Round 2a" section to your result file, then
`touch /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-fix-r1.done && echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-fix-r1.done`
and run `hc send t1d "W round 2a done"`.
