# Brief WP-E · Integration fixes before 0.13.0 ships (Codex gpt-6.1-sol)

cd /Users/abhayp/wt/lane1 — work ONLY in this directory (branch `patch/2026-11-15/integration-fix`, cut from
`dev` with all of 0.13.0 merged). Exception: your result file at the absolute path below.
Read `tasks/patch-bibles/2026-11-15.md` §3 and §4 first.

1. **A failing test in the full suite**: `CodexLiveQuotaTests.testLiveWeeklyKeepsTighterLogIndividualLimit`
   fails on `dev` (log: `~/Library/Developer/TokeiWork/integration-0.13.0.log`). Find the cause. Check whether
   it passes on the pre-0.13.0 base `713cf93` (a `git worktree` is not available to you; use `git stash`-free
   means such as `git show 713cf93:<path>` reading, or `git bisect run` inside this worktree with the single
   test, restoring the branch after). If a 0.13.0 change broke real behaviour (suspect: the shared
   `RoutePlan.bindingWindows` filter now used by the Codex account headline), fix the code and keep the test as
   is. Only if the test is date- or load-dependent on the old code too, fix the test's clock, with evidence.
2. **Security review lows** (all four, each with a test that fails first where code changes):
   a. `Core/Agent/AgentSnapshot.swift` (~line 581) label sanitiser: the length bound counts grapheme clusters
      and allows combining marks, so one letter plus 100,000 marks passes as short. Bound by unicode scalars (or
      UTF-8 bytes) and drop combining marks. This sanitiser also serves `get_burn_opportunities`; existing
      sanitiser tests keep passing.
   b. `TokeiCLI/RouteFormatting.swift` (~line 57): do not echo the row's `reason` from the snapshot file to an
      agent or terminal. Rebuild the sentence in the CLI from fixed sentences plus the row's own fields
      (disposition, percent left, expiry), so a tampered snapshot cannot place an instruction in front of an
      agent. The `--json` shape keeps its keys; the `reason` and `advice` values become the rebuilt sentences.
   c. `App/AIUsageDashboardApp.swift` (~line 113): with `TOKEI_PERF_PROBE=1` set in a normal Release launch the
      app hits `fatalError`. Ignore the probe when its guard fails (normal launch proceeds); the benchmark
      script itself must still fail loudly when its isolation check fails (exit non-zero from the script side).
   d. `scripts/perf-bench.sh`: every `python3 -` becomes `python3 -I -` (and `python3 -I` for script files).
3. Run the touched classes, the Codex quota classes, the route CLI and MCP classes and the sanitiser tests with
   `-derivedDataPath ~/Library/Developer/TokeiWork/dd-fix`, one `perf-bench.sh` run on a Release build to show
   the script still works and stays under budget, then `bash .claude/gates/run-all.sh fast`.
No merge, no push. Result: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-integration-fix.result.md`,
line 1 `STATUS: READY` or `STATUS: BLOCKED`; per item the cause, the commit, the test and its red-then-green
lines. Then run `hc send t1d "E result written"`.
