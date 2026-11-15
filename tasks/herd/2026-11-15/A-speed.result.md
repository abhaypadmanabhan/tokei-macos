STATUS: READY

# WP-A speed result

Branch: `patch/2026-11-15/speed`; worktree: `/Users/abhayp/wt/lane1`; final commit: `4a23297`.
Brief hash verified before work: `07e4fc2895488efe90513d5e4cb1de43ae721b570b0f15d2ff3cb1b5c4d60e1c`.

The lane's prescribed checks pass. CPU is 72.27% lower. The declared mean physical-footprint metric is
79.970 MB versus 80.374 MB. Diagnostic peak footprint increased by 2.906 MB; this is a caveat, not a
peak-memory improvement claim. Review and repo-wide finish gates remain the orchestrator's work under
`herdr-core/references/worker.md` rule 4.

## AC 1: repeatable, isolated benchmark

Implemented `AIUsageDashboard/scripts/perf-bench.sh` and `perf-budget.json`, plus the feature-map entry.
The fixed workload is 128 Claude sessions and 128 Cline sessions, 128 records each. A single synthetic
Claude JSONL session receives one complete assistant record every second for 120 seconds. The script
copies the supplied app, assigns the copy a unique `ai.padzy.tokei.perf.*` bundle/defaults identity,
re-signs only that temporary copy, and sets `HOME`, `CFFIXED_USER_HOME`, `TMPDIR`, `CLAUDE_CONFIG_DIR`,
`CODEX_HOME` and `ANTIGRAVITY_DATA_DIR` to its private temporary tree. It does not inherit credentials or
provider roots. All provider network toggles and Sparkle checks are off. The app positively confirms its
Foundation home before measurement. Its first real visible window is timed and closed; a three-second
settle follows initial refresh completion. CPU and footprint are sampled with all windows closed.
The child is terminated and waited for in `finally`, including on signals. Input app and installed app
are never edited or launched directly.

Minimal App exception: `App/AIUsageDashboardApp.swift` contains only the opt-in benchmark validation,
first-visible-window/close hook, Sparkle exclusion for that isolated run, and initial-refresh completion
signal. `WindowVisibilityMonitor.swift` was read only and remains unchanged. Counters are emitted by
`Core/Utilities/PerformanceProbe.swift` and `ProviderRegistry`; no account names or real usage are logged.

CPU time from macOS libproc is converted using `mach_timebase_info`. An independent busy-loop calibration
against Python's `process_time_ns` fails before measurement if the time units/layout are wrong. An
initial uncalibrated trial was discarded; its output is not the baseline below. Lesson L1033 records the
calibration correction, which is also enforced by the script.

Baseline source: `dev` application behavior at `713cf93`, with the documentation-only lane base
`d6c0b8f` and measurement-only commit `b0a4b58`. No refresh/cache/cadence behavior changed before the
baseline completed. Baseline and final app builds used the same Xcode project, Release configuration,
DerivedData and ad-hoc signing settings:

```sh
cd /Users/abhayp/wt/lane1/AIUsageDashboard
xcodegen generate
cd /Users/abhayp/wt/lane1
xcodebuild -project AIUsageDashboard/AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp -configuration Release -derivedDataPath ~/Library/Developer/TokeiWork/dd-speed CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES ENABLE_HARDENED_RUNTIME=NO build
```

Both build logs end in `** BUILD SUCCEEDED **`. Baseline log: `.scratch/speed/baseline-build.log`;
final log: `.scratch/speed/final-build.log`.

Exact benchmark command, run before behavior changes and again on the final committed Release build:

```sh
bash AIUsageDashboard/scripts/perf-bench.sh ~/Library/Developer/TokeiWork/dd-speed/Build/Products/Release/Tokei.app
```

Baseline stdout/stderr (`.scratch/speed/baseline-calibrated.txt`, exit 0):

```text
perf-bench: sampling 120 seconds with all windows closed
{"average_cpu_percent": 1.583, "budget_passed": true, "cold_launch_to_window_ms": 521.1, "defaults_suite": "ai.padzy.tokei.perf.c82a6bc4b92f441483837d0a6a110b10", "peak_footprint_mb": 82.267, "physical_footprint_mb": 80.374, "provider_refreshes": {"antigravity": 10, "claude_code": 10, "cline": 10, "codex": 10, "copilot": 10, "cursor": 10, "gemini": 10, "opencode": 10}, "sample_seconds": 120.004, "synthetic_home_verified": true, "workload_version": 1, "writes": 120}
Metric                              Measured        Budget
average_cpu_percent                    1.583 %       5.000 %
physical_footprint_mb                 80.374 MB    200.000 MB
cold_launch_to_window_ms             521.100 ms   1500.000 ms
Provider refreshes (120 seconds, window closed): {"antigravity": 10, "claude_code": 10, "cline": 10, "codex": 10, "copilot": 10, "cursor": 10, "gemini": 10, "opencode": 10}
```

Final stdout/stderr (`.scratch/speed/final-benchmark.txt`, exit 0):

```text
perf-bench: sampling 120 seconds with all windows closed
{"average_cpu_percent": 0.439, "budget_passed": true, "cold_launch_to_window_ms": 520.0, "defaults_suite": "ai.padzy.tokei.perf.711b213fc087496188432cc989a42c6d", "peak_footprint_mb": 85.173, "physical_footprint_mb": 79.97, "provider_refreshes": {"antigravity": 0, "claude_code": 8, "cline": 0, "codex": 0, "copilot": 0, "cursor": 0, "gemini": 0, "opencode": 0}, "sample_seconds": 120.001, "synthetic_home_verified": true, "workload_version": 1, "writes": 120}
Metric                              Measured        Budget
average_cpu_percent                    0.439 %       5.000 %
physical_footprint_mb                 79.970 MB    200.000 MB
cold_launch_to_window_ms             520.000 ms   1500.000 ms
Provider refreshes (120 seconds, window closed): {"antigravity": 0, "claude_code": 8, "cline": 0, "codex": 0, "copilot": 0, "cursor": 0, "gemini": 0, "opencode": 0}
```

The checked-in budgets, fixed before the valid baseline, are average CPU 5%, mean physical footprint
200 MB, cold first window 1500 ms, and exactly 120 sample seconds. Both runs pass. The mean footprint is
an average of 120 libproc physical-footprint samples, not RSS; the JSON also reports the maximum sample.
No harness workload, duration or budget was changed between the calibrated baseline and final run.

## AC 2: provider-specific refresh

`FileWatcher` now copies the actual FSEvent paths and flags, retains all paths in a debounced batch, and
maps component-bounded paths to their watched provider roots. Claude/Codex profile folders and configured
root overrides are included. Shared ancestors select every affected provider; unknown roots and dropped
FSEvents conservatively request a full refresh. `SyncEngine` merges targeted results with the existing
snapshots before saving, notifying, yielding and exporting, so unaffected providers remain present.
Concurrent targeted/full callers retain the existing one-trailing-refresh coalescing behavior.

Failing-first command, before this behavior changed:

```sh
cd AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-speed -only-testing:AIUsageDashboardCoreTests/TargetedRefreshTests test
```

Actual red output (`.scratch/speed/targeted-red.log`, exit 65):

```text
XCTAssertEqual failed: ("2") is not equal to ("1") - a Claude file event must leave Codex alone
Executed 1 test, with 1 failure (0 unexpected)
** TEST FAILED **
```

The final check uses Command F below. Relevant passing output:

```text
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testClaudeFileEventDoesNotRefreshCodex]' passed (0.482 seconds).
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testWatcherRetainsEveryProviderPathInOneBatchAndMapsSharedParents]' passed (0.001 seconds).
```

The live final benchmark independently records Claude=8 and every other provider=0 for 120 writes.

## AC 3: hidden-window cadence and immediate catch-up

`SyncEngine` keeps dirty provider IDs and one cancellable trailing deadline. Hidden file-event refreshes
are limited to one per provider per 15 seconds; visible/manual/periodic refreshes retain their behavior.
The same AppKit application-occlusion signal used by the existing visibility monitor is observed in Core.
Becoming visible flushes both the engine's dirty providers and the watcher's not-yet-emitted batch.
The accepted menu-bar lag is therefore up to 15 seconds while all windows/popovers are hidden.
The injected clock test advances all 15 seconds without a wall-clock wait, proves no early second refresh,
proves the exact deadline refresh, then proves opening flushes pending work immediately.

Check: Command F below. Actual output:

```text
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testHiddenWritesRunAtMostOncePerFifteenSecondsAndOpeningCatchesUp]' passed (0.016 seconds).
```

Existing periodic/coalescing, low-power and watcher scheduling/discovery tests also pass. The benchmark's
8 Claude refreshes over 120 seconds corroborate the hidden cadence on the running Release app.

## AC 4: skip unchanged Cline reads and SQLite copies

Cline now caches decoded per-file results by fresh size, mtime, ctime and inode, drops removed sources,
rebuilds calendar windows from the cached records each call, and retains the bounded read (cap+1 bytes).
Atomic replacement, rewrite, retargeted symlink and changing metadata invalidate the cache. A write during
the read is not cached. Malformed/oversized results retain their warning; transient I/O failures retry.
The existing file-alias behavior is preserved by fingerprinting the resolved target.

Cursor, opencode and Antigravity conversation parsers already had SQLite caches (including WAL), so their
copy paths were not rewritten. Antigravity's state parser did copy on every refresh; it now caches its parsed
state and skips the backup until main database, `-wal` or `-journal` fingerprints change. SQLite's coherent
online backup and private-file permissions are unchanged. Both pre- and post-copy stamps must agree.

Counting-test command before caching was added (only injectable I/O seams had been added):

```sh
cd AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-speed -only-testing:AIUsageDashboardCoreTests/RefreshCacheTests test
```

Actual red output (`.scratch/speed/cache-red.log`, exit 65):

```text
XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged SQLite state must not be copied twice
XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged Cline bytes must not be read twice
Executed 2 tests, with 6 failures (0 unexpected)
** TEST FAILED **
```

The alias regression was also seen fail before its fix (`.scratch/speed/symlink-red.log`, exit 65):

```text
XCTAssertEqual failed: ("Optional(0)") is not equal to ("Optional(7)")
Executed 1 test, with 1 failure (0 unexpected)
```

Check: Command F below. Actual passing output:

```text
Test Case '-[AIUsageDashboardCoreTests.RefreshCacheTests testAntigravityStateSkipsUnchangedSnapshotButCopiesCommittedWAL]' passed (0.029 seconds).
Test Case '-[AIUsageDashboardCoreTests.RefreshCacheTests testClineReadsUnchangedFileOnceAndInvalidatesOnRewriteAndRemoval]' passed (0.005 seconds).
Test Case '-[AIUsageDashboardCoreTests.RefreshCacheTests testClineSymlinkKeepsItsPreviouslySupportedNumbers]' passed (0.003 seconds).
```

The SQLite counting test commits a real WAL update, independently confirms the main database bytes did
not change, and requires exactly one additional copy. Relevant existing parser/backup tests passed too.

## AC 5: keep subprocesses on quota cadence

Read all three clients and their provider callers first. Codex already stamps successful AND failed
probes before suspension and enforces 300 seconds per account, so no Codex behavior changed.
Claude's successful disk cache already lasts 600 seconds, but missing/failed credential reads could spawn
again on every file refresh because the client factory creates a new client. The provider now retains the
original failed attempt and its deadline per identity/profile, also stamping an in-flight attempt before
suspension. It retries at 600 seconds and prunes profiles that disappear or change identity.
Antigravity had no discovery cadence; it now runs discovery/network requests at most every 300 seconds,
including failed discovery, reuses valid live windows between attempts and preserves existing stale-cache
observation times and reset/stale ceilings.

Failing-first command:

```sh
cd AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-speed -only-testing:AIUsageDashboardCoreTests/QuotaSpawnCadenceTests test
```

Actual red output (`.scratch/speed/spawn-red.log`, exit 65):

```text
XCTAssertEqual failed: ("3") is not equal to ("1") - file refreshes must not repeatedly spawn ps and lsof
XCTAssertEqual failed: ("3") is not equal to ("1") - a missing credential must not cause repeated subprocess probes
Executed 2 tests, with 4 failures (0 unexpected)
** TEST FAILED **
```

Check: Command F below; actual output:

```text
Test Case '-[AIUsageDashboardCoreTests.CodexLiveQuotaTests testFailedProbeIsAlsoLimitedToFiveMinutes]' passed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.CodexLiveQuotaTests testRefreshReusesReadingAt299SecondsAndProbesAt300]' passed (0.003 seconds).
Test Case '-[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testAntigravityFailedDiscoveryRunsAtMostEveryFiveMinutes]' passed (0.003 seconds).
Test Case '-[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testClaudeMissingCredentialsDoNotProbeAgainBeforeTenMinutes]' passed (0.005 seconds).
```

Quota checks ran with fakes/URLProtocol, not real credentials, Keychain or vendor endpoints. The running
benchmark deliberately disables all network quota paths; no claim of a live vendor measurement is made.

## AC 6: unchanged totals

No existing parser, sync or analytics test was weakened or edited. Added a real Claude+Cline fixture
comparison: append 42 Claude output tokens after an initial 10, targeted-refresh Claude, then full-refresh
both providers. Lifetime must actually be 52; all token windows and daily/hourly totals must match the full
refresh. A second fixture test compares complete encoded fake snapshots and checks that saved siblings
survive the partial update. Existing parser, sync, analytics and quota tests ran together at the end.

Check: Command F below; actual output:

```text
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testRealParserNumbersMatchBetweenTargetedAndFullRefresh]' passed (0.021 seconds).
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testTargetedAndFullRefreshProduceTheSameFixtureSnapshots]' passed (0.008 seconds).
Executed 293 tests, with 1 test skipped and 0 failures (0 unexpected) in 15.043 (15.178) seconds
** TEST SUCCEEDED **
```

The one skip is the opt-in external Python recount inside Copilot parser tests. Real-log smoke/oracle
classes were intentionally excluded; no real agent logs were needed for this lane.

## AC 7: measured win

| Metric | Calibrated baseline | Final committed Release | Change |
| --- | ---: | ---: | ---: |
| Average CPU, 120 s, window closed | 1.583% | 0.439% | 72.27% lower |
| Mean physical footprint | 80.374 MB | 79.970 MB | 0.404 MB lower |
| Maximum sampled physical footprint (diagnostic) | 82.267 MB | 85.173 MB | 2.906 MB higher |
| Cold launch to first visible window | 521.1 ms | 520.0 ms | 1.1 ms lower |
| Claude refreshes during sample | 10 | 8 | targeted, 15-second hidden cadence |
| Each other provider's refreshes | 10 | 0 | none caused by Claude writes |

The requested CPU halving passes and the declared mean footprint metric does not grow. The mean memory
change is small and is not a memory-saving claim. Peak footprint increased; neither its cause nor memory
pressure effects were profiled. The first after-run was 0.410% CPU / 64.588 MB mean / 83.017 MB peak;
that memory variability is a reason to keep the final exact numbers and the peak caveat visible. Both
after-runs used the unchanged workload and budgets. No profiler summary was required for a missed CPU
halving target because CPU dropped by more than half.

## Command F: final targeted test matrix

Actually run from the worktree root as `bash .scratch/speed/run-final-tests.sh`; generated the project
first, then ran the following exact command from `AIUsageDashboard/`. Full output is
`/Users/abhayp/wt/lane1/.scratch/speed/final-tests.log`.

```sh
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination platform=macOS -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-speed -only-testing:AIUsageDashboardCoreTests/AntigravityConversationParserTests -only-testing:AIUsageDashboardCoreTests/AntigravityQuotaClientTests -only-testing:AIUsageDashboardCoreTests/AntigravityQuotaObservationTests -only-testing:AIUsageDashboardCoreTests/AntigravitySQLiteModuleTests -only-testing:AIUsageDashboardCoreTests/AntigravityStateDBParserTests -only-testing:AIUsageDashboardCoreTests/BurnViewModelTests -only-testing:AIUsageDashboardCoreTests/ClaudeCodeProviderQuotaTests -only-testing:AIUsageDashboardCoreTests/ClaudeJSONLParserTests -only-testing:AIUsageDashboardCoreTests/ClaudeMultiAccountProviderTests -only-testing:AIUsageDashboardCoreTests/ClaudeUsageClientImplTests -only-testing:AIUsageDashboardCoreTests/ClineMessagesParserTests -only-testing:AIUsageDashboardCoreTests/ClineProviderTests -only-testing:AIUsageDashboardCoreTests/CodexCompressedRolloutTests -only-testing:AIUsageDashboardCoreTests/CodexFirstEventBoundsTests -only-testing:AIUsageDashboardCoreTests/CodexJSONLParserTests -only-testing:AIUsageDashboardCoreTests/CodexLiveQuotaTests -only-testing:AIUsageDashboardCoreTests/CodexProviderTests -only-testing:AIUsageDashboardCoreTests/CopilotSessionParserTests -only-testing:AIUsageDashboardCoreTests/CursorStateDBParserTests -only-testing:AIUsageDashboardCoreTests/DayBucketingTests -only-testing:AIUsageDashboardCoreTests/FileWatcherDiscoveryTests -only-testing:AIUsageDashboardCoreTests/FileWatcherSchedulingTests -only-testing:AIUsageDashboardCoreTests/FileWatcherTests -only-testing:AIUsageDashboardCoreTests/LikeForLikeTrendTests -only-testing:AIUsageDashboardCoreTests/LowPowerSyncTests -only-testing:AIUsageDashboardCoreTests/MiniProtobufReaderTests -only-testing:AIUsageDashboardCoreTests/OpencodeStoreParserTests -only-testing:AIUsageDashboardCoreTests/OverviewCostTests -only-testing:AIUsageDashboardCoreTests/QuotaSpawnCadenceTests -only-testing:AIUsageDashboardCoreTests/RefreshCacheTests -only-testing:AIUsageDashboardCoreTests/SyncEngineQuotaRefreshTests -only-testing:AIUsageDashboardCoreTests/TargetedRefreshTests -only-testing:AIUsageDashboardCoreTests/UsageAnalyticsTests -only-testing:AIUsageDashboardCoreTests/ValueByModelParserTests -only-testing:AIUsageDashboardCoreTests/WP1TierParserTests -only-testing:AIUsageDashboardCoreTests/WP4LabelMotionTests -only-testing:AIUsageDashboardCoreTests/ZstdDecoderTests test
```

```text
Executed 293 tests, with 1 test skipped and 0 failures (0 unexpected) in 15.043 (15.178) seconds
** TEST SUCCEEDED **
```

Final fast gate command (exit 0):

```sh
BASE_REF=dev bash .claude/gates/run-all.sh fast
```

Actual output (`.scratch/speed/fast-gates.log`):

```text
PASS  preflight
PASS  no-secret
PASS  no-large-artifact
PASS  no-uncommitted
PASS  cli-version-sync
PASS  format
PASS  lint
[run-all] ALL GATES GREEN
```

Format and lint are explicit SKIPs because `swiftformat` and `swiftlint` are not installed; the gate
runner labels their allowed skips PASS. They were not silently run or treated as available tools.

Static app-signing check (exit 0; launch intentionally delegated to the isolated benchmark):

```sh
TOKEI_VERIFY_SKIP_LAUNCH=1 bash AIUsageDashboard/scripts/verify-app.sh /Users/abhayp/Library/Developer/TokeiWork/dd-speed/Build/Products/Release/Tokei.app
```

```text
verify-app: static signing metadata verified across 9 nested code item(s)
verify-app: SKIP — launch assertion disabled by TOKEI_VERIFY_SKIP_LAUNCH=1
verify-app: RESULT: STATIC CHECKS PASSED, LAUNCH ASSERTION SKIPPED (not a full pass)
```

No new source warnings versus the measurement baseline. Seven unique source warnings persist in both
baseline and final build logs (existing Sendable annotations, unused lock result and deprecated chart
property); they were not changed in this lane.

## Commits

`git log --oneline dev..HEAD`:

```text
4a23297 Prove parser equivalence and preserve aliased Cline logs
b639927 Keep quota subprocess probes on their network cadence
06982ec Reuse unchanged Cline records and coherent SQLite state
3d26686 Refresh changed providers and coalesce hidden-window writes
b0a4b58 Measure Tokei refresh cost in an isolated synthetic home
```

## Contract additions and changed files

- `Core/Utilities/FileWatcher.swift`: additive `Event.paths` and `requiresFullRescan`; legacy path initializer
  retained; actual path batches, drop fallback, root discovery/overrides and provider mapping.
- `Core/Sync/SyncEngine.swift`: additive defaulted clock/visibility injection, internal targeted refresh and
  visibility/event seams; pending-provider union, full-refresh coalescing, hidden trailing deadline.
- `Core/Providers/ProviderRegistry.swift`: internal subset fetch; public `snapshotAll` retained; opt-in counter.
- `Core/Providers/ClaudeCodeProvider.swift`: defaulted clock injection and failed probe cadence by profile.
- `Core/Network/ClaudeUsageClient.swift`: existing 600-second cache cadence made internal for one shared value.
- `Core/Network/AntigravityQuotaClient.swift`: 300-second discovery/live quota cadence, existing stale rules.
- `Core/Parsing/ClineMessagesParser.swift`: bounded per-file decoded cache plus injectable reader.
- `Core/Parsing/SQLiteSidecarCopy.swift`: main/WAL/journal fingerprint helper; backup semantics unchanged.
- `Core/Parsing/AntigravityStateDBParser.swift`: cached parsed state and injectable copy; no new Sendable warning.
- `Core/Utilities/PerformanceProbe.swift`, `App/AIUsageDashboardApp.swift`: opt-in measurement-only hooks.
- `Tests/SyncTests/TargetedRefreshTests.swift`, `Tests/ParserTests/RefreshCacheTests.swift`,
  `Tests/ProviderTests/QuotaSpawnCadenceTests.swift`, `Tests/Fixtures/Fixtures.swift`: additive regression proof.
- `scripts/perf-bench.sh`, `scripts/perf-budget.json`, `docs/FEATURES.md`: repeatable method, budgets and entry.

`UsageProvider`, `UsageStore`, `ProviderSnapshot`, MCP and CLI contracts remain unchanged. No edits in
`TokeiCLI/**`, `Core/Agent/**`, UI, utilization or game code. No dependency added. No push, merge, PR or deploy.

## Known gaps, risk and cleanup

- Peak memory increased 2.906 MB even though the declared mean metric is slightly lower. This is explicit;
  do not publish a peak-memory reduction or a strong memory improvement claim from this result.
- Security scan, `prove-red` wrapper, cross-model review, repo-wide verify, full-suite integration and work-log
  entry belong to the orchestrator under the worker rules and were not run here. The recorded pre-fix
  targeted/cache/cadence logs are real failing assertions, not compile failures; they retain the red proof.
- Real vendor/network behavior and real agent logs were not exercised. Visibility catch-up has the injected
  clock proof; no separate human click tour or light/dark capture was needed for these unchanged UI pages.
- The final Release build is ad-hoc, not notarized. Build paths and exact measurement logs remain in this
  worktree's ignored `.scratch/speed/` and lane DerivedData for the orchestrator to rerun.
- All 17 check terminals started by this worker were removed after exit. Remaining live worker check
  terminals: 0. Remaining temporary benchmark app processes: 0. No dev server was started; listener snapshot
  is `.scratch/speed/listeners.txt`. All benchmark temporary homes/apps were cleaned by the script.
- Rollback: revert this lane's merge as specified in the patch bible. The new hidden label lag is the accepted
  15 seconds; unknown event roots intentionally prefer a full refresh over stale data.


## Fix round 1

STATUS: READY. Reviewed starting point: `4a23297`. Final fix head: `b7d841d`.
All requested fixes are implemented and checked, except the explicitly declined S6 symlink change:
**S6 symlink part declined, matches dev**, as instructed by t1d after the dev-code check.
The final 37-class matrix ran 301 tests with one skip and zero failures. Release build and fast gates
pass. Three final-build benchmark runs pass the tightened 1.0% CPU budget and preferences-cleanup assertion.

### S1: leave no benchmark preferences behind

Commit: `b7d841d`.
The harness now obtains the real user home with `pwd.getpwuid(os.getuid()).pw_dir`, deletes only its exact
UUID-named disposable defaults domain after terminating/waiting for the child, unlinks only that domain's
real-home preferences plist, then asserts both the daemon domain and plist are absent. A guard refuses
any identity outside `ai.padzy.tokei.perf.<32 lowercase hex digits>`, including the installed app's domain.
Success JSON is emitted only after cleanup succeeds; it adds `preferences_cleaned: true`.
Cleanup failure makes the run fail, including on an otherwise good measurement or an interrupted run.

The four original leftovers were positively reproduced before cleanup, then removed by exact identity:

```text
ai.padzy.tokei.perf.240b363a284c4c3da4a2c590f0b5678a
ai.padzy.tokei.perf.c82a6bc4b92f441483837d0a6a110b10
ai.padzy.tokei.perf.5f2ee343c09a4ace910592f8f9f9cf2d
ai.padzy.tokei.perf.711b213fc087496188432cc989a42c6d
```

No other preferences file was deleted. Logs: `fix-r1/preferences-red.log` and
`fix-r1/preferences-green.log`, under the existing `.scratch/speed/` proof folder.
A separate live regression test created one disposable test domain, executed the exact old script's
AST-extracted `finally` body, asserted its preferences were gone (red, child exit 1), then used the current
cleanup on the same domain and repeated the assertion (green). The test domain was removed too.

```sh
python3 .scratch/speed/fix-r1/preferences-regression.py
```

Actual output:

```text
RED S1 old finally: exit 1; benchmark preferences escaped the temporary tree
GREEN S1 current cleanup: daemon domain and real-home plist are absent
```

The three real benchmark runs below also verify cleanup. After all three completed, an independent
`defaults read` plus real-home plist check confirmed each run's domain was still absent (exit 1 from read,
no plist), so cleanup is not inferred only from a flag in the JSON.

### S2: opening catches up unwatched providers

Commit: `e7828c0`. Sync records the last completed refresh per provider. A hidden-to-visible transition
flushes pending file events, then refreshes any still-stale provider (older than 15 seconds), including
providers without watched folders. Duplicate visible notifications do not refetch already fresh data.
Test: `TargetedRefreshTests.testOpeningRefreshesUnwatchedProvidersAfterFifteenSeconds`, with the injected
clock and a counting Cursor provider without a watched folder.

Red on the reviewed code, then green in the final matrix:

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:20: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testOpeningRefreshesUnwatchedProvidersAfterFifteenSeconds] : XCTAssertEqual failed: ("1") is not equal to ("2") - opening must catch up providers without watched folders
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:23: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testOpeningRefreshesUnwatchedProvidersAfterFifteenSeconds] : XCTAssertEqual failed: ("1") is not equal to ("2") - a duplicate visibility notification must not refetch
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testOpeningRefreshesUnwatchedProvidersAfterFifteenSeconds]' failed (0.004 seconds).
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testOpeningRefreshesUnwatchedProvidersAfterFifteenSeconds]' passed (0.019 seconds).
```

### S3: preserve a pending batch when roots change

Commit: `e7828c0`. `refreshWatchPaths()` emits any pending batch before stopping/replacing the stream.
The raw paths survive; a removed or unknown root still conservatively maps to a full scan.
Test: `TargetedRefreshTests.testRootReplacementEmitsTheOtherProvidersPendingBatch` queues a Codex event,
adds a Claude root, and requires that the original Codex event is delivered.

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:40: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testRootReplacementEmitsTheOtherProvidersPendingBatch] : failed - Missing refresh checkpoint
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:41: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testRootReplacementEmitsTheOtherProvidersPendingBatch] : XCTAssertEqual failed: ("nil") is not equal to ("Optional(["/tmp/tokei-root-replacement/.codex/sessions/active.jsonl"])") - changing roots must preserve another provider's pending event
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testRootReplacementEmitsTheOtherProvidersPendingBatch]' failed (0.958 seconds).
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testRootReplacementEmitsTheOtherProvidersPendingBatch]' passed (0.001 seconds).
```

### S4: resolve roots for the batch

Commit: `e7828c0`. Resolve/classify the root list before iterating changed paths. The injected resolver
counts actual root-resolution calls for twelve changed files; each watched root must be resolved once.
Test: `TargetedRefreshTests.testWatchedRootsAreResolvedOnceForTheWholeEventBatch`.

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:54: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testWatchedRootsAreResolvedOnceForTheWholeEventBatch] : XCTAssertEqual failed: ("12") is not equal to ("1") - each root should be resolved once per batch, not once per changed file
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:55: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testWatchedRootsAreResolvedOnceForTheWholeEventBatch] : XCTAssertEqual failed: ("12") is not equal to ("1")
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testWatchedRootsAreResolvedOnceForTheWholeEventBatch]' failed (0.002 seconds).
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testWatchedRootsAreResolvedOnceForTheWholeEventBatch]' passed (0.001 seconds).
```

### S5: explicit manual Refresh retries failed Claude probes

Commit: `3129f37`. Added the separate `UserRefreshAwareProvider` capability; the frozen `UsageProvider`
requirements are unchanged. `DashboardViewModel.refresh()` carries explicit user intent through Sync's
coalescing queue. Immediately before that queued provider fetch, Claude clears its failed-probe cache.
Automatic file/periodic/visibility refreshes retain the cadence. The queue flag prevents an in-flight
automatic fetch from swallowing a manual retry.
Test: `QuotaSpawnCadenceTests.testManualRefreshRetriesClaudeImmediatelyAfterSignInIsFixed` drives the
real view-model refresh path with a fake Claude client: initial failure, recovered sign-in, automatic
refresh remains throttled, manual Refresh fetches immediately and reports authenticated.

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/ProviderTests/QuotaSpawnCadenceTests.swift:33: error: -[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testManualRefreshRetriesClaudeImmediatelyAfterSignInIsFixed] : XCTAssertEqual failed: ("1") is not equal to ("2") - manual Refresh must retry immediately after sign-in is fixed
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/ProviderTests/QuotaSpawnCadenceTests.swift:34: error: -[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testManualRefreshRetriesClaudeImmediatelyAfterSignInIsFixed] : XCTAssertEqual failed: ("Optional(AIUsageDashboardCore.AuthStatus.unknown)") is not equal to ("Optional(AIUsageDashboardCore.AuthStatus.authenticated)")
Test Case '-[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testManualRefreshRetriesClaudeImmediatelyAfterSignInIsFixed]' failed (0.089 seconds).
Test Case '-[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testManualRefreshRetriesClaudeImmediatelyAfterSignInIsFixed]' passed (0.077 seconds).
```

### S6: missing WAL, one fingerprint type, and preserved NOFOLLOW

Commit: `391a34a`. The duplicate `SQLiteSidecarCopy.Fingerprint` was removed; state and conversation
parsers now share `AntigravityConversationFiles.Fingerprint`, with main/WAL/journal stamps.
The fingerprint no longer does an exists-then-stat check. A sidecar lstat returning ENOENT is nil;
other errors still propagate. The deterministic regression deletes a real synthetic WAL immediately
before the stat, so it exercises the exact disappearing-file case.

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/AntigravityConversationFiles.swift:17: error: -[AIUsageDashboardCoreTests.RefreshCacheTests testWALDisappearingBetweenDiscoveryAndStatIsTreatedAsAbsent] : failed: caught error: "Error Domain=NSCocoaErrorDomain Code=256 "The file couldn’t be opened.""
Test Case '-[AIUsageDashboardCoreTests.RefreshCacheTests testWALDisappearingBetweenDiscoveryAndStatIsTreatedAsAbsent]' failed (0.091 seconds).
Test Case '-[AIUsageDashboardCoreTests.RefreshCacheTests testWALDisappearingBetweenDiscoveryAndStatIsTreatedAsAbsent]' passed (0.006 seconds).
```

**S6 symlink part declined, matches dev.** There was already a low-level NOFOLLOW invariant and an
existing test that requires a symlink source to be refused. Per t1d's follow-up, no new symlink following
or path resolution was added to the SQLite/state path. To prove the prior behavior rather than infer it,
compiled dev's exact state parser, snapshot copy, protobuf reader, warning model, C SQLite hardening code
and header into an isolated command test. A real regular fixture database is readable; the alias to the
same database is refused. The copied state/copy source bytes match dev's git blobs:

```text
AntigravityStateDBParser.swift c4d1256bfa864635adb070032e27e08f4f57f66e
SQLiteSidecarCopy.swift f6589bd11b222d018a4edb4486eed0a4cfd08ced
```

Exact check:

```sh
bash .scratch/speed/fix-r1/dev-alias/check.sh
```

```text
PASS S6 dev source: regular state database is readable; symlinked state database is refused (NOFOLLOW)
Test Case '-[AIUsageDashboardCoreTests.RefreshCacheTests testAntigravityStateAliasRemainsRejectedLikeDev]' passed (0.017 seconds).
Test Case '-[AIUsageDashboardCoreTests.AntigravityConversationParserTests testSQLiteSnapshotRefusesSymlinkSourceAndRemovesDestination]' passed (0.003 seconds).
```

The initially proposed alias-following assertion was replaced by the refusal assertion after t1d's
explicit instruction. It is not presented as a fixed regression or as a weakened existing test.

### S7: keep a nil-reset live reading live

Commit: `3129f37`. The live-cache predicate now accepts a missing reset time or a future reset time;
a reset at/before now still expires. The client uses the predicate before falling back to stale cache.
Test: `QuotaSpawnCadenceTests.testAntigravityLiveReadingWithoutResetTimeCanStayLiveBetweenAttempts`
covers nil, future and elapsed reset values. This is a cache-policy test; no vendor request was made.

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/ProviderTests/QuotaSpawnCadenceTests.swift:43: error: -[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testAntigravityLiveReadingWithoutResetTimeCanStayLiveBetweenAttempts] : XCTAssertTrue failed - an absent reset time must not downgrade a still-live reading
Test Case '-[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testAntigravityLiveReadingWithoutResetTimeCanStayLiveBetweenAttempts]' failed (0.730 seconds).
Test Case '-[AIUsageDashboardCoreTests.QuotaSpawnCadenceTests testAntigravityLiveReadingWithoutResetTimeCanStayLiveBetweenAttempts]' passed (0.001 seconds).
```

### S8: cancel a replaced file deadline

Commit: `e7828c0`. `scheduleFileRefresh` cancels the existing task before assigning its replacement.
The regression holds a provider fetch, interleaves two actor-reentrant drains and another file event,
then releases both drains. Before the fix, three sleepers survived at the same deadline; now exactly
one cancellable sleeper survives.

```text
/Users/abhayp/wt/lane1/AIUsageDashboard/Tests/SyncTests/TargetedRefreshTests.swift:89: error: -[AIUsageDashboardCoreTests.TargetedRefreshTests testReentrantDrainsKeepOneCancellableFileDeadline] : XCTAssertEqual failed: ("3") is not equal to ("1") - reentrant drains must cancel replaced deadlines
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testReentrantDrainsKeepOneCancellableFileDeadline]' failed (0.010 seconds).
Test Case '-[AIUsageDashboardCoreTests.TargetedRefreshTests testReentrantDrainsKeepOneCancellableFileDeadline]' passed (0.097 seconds).
```

### S9: 1.0% CPU budget and three-run medians

Commit: `b7d841d`. CPU budget is now 1.0%, per the accepted review change. A direct check confirms this
budget rejects the recorded 1.583% old-code baseline. The synthetic workload, sample duration, settle,
launch timing and footprint method are unchanged. Every run below uses the final committed Release build
from `b7d841d`; no code changed during/between the runs. The three runs were sequential.

Exact commands:

```sh
bash .scratch/speed/fix-r1/three-benchmarks.sh
# Runs the following command three times, retaining a separate output per run:
bash AIUsageDashboard/scripts/perf-bench.sh /Users/abhayp/Library/Developer/TokeiWork/dd-speed/Build/Products/Release/Tokei.app
```

Actual runner output:

```text
Run 1 exited 0
Run 2 exited 0
Run 3 exited 0
```

Each JSON line, in run order:

```json
{"average_cpu_percent": 0.458, "budget_passed": true, "cold_launch_to_window_ms": 558.9, "defaults_suite": "ai.padzy.tokei.perf.fb621c38dae84db9917b47409d7abb49", "peak_footprint_mb": 83.204, "physical_footprint_mb": 76.518, "preferences_cleaned": true, "provider_refreshes": {"antigravity": 0, "claude_code": 8, "cline": 0, "codex": 0, "copilot": 0, "cursor": 0, "gemini": 0, "opencode": 0}, "sample_seconds": 120.001, "synthetic_home_verified": true, "workload_version": 1, "writes": 120}
{"average_cpu_percent": 0.478, "budget_passed": true, "cold_launch_to_window_ms": 741.3, "defaults_suite": "ai.padzy.tokei.perf.e1f10462820045278ab04dfc97cb5a65", "peak_footprint_mb": 83.97, "physical_footprint_mb": 66.166, "preferences_cleaned": true, "provider_refreshes": {"antigravity": 0, "claude_code": 8, "cline": 0, "codex": 0, "copilot": 0, "cursor": 0, "gemini": 0, "opencode": 0}, "sample_seconds": 120.005, "synthetic_home_verified": true, "workload_version": 1, "writes": 120}
{"average_cpu_percent": 0.482, "budget_passed": true, "cold_launch_to_window_ms": 536.9, "defaults_suite": "ai.padzy.tokei.perf.189985a6dc4748efa72f23fd1b54ce65", "peak_footprint_mb": 82.517, "physical_footprint_mb": 66.898, "preferences_cleaned": true, "provider_refreshes": {"antigravity": 0, "claude_code": 8, "cline": 0, "codex": 0, "copilot": 0, "cursor": 0, "gemini": 0, "opencode": 0}, "sample_seconds": 120.005, "synthetic_home_verified": true, "workload_version": 1, "writes": 120}
```

| Run | Average CPU | Mean physical footprint | Peak physical footprint | Cold first window | Cleanup |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 | 0.458% | 76.518 MB | 83.204 MB | 558.9 ms | Verified absent |
| 2 | 0.478% | 66.166 MB | 83.970 MB | 741.3 ms | Verified absent |
| 3 | 0.482% | 66.898 MB | 82.517 MB | 536.9 ms | Verified absent |

**Median CPU: 0.478%. Median mean physical footprint: 66.898 MB.**
Median CPU is 69.80% below the original measured baseline of 1.583%. The final footprint median
is reported with all three samples; the original baseline was only one run, so this is not a strong
memory-improvement or peak-memory claim. Every run is under the CPU, footprint and first-window budgets.

### Final checks, commits and cleanup

Before the fixes, the three touched classes ran 18 tests with 12 failures (one unexpected thrown
missing-WAL error), recorded in `.scratch/speed/fix-r1/red.log`. This was a built/running test failure,
not a compilation failure. Only additive test seams were present when it ran. The red command was:

```sh
cd AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/TokeiWork/dd-speed -only-testing:AIUsageDashboardCoreTests/TargetedRefreshTests -only-testing:AIUsageDashboardCoreTests/QuotaSpawnCadenceTests -only-testing:AIUsageDashboardCoreTests/RefreshCacheTests test
```

Final same 37-class parser/sync/analytics/quota matrix as Command F above, including the added methods:

```sh
bash .scratch/speed/run-final-tests.sh
```

Actual output (`.scratch/speed/fix-r1/final-tests.log`):

```text
Executed 301 tests, with 1 test skipped and 0 failures (0 unexpected) in 15.892 (15.998) seconds
** TEST SUCCEEDED **
```

The skip remains the opt-in external Copilot Python oracle. Existing tests were not weakened.
The final Release command and ad-hoc settings are the same as AC1 above; output in
`.scratch/speed/fix-r1/build.log` ends with `** BUILD SUCCEEDED **`. No new source warnings versus the
measurement baseline. Static signing verification again passed nine nested code items; its non-isolated
launch assertion was intentionally skipped because the three isolated live runs supply the launch proof.

```sh
BASE_REF=dev bash .claude/gates/run-all.sh fast
```

Actual output (`.scratch/speed/fix-r1/fast-gates.log`):

```text
PASS  preflight
PASS  no-secret
PASS  no-large-artifact
PASS  no-uncommitted
PASS  cli-version-sync
PASS  format
PASS  lint
[run-all] ALL GATES GREEN
```

Format/lint remain explicit allowed skips because the tools are unavailable. Security scan, cross-model
review, repo-wide finish gates and work log still belong to the orchestrator under worker rule 4.
No push, merge, PR, deploy or new dependency. Worktree is clean. No benchmark app process, watcher,
dev server or worker check terminal remains. All four original domains and all three final-run domains
were verified absent by exact identity. The temporary preferences regression domain was also removed.

`git log --oneline 4a23297..HEAD`:

```text
b7d841d Clean benchmark preferences and guard the lower CPU budget
3129f37 Retry failed Claude probes on an explicit user refresh
391a34a Share SQLite fingerprints and tolerate disappearing WAL files
e7828c0 Catch up visible providers and preserve pending watcher work
```
