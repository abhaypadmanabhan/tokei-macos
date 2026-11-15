# WP-A fix round 1 (review: /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/A-review-r1.md, read it fully)

All accepted; behaviour fixes get a test that fails on your current code first.
- S1 (should): the harness leaves `ai.padzy.tokei.perf.<uuid>.plist` in the real `~/Library/Preferences`. Make
  the run leave nothing outside its temp tree (delete the run's own defaults domain in `finally`, and assert it
  is gone before exit 0). Remove the leftover `ai.padzy.tokei.perf.*` files this lane's runs created, by exact
  name, nothing else in that folder.
- S2: opening the popover or window also refreshes providers that have no watched folder when their last
  refresh is older than 15 s (so nothing on screen is up to 300 s stale).
- S3: a pending batch for another provider survives `refreshWatchPaths()` (emit it or mark a full rescan).
- S4: resolve watched roots once per batch (or cache on root change), not per event path.
- S5: a refresh the user asked for (manual Refresh) clears the failed-probe cadence, so fixing sign-in shows at once.
- S6: `SQLiteSidecarCopy` follows a symlinked database as before; a vanished `-wal` is nil, not an error; reuse
  the existing fingerprint type instead of a duplicate.
- S7: reuse a live Antigravity reading when `resetAt` is nil or in the future.
- S8: cancel the previous `fileRefreshTask` in `scheduleFileRefresh`.
- S9: set the CPU budget to 1.0% (so the harness catches this win regressing) and report CPU and mean footprint
  as the median of 3 runs of the final build, each run's JSON line included.

Rerun the touched classes plus Sync and parser classes, the fast gate, and the 3 harness runs. Append a
"Fix round 1" section to your result file (per finding: commit, test, red-then-green lines; the three runs and
the medians), then `echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/A-fix-r1.done`
and run `hc send t1d "A fix r1 done"`.
