STATUS: READY

# T07 security hardening

Completed the four specified hardening items. Final independent verdict: PASS on code commit `54c3224`. The detached test mirror has been removed; no push, merge or PR.

## Scope and source

First command was the requested checksum check:

```text
shasum -a 256 ~/.herd/runs/20261029-0458-32/tasks/t07.brief.md
4f7249a0ee4abd737344ce5ad31da1a810aa1c089f9f87f48832128d43cfa6ad
```

After reading the matching brief, ran its first command (`cd /Users/abhayp/Downloads/Projects/tokei-worktrees/2026-10-29-sec-hardening`). Confirmed the clean `patch/2026-10-29/sec-hardening` branch at `efa815b0c0cb2d03f6838224d2de39084d5e7e30`. Read the requested L1/L2/L5/L6 source-review sections and relevant code/callers. No credentials, dependency additions, app launches, provider calls, push, merge or PR.

## Test setup

```sh
git worktree add ~/Library/Developer/TokeiWork/t07 HEAD --detach
cd ~/Library/Developer/TokeiWork/t07/AIUsageDashboard
xcodegen generate
```

The mirror started at the base commit. Copied only this lane's changed source/tests into it for red/green runs; byte comparison confirms the final mirror matches the implementation. Generated project files and DerivedData stayed outside Downloads. Logs and probes stayed in this worktree's ignored `.scratch/t07/`.

All test runs used this exact command prefix followed by the selectors shown below:

```sh
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore \
  -destination 'platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/TokeiDerivedData/t07" test
```

Selectors have the prefix `-only-testing:AIUsageDashboardCoreTests/`.

## L1: permission changes do not follow child links

Changed both chmod sites to `fchmodat(AT_FDCWD, path, mode, AT_SYMLINK_NOFOLLOW)`, with checked failures. Kept the existing intentional root-link resolution and private atomic-write path. Updated the failing-child fixture to produce a real missing-file failure after cached metadata inspection, since chmod no longer runs through FileManager.

- Before command: test prefix + `SecureFileWriterReviewTests` selector.
- Before output: 4 tests, 2 expected assertion failures. A swapped child changed the outside file from 0644 to 0600; a swapped directory changed its outside directory from 0755 to 0700. The runner stalled after printing the completed failing suite and was terminated after about six minutes (exit 143); the assertion output is retained in `l1-red.log`.
- After command: test prefix + selectors `SecureFileWriterReviewTests`, `UsageStoreWriteTests`, `AntigravityConversationParserTests`, `CooldownStoreTests`, `UsageHTTPSessionTests`.
- After output: L1's 4 tests and all 7 storage-write tests passed. The same run intentionally reproduced the other unfixed findings (overall exit 65). Evidence: `l1-green-others-red.log`.
- Constraint: deterministic cached-metadata link swaps test the timing gap, for both files and directories. The outside file's bytes are also covered by the existing ordinary-link test.

## L2: defensive SQLite connections and ordinary history tables

Added a fixed-signature C adapter because Swift cannot call SQLite's variadic configuration interface. After each of the three opens, require DEFENSIVE=1 and TRUSTED_SCHEMA=0 before proceeding; configuration failure closes the handles through the existing failure paths. The hardener also removes all virtual-table modules before any query. The Antigravity table check accepts only the parsed `table` type from `PRAGMA main.table_list`, independent of raw SQL spacing; the live source opens with `SQLITE_OPEN_NOFOLLOW`. SQLite documents the parsed type column in its [table_list reference](https://www.sqlite.org/pragma.html#pragma_table_list).

- Before command: test prefix + `AntigravityConversationParserTests` (in `l1-green-others-red.log`).
- Before output: the empty FTS virtual `steps` table was accepted without an unreadable-history warning. Direct reading did not throw. A linked source was also copied and left a snapshot. Both new tests failed, four assertions total.
- After command: test prefix + selectors `AntigravityConversationParserTests`, `CursorStateDBParserTests`, `OpencodeStoreParserTests`, `CursorCopyCacheTests`.
- Initial green output: **36 passed, 0 failed, 0 skipped; exit 0** (`l2-final.log`). This includes actual SQLite backup, WAL changes, rollback-journal consistency, private snapshot modes, and the linked-source cleanup test. The virtual-table test ran with a system FTS module; it was not skipped.
- Compatibility investigation: the first protected run rejected Cursor/opencode temporary paths. A path probe showed `/var` + NOFOLLOW returns SQLite 14, canonical `/private/var` returns 0, and a linked filename returns 14. A Foundation-only parent resolution still returned `/var`, and a second run failed. A Swift checkpoint probe confirmed Foundation's resolved-parent path still returned 14 while POSIX `realpath` returned 0. The final helper applies `realpath` to the parent only and preserves the filename. Existing normal-file snapshot tests and the new linked-file test now pass together.
- Build correction: the initial C-adapter revision omitted the header defining `NULL`; included `<stddef.h>` and rebuilt. No compile errors remain. Probe and failed-run evidence remains in `.scratch/t07/`.

### Review correction: alternate schema spacing

The independent reviewer reproduced a bypass of the source review's suggested SQL-prefix filter: `CREATE  VIRTUAL TABLE` still parses as virtual, but does not match `CREATE VIRTUAL%`. Replaced the prefix filter with `PRAGMA main.table_list('<hardcoded name>')` and accept only its parsed `table` type. Direct PRAGMA also avoids resolving a user-created table with the same name as a bare table-valued pragma function.

- Regression command before the correction: test prefix + `AntigravityConversationParserTests/testVirtualStepsWithNonCanonicalSchemaIsReportedAsUnreadable`.
- Red output: **1 test, 2 expected failures; exit 65** (`l2-tab-red.log`). A planted `CREATE\tVIRTUAL` schema was read without throwing and without the unreadable-history warning. The fixture patches one space to one tab after SQLite closes, preserving page sizes.
- The first fixture attempt used `writable_schema`; Apple's linked SQLite rejected modifying sqlite_master. That setup failure is not counted as red proof (`l2-spacing-red.log`; its stalled runner was terminated, exit 143). The byte-patched fixture above reproduces the intended defect.
- Green command: the same four SQLite class selectors listed above.
- Green output: **37 passed, 0 failed, 0 skipped; exit 0** (`l2-delta-green.log`), including 18 Antigravity and 19 shared snapshot-caller tests.
- `swiftlint lint --strict` on the two delta files: **0 violations, exit 0** (`l2-delta-lint.log`).

### Final review correction: do not start modules during metadata inspection

Round 2 resolved the schema-spacing bypass but proved that SQLite's table-list metadata inspection can start unrelated virtual-table modules while discovering column counts. The first metadata call read an unrelated FTS decoy's configuration even though Tokei never queried that table.

The existing C connection-hardening boundary now also checks `sqlite3_drop_modules(database, NULL)`. All three named connections remove virtual modules before any SQL; raw-page backups and ordinary-table readers need none of them. This prevents module startup while preserving the parsed-type rejection. No test-only hook was added to production.

- Before command: test prefix + `AntigravitySQLiteModuleTests`.
- Red output: **1 test, 1 expected failure; exit 65** (`l2-modules-trace-red.log`). Tracing the actual production hardener's connection recorded `SELECT k, v FROM 'main'.'decoy_config'` during table metadata inspection.
- After command: test prefix + selectors `AntigravitySQLiteModuleTests`, `AntigravityConversationParserTests`, `CursorStateDBParserTests`, `OpencodeStoreParserTests`, `CursorCopyCacheTests`.
- Green output: **38 passed, 0 failed, 0 skipped; exit 0** (`l2-modules-green.log`). The new test asserts the trace is active, rejects any decoy query, and verifies the real Antigravity reader still accepts the ordinary-table fixture.
- First test-instrumentation attempt: Apple's SQLite returned SQLITE_MISUSE for process-global auto-extension registration. Its SDK header explicitly says those extensions are unsupported on Apple platforms. That setup failure is not counted as red proof (`l2-modules-red.log`). The final test directly instruments the existing C hardening boundary with supported per-connection tracing; no auto-extension or unsafe cast remains.
- `swiftlint lint --strict` on the new test: **0 violations, exit 0** (`l2-modules-lint.log`).

## L5: cap a persisted cooldown when reading

Decode the existing format, then return `min(until, now() + maxCooldownInterval)`.

- Before command: test prefix + `CooldownStoreTests` (in `l1-green-others-red.log`).
- Before output: a planted 2099 date was returned unchanged and remained active past the configured 90-second maximum; both assertions failed.
- After command: test prefix + selectors `CooldownStoreTests`, `UsageHTTPSessionTests`, `GeminiUsageClientTests`, `GeminiCooldownMessageTests`.
- After output: **34 passed, 0 failed; exit 0** (`network-final.log`); CooldownStore accounts for 14 tests.
- Shared-callers command: test prefix + selectors `ClaudeUsageClientImplTests`, `CursorUsageClientImplTests`, `CursorUsageClientRetryTests`.
- Shared-callers output: **18 passed, 0 failed; exit 0** (`network-callers.log`). The earlier command accidentally selected nonexistent Claude/Cursor class names; these corrected selectors explicitly executed 7 + 8 + 3 tests.

## L6: require the same HTTPS port on redirects

Added `original.port == destination.port` to the existing HTTPS/same-host policy.

- Before command: test prefix + `UsageHTTPSessionTests` (in `l1-green-others-red.log`).
- Before output: default-port to 8443 and 8443 to 9443 each followed the redirect and made a second request; both assertions failed.
- After command: the network command under L5.
- After output: all **4 HTTP-session tests passed**. Cross-host and HTTPS downgrade rejection still pass; same-host redirects with the same default or explicit 8443 port still proceed. These tests drive URLSession with fixture requests and a local URLProtocol, without external traffic or real credentials.

## Strict lint and security scan

Command: `swiftlint lint --strict --config AIUsageDashboard/.swiftlint.yml --reporter json` on all ten touched Swift files in the mirror; compared against the nine existing files extracted from base `efa815b` with the same configuration; the new module test also has zero violations on its own.

Output: both baseline and final exit 2 with exactly two violations; **no new file/rule pairs**:

- `CooldownStore.swift`: existing `line_length` at line 50, 163 characters, unchanged.
- `SQLiteSidecarCopy.swift`: existing `function_body_length` at line 30, baseline 77 / final 80 lines. No new complexity, test-type length or other violations.

Lint data: `.scratch/t07/lint-baseline.json`, `lint-final.json`. Baseline comparison and mirror-byte verification ran successfully. Existing Swift concurrency warnings in provider constructors are visible in the original baseline build as well; they were outside this task. Xcode also prints App Intents metadata and launch-diagnostics tool warnings.

Command: `~/agent-kit/bin/secscan /Users/abhayp/Downloads/Projects/tokei-worktrees/2026-10-29-sec-hardening`.

```text
VERDICT: PASS
head 54c3224547e3
FLAG lines: none
GAP lines: none
```

The pre-commit hooks passed the secret and large-artifact gates on every implementation commit. Their existing formatting gate reports SKIP because swiftformat is not installed; strict SwiftLint was run separately. No gate was bypassed.

## Independent review

Round 1: Claude Opus 5.5, confirmed from the running client's banner and reviewer identity, independently ran all **99 focused tests: 99 passed, 0 failed, 0 skipped; exit 0** (`review-validation.log`). The reviewer also built the app target offline in the mirror, with cached Sparkle and signing disabled: **BUILD SUCCEEDED, exit 0** (`review-app-build.log`); no launch/copy. Round-one verdict: CHANGES for S1, the schema-spacing bypass. The author reproduced S1 in a failing regression and committed the parsed-type correction.

Round 2: the same reviewer independently reran the **18 Antigravity tests: 18 passed, 0 failed, 0 skipped; exit 0** (`review-delta-validation.log`). S1 was resolved. Verdict remained CHANGES for S5: metadata inspection starts virtual modules. The author reproduced this in a failing trace test, then added module removal at the existing C boundary.

Round 3: **VERDICT: PASS** on `54c3224547e382d6d5c16fe772466e74f33a48c4`. The reviewer independently reran the two affected classes: **19 passed, 0 failed, 0 skipped; exit 0** (`review-final-validation.log`). S5 was confirmed resolved. Final verdict and evidence: `.scratch/t07/review-final.result.md`. No blocker or required finding remains open.

There are **101 distinct passing tests across the scoped runs**, counted by unique passing test names in the independent 99-test run and the final 38-test SQLite run. This is not a claim of one 101-test run or of the full suite. The final changed SQLite paths passed 38 author-run tests and 19 independent tests. Review artifacts remain in this worktree's ignored `.scratch/t07/`. No live app/provider proof is claimed.

Diff size: the original review covered 11 files, +164/−20; the final implementation is 12 files, +238/−22 (`git diff --shortstat efa815b HEAD -- AIUsageDashboard`). Both expansions add demonstrated security corrections and failing-then-passing tests. One final nit was declined: the module trace test repeats the private metadata SQL; production gained no test-only access hook.

Ledger:

- S1: fixed in `5353517`; independently confirmed resolved in round 2.
- S5: fixed in `54c3224`; independently confirmed resolved and approved in round 3.
- S2: retained as a limitation of the exact T07 formula. With a far-future planted file and an advancing clock, the cap moves at every read; it does **not** guarantee the gate expires after one maximum interval. The reviewer's real-source Swift probe showed it active at 0, 24 and 8760 hours (`review-probe-cooldown.log`, exit 0). Changing to a persisted fixed cap or invalidating such files would change the requested policy, so that was not added.
- S3: reading-only follow-up, outside the two requested chmod replacements: stale directory metadata may still cause traversal into a replaced directory link. The two entry permission syscalls do not follow links; traversal safety beyond them remains unproven.
- S4: an implicit HTTPS port and an explicit 443 are treated as different by the requested `URL.port` equality rule and are refused. This fails closed; no normalization was added.

Usage for the reviewer was not exposed. One reviewer, at most three rounds; no fourth round will be started.

## Files touched

- `AIUsageDashboard/AIUsageDashboardApp/Core/Storage/SecureFileWriter.swift`
- `AIUsageDashboard/Tests/StorageTests/SecureFileWriterReviewTests.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/AIUsageDashboardCore.h`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/SQLiteConfiguration.c`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/SQLiteSidecarCopy.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Parsing/AntigravityConversationDatabase.swift`
- `AIUsageDashboard/Tests/ParserTests/AntigravityConversationParserTests.swift`
- `AIUsageDashboard/Tests/ParserTests/AntigravitySQLiteModuleTests.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Network/CooldownStore.swift`
- `AIUsageDashboard/Tests/ClaudeUsageTests/CooldownStoreTests.swift`
- `AIUsageDashboard/AIUsageDashboardApp/Core/Network/UsageHTTPSession.swift`
- `AIUsageDashboard/Tests/ProviderTests/UsageHTTPSessionTests.swift`
- `tasks/reports/2026-10-29-sec-hardening.result.md`

## Commits, limits and rollback

- `9a9b2a8`: L1.
- `a7d5d8d`: L2.
- `7c7246e`: L5.
- `f91c8c2`: L6.
- `5353517`: L2 schema-spacing correction and regression.
- `54c3224`: L2 module-startup correction and trace regression.

Local fixture/filesystem/URLSession proof only. No full suite, installed-app launch, real vendor, release signing or distribution check. No history rewriting and no unrelated review findings addressed. Rollback is to revert these six implementation commits in reverse order; no persisted format changed.

An initial `xcodegen generate` was mistakenly invoked at the source worktree root and returned “No project spec found”; corrected it to the required mirror's AIUsageDashboard directory, where generation succeeded. No project was generated inside Downloads.

Mirror cleanup command: `git worktree remove --force /Users/abhayp/Library/Developer/TokeiWork/t07` → exit 0. Before removal, verified the detached base identity, exactly the 12 task-owned changes, and byte equality with committed source. After removal, the directory and worktree registration are absent. Other worktrees were preserved.

Final code and review artifacts were stable for over 60 seconds before collection. This report is committed separately from the six implementation commits. Waits on: nobody.
