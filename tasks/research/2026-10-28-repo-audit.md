STATUS: READY

# Tokei repo audit, 2026-10-28 (read-only)

Scope: branch `dev` @ 68d10a6, version 0.10.0. Nothing in the repo was edited except this file. No full test run, no `TOKEI_REAL_LOGS`. No credential file, Keychain item or `.env` was read. Data files under Application Support were inspected by key names, counts and sizes only. Two throwaway experiments ran in the scratchpad (file modes, symlink behaviour) and were deleted.

Evidence labels: "measured" = I ran it on this Mac; "code" = read in source; "inferred" = reasoned, not run.

## 0. Findings ranked by user impact

1. **Cursor's 157 MB state database is copied on every refresh.** Measured. `CursorProvider.fetchSnapshot` (CursorProvider.swift:51) calls `CursorStateDBParser.parse` (CursorStateDBParser.swift:78-95), which runs a full SQLite online backup of `state.vscdb` (156,680,192 B) into a temp dir each time, with no mtime/size stamp check. `OpencodeStoreParser` already has such a stamp cache (OpencodeStoreParser.swift:63-67); Cursor does not. I watched the user temp dir for 50 s: `TokeiCursorStateDB-*` appeared at t=2.4 s, 22.1 s and 42.7 s (one caught mid-copy at 9 MB). A copy took 0.31 s wall / 0.2 s CPU with `sqlite3 .backup`. At the observed 20 s refresh cadence that is up to ~28 GB/h of temp writes during active work; at the 300 s idle timer (SyncEngine.swift:103) it is ~1.9 GB/h, ~45 GB/day. Fix: skip the copy when db+wal mtime/size are unchanged (reuse the cached `OfflineState`).
2. **Whole-file rewrites on every refresh, changed or not.** Measured: `agent-snapshot.json` and `usage-store.json` were both rewritten at t=6.0, 24.7, 44.4, 65.5 s in a 75 s window (~20 s cadence while agent sessions were writing logs). `SyncEngine.performRefresh` (SyncEngine.swift:77-87) always calls `store.save` (rewrites 68 KB, UsageStore.swift:41-86) and `agentSnapshotWriter.write` (7.5 KB, AgentSnapshotWriter.swift:207-210). `generatedAt` changes each time, so file mtime says nothing about real change. `quota-series.json` (2.4 MB, pretty-printed) is fully rewritten on every changed reading (QuotaSeriesStore.swift:121-139); the busiest observed day had 1,014 new samples, i.e. up to ~2.4 GB written that day. Fix: skip the write when the payload minus `generatedAt` is identical; encode compact (-30% for the series, -38% for the snapshot); move the series to append-only JSONL or SQLite.
3. **Quota history is account-blind, so multi-account pace baselines are mixed.** Code: series key is `(providerID, windowType, bucketKey)` (QuotaSeriesStore.swift:117-119); `QuotaSample` has no account field (QuotaSample.swift:3-12); `append` feeds provider-level windows, which for Claude are the headline account's (best headroom) windows (AgentSnapshotWriter.swift:100-120 shows the same projection). Measured symptom in the real file: `resetAt` moves backwards 269 times in the 2,000-sample `session` series, 332 in `weekly_all`, 317 in `weekly_scoped:Fable`; this machine has two Claude accounts with different reset times. The only reader, `loadPaceBaselines` (UI/MenuBar/MenuBarView.swift:383-400), picks "same point last period" from this series, so the menu-bar pace notch can compare account A now against account B last week. Codex shows 206 backwards moves with one account (live probe vs log-derived window alternating, inferred), same root cause class. Fix: add `accountID` to the sample and the series key.
4. **Cold start re-parses ~6.2 GB of logs every launch.** Code: Claude/Codex incremental caches are in-memory only (ClaudeJSONLParser.swift:24, CodexJSONLParser.swift:41); the whole Claude cache is also dropped at each month rollover (ClaudeJSONLParser.swift:56-62). Measured corpus: 4,412 `.jsonl` files (46 over 20 MB, largest 70 MB), `~/.claude/projects` 2.8 GB, `~/.claude-account-1/projects` 2.8 GB, `~/.codex/sessions` 603 MB. Prior audit (tasks/todo.md) recorded cold CPU 3:31 min after the 0.9.0 diet. Running app now: RSS ~320 MB. Fix: persist `{path, mtime, size, fileID, byteOffset, aggregate}` per file.
5. **Gemini calls Google on every refresh with no opt-in, cache or cooldown.** Code: `GeminiProvider.fetchSnapshot` (GeminiProvider.swift:40-47) fires whenever `~/.gemini/oauth_creds.json` exists; `GeminiUsageClientImpl` (GeminiUsageClient.swift:136-160) reads the Gemini CLI's access token and POSTs `loadCodeAssist` then `retrieveUserQuota` (2 requests per refresh, ~every 20 s when active). Claude, Cursor and Antigravity network paths are default-off toggles and Claude has a 10-minute fresh cache (ClaudeUsageClient.swift:570); Gemini has none of that. Also Codex is default-on: `liveQuotaDefaults = [codexLiveQuotaEnabled: true]` (CodexProvider.swift:5) spawns `codex app-server` per account every 300 s (CodexProvider.swift:132), and that child talks to OpenAI with the user's login. README frames network access as opt-in; these two are not.
6. **The agent snapshot and MCP `get_usage` hand local paths to the model.** Measured: `agent-snapshot.json` contains `accounts[].id` and `selector.env` with absolute profile paths (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, containing the macOS username). `docs/08-agent-snapshot-schema.md` §1 says this is allowed; the in-code invariant says the opposite ("ONLY percentages, token counts, and timestamps", AgentSnapshot.swift:90-93) and `AgentAccount.id` is documented as a path (AgentSnapshot.swift:191). No emails, tokens or `@` found in any data file (measured). Fix: reconcile the comment with the doc; keep the selector only on `recommendation.target`; stop emitting `accounts[].id` (it is already marked legacy).
7. **File permissions are inconsistent and the one fix only covers fresh installs.** See section 4.
8. **Test leak in `~/Library/Preferences`: 3,710 empty plists** named `ai.AIUsageDashboard.NotificationEngineTests.<UUID>.plist` (42 B each, 14 MB on disk, newest 20 Oct). Cause: `NotificationEngineTests.setUp` creates a new UUID suite per test method (NotificationEngineTests.swift:11-14); `removePersistentDomain` in tearDown (line 18) empties the domain but leaves the file. Rung-1 fix: one fixed suite name per class, or delete the plist in tearDown.
9. **Stale GitHub issues and 12 extra worktrees.** Issues #48, #49, #55, #57, #59 are shipped in code but open (section 1). Worktrees under `~/Downloads/Projects/tokei-worktrees` use 803 MB; every branch is already merged into `dev` (`git branch --merged dev`). Removal needs the owner's yes.
10. **Product: no launch-at-login, export, per-provider thresholds, session drill-down; widget is an unbuilt placeholder.** Section 6.
11. Lint gate fails: 348 strict violations (section 2). No `swiftformat`, so the format gate is skipped.
12. MCP: single hard-coded protocol revision, no tool annotations, no filters, pretty-printed payloads (section 5).

## 1. Repo state

`git status --short` (the 5 pre-existing deletions, left alone):
```
 D tasks/brand/tokei-brand-sheet.png
 D tasks/brand/tokei-icon-master.png
 D tasks/handoff/ref-drill.png
 D tasks/handoff/ref-overview.png
 D tasks/handoff/ref-value.png
```
`git log --oneline -10`: 68d10a6 merge(fix/2026-10-20/hidden-launch-sync) · 2a01936 fix(app): seed first-run visibility before the first sync · f8e7ec2 fix(app): start syncing at launch · 820cb80 docs(checkpoint): 0.10.0 shipped · 4b0b245 release(0.10.0): publish the signed appcast · fd3e205 Release 0.10.0 · 89aa447 docs(release) 0.10.0 · 21aa50e perf(claude): bucket each record's day and hour once · 6f5e9dd build(release): fail before notarizing when sign_update is missing · 920a1ae test(codex): stop the process-tree test racing its fixture.

`git worktree list` (13 entries, 12 besides the main checkout):
- main checkout `/Users/abhayp/Downloads/Projects/AI_tracker` [dev]
- `~/.herdr/worktrees/AI_tracker/herd-20260727-2005-49-t03` [herd/20260727-2005-49/t03], 7 MB, clean
- 11 under `~/Downloads/Projects/tokei-worktrees/`: 2026-07-22 codex-parser-cache, cursor-cooldown-scope, gemini-signin-docs, plan-cost-presets; 2026-07-24 agent-snapshot-mcp, copilot-connector, robustness-core; 2026-07-27 cli-tests-docs, core-client-hygiene, release-signing, route-policy. Total 803 MB. Each shows the same 5 PNG deletions as the main checkout (cause not investigated).

`gh issue list --state open --limit 50`: gh is authenticated; 37 open. Highest priority: P0 #1 secure store access, #2 Claude connector, #10 website; P1 #4, #12 onboarding, #14 credential policy, #15 Padzy compliance, #16 widget rebuild, #17 app identity, #18 crash reporting, #23 Maxxer score, #36 pace notch, #37 route chip, #59 CLI/MCP tests; P2 #5, #6, #19, #26, #41, #48, #49, #51, #55, #57, #60, #61, #62, #63; P3/other #24, #25, #27, #42, #52, #53, #54.

Issues that the code already satisfies (verified in source or git):
- #48 per-series retention: `defaultPerSeriesRetentionLimit = 2_000` (QuotaSeriesStore.swift:14), commit 0f3f11a, merge 52cf3ba.
- #49 Cursor cooldown scoped per cookie: same merge 52cf3ba; `CursorSession.identityHash` (CursorSession.swift:58).
- #55 Codex incremental parse: `fileCache` + `byteOffset` (CodexJSONLParser.swift:41-136), commit 99b38d8, merge 9696ed9.
- #57 CLI + MCP: shipped in 0.7.0 (d34ac9a), now at 0.10.0.
- #59 CLI/MCP tests: `Tests/CLITests` has 9 files (commit fae11d0). Open as P1 bug.
- #36 pace marker: `QuotaPace` + `PaceLine`/`PaceMark` (PaceViews.swift:46,68). #37 route chip: ProviderDetailView.swift:162.
- Partial: #19 (Core slice merged in d4023e3: Cline cap, atomic UsageStore writes), #61 (the `cli-version-sync` gate fails on drift; the string is still hand-kept at main.swift:15).

## 2. TODOs, lint, format

`rg 'TODO|FIXME|HACK|XXX'` over App + CLI: 2 lines, 1 real:
- Core/Maxxer/PlanPreset.swift:29 `TODO(#51)` (Tokei models one claude_code provider, so plan detection is not attempted).
- Core/Network/CursorSession.swift:37 is a doc example (`user_XXXX`), not a marker.

`bash .claude/gates/lint.sh`: FAIL, 348 violations under `--strict` (config `AIUsageDashboard/.swiftlint.yml`). By rule: line_length 100, trailing_comma 65, identifier_name 64, type_body_length 18, function_body_length 15, file_length 15, large_tuple 11, implicit_optional_initialization 11, multiple_closures_with_trailing_closure 9, static_over_final_class 8, trailing_whitespace 6, trailing_newline 5. Worst offenders: CodexJSONLParser.swift (1,151 lines; one 180-line function at :50, complexity 18 at :914, 8-parameter function at :524), OpencodeStoreParser.swift (470 lines), ClaudeJSONLParser.swift (350-line actor body), DashboardViewModel.swift, NotificationEngine.swift. tasks/todo.md recorded 360 before this; the count is roughly flat.

`bash .claude/gates/format.sh`: SKIP, `swiftformat` not installed. `swift-format` is also absent.

Dead code found while reading: `Core/Utilization/UtilizationCache.swift` (145 lines, header says "not yet wired", only its test calls it); `Core/Security/Keychain.swift` (64 lines, no production caller, yet issue #14 asks to harden it); `UsageStore.dailyHistory(providerID:)` (UsageStore.swift:128, no caller); `AIUsageDashboardWidgets/` (not in project.yml or the generated pbxproj).

## 3. File efficiency

### 3.1 What Tokei writes (`~/Library/Application Support/AIUsageDashboard/`, measured 21:45)

| File | Size | Written by | Rule |
|---|---|---|---|
| quota-series.json | 2,415,237 B (8,938 samples, 10 series) | QuotaSeriesStore.swift:121 | count-capped, see 3.2 |
| usage-store.json | 67,866 B (was 49,908 B at 13:52 on 20 Oct; app relaunched 21:41 today) | UsageStore.swift:41 | per-provider latest snapshot overwritten; `dailyUsages` never pruned |
| agent-snapshot.json | 7,476 B | AgentSnapshotWriter.swift:207 | overwritten each refresh |
| claude-usage-cache{,-a337dfc1,-aa058b15}.json | 1,163 / 809 / 418 B | ClaudeUsageClient.swift:447-451 | per account, `.atomic`, 2 h max-stale |
| claude-usage-cooldown{,-…}.json | 38 B x3 | CooldownStore.swift:73-80 | `{until}`, max 1 h |
| antigravity-quota-cache.json | 1,906 B (raw RPC payload, base64) | AntigravityQuotaClient.swift:142-150 | overwritten on success, 2 h max-stale |
| `~/Library/Caches/AIUsageDashboard/litellm-model-prices.json` | 639,461 B | PricingService.swift:136-150 | daily refresh |
| `~/Library/Caches/ai.padzy.tokei/Cache.db` | 3 cached responses, ~4 KB data | URLSession.shared URLCache | see 4.5 |

Orphans: `claude-usage-cache-aa058b15.json` (30 Jul) and `claude-usage-cooldown-aa058b15.json` (30 Aug) belong to an account no longer in use; nothing deletes per-account files (code: only `CooldownStore.remove` for migration).

### 3.2 `quota-series.json`

- Writer: `QuotaSeriesStore.append` (QuotaSeriesStore.swift:45-67), called from `SyncEngine.performRefresh` (SyncEngine.swift:80). A sample is added only when the reading differs from the last one in its series (`hasSameReading`, QuotaSample.swift:58-64), so the write rate follows reading changes, not syncs.
- Retention: count only. 2,000 per series, 20,000 global backstop (lines 9, 14, 98-119). No time-based pruning and no age cutoff.
- Atomic: yes. Writes `.<name>.<uuid>.tmp` then `replaceItemAt`/`moveItem` (lines 121-139). Failure is swallowed silently (`catch` removes the tmp file, no log).
- Rewrites the whole file each time. Encoding is `.prettyPrinted + .sortedKeys` with ISO-8601 dates (line 144): 270 B/sample on disk vs 188 B compact (1,681,919 B measured by re-encoding with python).
- Load: once, lazily (line 80-89); `samples.last(where:)` is an O(n) scan per window per sync (line 54), negligible at the 20,000 cap.
- Current fill (measured): `claude_code session` 2,000 (full), `claude_code weekly_all` 2,000 (full), `claude_code perModel weekly_scoped:Fable` 2,000 (full), `codex weekly` 1,335, `cursor monthly` 1,093, `codex session` 474, antigravity 11+11+9+3. First sample 2026-07-10, last 2026-10-20. Samples exist on only 34 distinct days (median 123/day, max 1,014/day).
- Growth estimate: the three full series are now churning (oldest out, newest in). The other three active series will fill within roughly 1 to 3 months at the median rate. Plateau with today's series set is ~12,000 samples = ~3.3 MB pretty (2.3 MB compact). Hard ceiling is 20,000 x 270 B = 5.4 MB. Each new model-scoped Claude bucket (like `weekly_scoped:Fable`) adds up to ~540 KB. So the file grows by about 0.9 MB over the next few months, then stops.
- Write cost, not size, is the issue: a 2.4 MB rewrite per changed reading, 123/day median = ~300 MB/day, 1,014/day peak = ~2.4 GB/day.
- Depth limit: 2,000 samples cover ~88 days for the Claude series at this user's activity but only ~4 to 20 days for a heavy user (at 100 to 500 changes/day), so a long-range history chart cannot rely on it.

### 3.3 `usage-store.json`

- Writer: `UsageStore.save(snapshots:)` (UsageStore.swift:109-116) from every refresh (SyncEngine.swift:79). Atomic: `.atomic` tmp file + `replaceItemAt` (lines 64-81). Plain `JSONEncoder()` (compact, no pretty print); dates are Double reference-date seconds; `[Date: Int]` dictionaries are encoded as flat key/value arrays (this is why the file looks unreadable).
- Size breakdown (measured): claude `dailyModelUsage` 10.9 KB (current month only), cursor `hourlyTotals` 3.7 KB, claude accounts 3.4 KB, claude `hourlyTotals` 3.3 KB, codex `dailyModelUsage` 3.1 KB, `dailyUsages` 128 entries = 30.1 KB (44% of the file).
- Retention: snapshot sections are bounded by log retention (claude `dailyTotals` 82 days, `hourlyTotals` 484 hours at audit start). `dailyUsages` has no pruning and grows ~5 entries/day (one per provider with tokens), ~1.2 KB/day, ~36 KB/month, ~0.43 MB/year. Its only reader `dailyHistory()` has no caller, so this growth buys nothing today.
- Write frequency: every refresh, ~20 s measured while active, 300 s idle floor. At 20 s that is ~4,300 rewrites/day x 68 KB = ~290 MB/day (inferred from the measured cadence).

### 3.4 Parse caches and reads

- Claude JSONL: incremental. `cachedEntry` (ClaudeJSONLParser+Streaming.swift:69-139) keeps `{mtime, size, fileIdentifier, byteOffset, 4 KiB continuityTail}` per file; unchanged file = zero stat/zero read; grown file = read only from `byteOffset` after verifying the tail still matches; otherwise full re-parse. Records are 64 KiB-chunk streamed, 16 MiB record cap (`JSONLRecordFraming.maximumRecordBytes`). Memory: `recordsByID` keeps every deduped record per file for the process lifetime (the cause of the old 731 MB RSS; now ~320 MB).
- Codex JSONL: same design (CodexJSONLParser.swift:41-180, +Streaming 4 MiB chunks, same 16 MiB cap).
- Cline: bounded `read(upToCount: 16 MiB + 1)` per file (ClineMessagesParser.swift:44-45), no cache (re-reads all session files every sync).
- Opencode: SQLite stamp cache (OpencodeStoreParser.swift:63-67), copy + rescan only when the db changed (the db is 304 MB); JSON fallback reads each file with an unbounded `String(contentsOf:)` (line 322).
- Cursor: no cache, full 157 MB copy per refresh (finding 1).
- Antigravity: copies a 1.1 MB db per refresh (trivial).
- `ClaudeAccount.discover` lists `$HOME` and reads `~/.claude.json` (310 KB here) through a stamp cache.

### 3.5 FileWatcher

- Debounced, trailing, 2.0 s (FileWatcher.swift:107-117): each event cancels and restarts the timer; FSEvents latency is 0 (line 78). There is no max-wait, so a stream of events closer than 2 s apart postpones the refresh indefinitely until a quiet gap (the 300 s timer is the backstop). Measured cadence of ~20 s says it does not starve in practice here.
- Watch set is a `static let` evaluated once (FileWatcher.swift:5-16): a `~/.claude-*` account created after launch is not watched until relaunch. Cursor, Gemini, opencode, Antigravity and Copilot are not watched at all; they refresh only when some other event or the 300 s timer fires.

## 4. Security

Verdict: no credential leak path found; the issues are exposure of local metadata, default-on network use, and write hygiene. Nothing here is critical.

### 4.1 `secscan`

`~/agent-kit/bin/secscan /Users/abhayp/Downloads/Projects/AI_tracker`:
```
VERDICT: PASS
repo AI_tracker head 68d10a6c4fb7 base origin/dev (68d10a6c4fb7): 0 commits, 5 uncommitted paths
```
No FLAG or GAP lines. Report file: `.git/secscan/68d10a6c4fb743f217881ea3162b881389bc4f55.txt`.

### 4.2 Permissions on written files

- Only `usage-store.json` asks for 0600 (UsageStore.swift:68-79: creates a 0600 placeholder, then `replaceItemAt`). Experiment in a temp dir: a fresh install ends 0600 and stays 0600 after the next persist. The real file here is `-rw-r--r--` (0644): it predates that change and nothing re-applies the mode, so existing installs never get it. A test locks the fresh-install case only (UsageStoreTests.swift:249-250).
- Everything else uses the default umask (0644): quota-series (experiment confirmed 0644), agent-snapshot, claude-usage caches, cooldown files, antigravity cache, litellm cache. The directory itself is 0755 (`createDirectory` with no attributes).
- Real exposure is small: the parent `~/Library/Application Support` is 0700 with an ACL, so other local users cannot reach these files, and any same-user process can read them regardless of mode. Treat it as defense in depth. Contents: no emails or tokens (no `@` found in any file); account ids are SHA-256 hashes; paths are present in agent-snapshot only. Fix: one shared atomic-write helper that creates the dir 0700 and the files 0600, plus a one-time chmod for existing files.
- Private SQLite copies are done right: dir 0700, files `O_CREAT|O_EXCL` 0600 plus `fchmod` (SQLiteSidecarCopy.swift:12-30, 128-145), removed by `defer`. No leftover `Tokei*` temp dirs found.

### 4.3 Reading provider directories

- Symlinks: Claude, Codex and opencode discovery use `enumerator(at:)` with `.isRegularFileKey` and skip non-regular files (ClaudeCodeProvider.swift:466-467, CodexProvider.swift:233-245, OpencodeStoreParser.swift:353-354). Experiment: a symlinked `.jsonl` reports `isRegularFile=false` and is skipped; the enumerator lists a symlinked directory but does not descend. `ClaudeAccount.discover` resolves roots with `resolvingSymlinksInPath` only to dedupe. A symlinked `~/.claude` itself is followed (by design). Cline/Copilot use `contentsOfDirectory` without a regular-file check (not exercised).
- Bounded reads: JSONL 16 MiB per record; Cline 16 MiB per file; Codex probe 1 MiB (CodexRateLimitClient.swift:24); MCP frame 1 MiB. Unbounded: opencode JSON fallback `String(contentsOf:)` (OpencodeStoreParser.swift:322), `Data(contentsOf:)` on credential/pricing/cache files (ClaudeUsageClient.swift:150,454; GeminiUsageClient.swift:152; PricingService.swift:131,191; AntigravityQuotaClient.swift:152) and on the snapshot in the CLI (SnapshotReader.swift:74). All low risk because the files are the user's own.
- Tokei reads other tools' secrets by design: Claude OAuth (Keychain via `/usr/bin/security`, or `.credentials.json`), Gemini `oauth_creds.json`, Cursor's session JWT from its state db, Antigravity's CSRF token from a process command line. Issue #14 (credential-handling policy) and #12 (local-only disclosure) are still open.

### 4.4 Process spawning

- `security find-generic-password -s <service> -w` (ClaudeUsageClient.swift:82-113): absolute path, fixed argv, the service name is derived from a path hash (no user text in argv), stdin/stderr null, 2 s timeout then `terminate()` (no wait afterwards). Token comes back on a pipe; `readDataToEndOfFile` after exit is unbounded but the child is `/usr/bin/security`. It blocks a thread on a semaphore for up to 2 s per account.
- `codex app-server` (CodexRateLimitClient.swift:75-155): `posix_spawn`, no shell, argv `[binary, "app-server"]`, own process group, 5 s deadline, SIGKILL on the group, stdout capped at 1 MiB, stderr to `/dev/null`. Concerns: (a) the binary is resolved from user-writable directories first (`~/.local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, fnm, nvm) before `/opt/homebrew/bin` and `/usr/local/bin` (lines 47-71), so whatever sits earliest wins; (b) it inherits the app's full environment, sets `CODEX_HOME` and prepends the binary's directory to `PATH` (lines 134-137). Both match what the user's own shell would do, so the trust boundary is the user's account.
- Antigravity (opt-in toggle `antigravityOnlineQuotaEnabled`): `/bin/ps -axo pid=,command=` and `/usr/sbin/lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN`, both absolute paths with fixed argv (AntigravityQuotaClient.swift:251,285). It takes the first process whose command line contains `language_server` and `--standalone`, extracts its CSRF token from argv, then POSTs `{}` with that token to every listening port of that pid. A 5 s watchdog terminates a hung child; output is unbounded in memory (`ps` table).
- No `Process` or spawn call exists in `TokeiCLI`.

### 4.5 Network clients

| Host | Sent | Gate | Session |
|---|---|---|---|
| api.anthropic.com/api/oauth/usage | GET, `Authorization: Bearer <Claude OAuth token>`, `anthropic-beta: oauth-2025-04-20`, UA `Tokei/0.2` (stale version string, ClaudeUsageClient.swift:410-417) | `claudeNetworkUsageEnabled`, default off; 10 min fresh cache, 429 cooldown on disk, 3 attempts max, sleeps <= 30 s | `URLSession.shared` |
| cursor.com/api/usage-summary and /api/dashboard/export-usage-events-csv | GET with `Cookie: WorkosCursorSessionToken=<userId>::<JWT>` built from Cursor's local db, `httpShouldHandleCookies = false` | `cursorNetworkUsageEnabled`, default off; per-cookie cooldown; no fresh cache | `URLSession.shared` |
| oauth2.googleapis.com/token, cloudcode-pa.googleapis.com `loadCodeAssist`, `retrieveUserQuota` | `Bearer` access token from `~/.gemini/oauth_creds.json`; refresh is disabled because the client secret is deliberately not bundled (GeminiUsageClient.swift:55-66) | none; runs when the file exists; no cache, no cooldown | ephemeral |
| 127.0.0.1:<port> (Antigravity language server) | POST `{}` with `x-codeium-csrf-token` from `ps` | `antigravityOnlineQuotaEnabled`, default off | ephemeral; TLS trust accepted for host `127.0.0.1` only (LocalhostOnlyTLSDelegate, AntigravityQuotaClient.swift:364-379) |
| raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json | unauthenticated GET, 15 s timeout, daily | always on | `URLSession.shared`; tracks the `main` branch of a third-party repo with no pin or integrity check (PricingService.swift:182); a bad upstream edit changes displayed costs |
| abhaypadmanabhan.github.io/tokei-macos/appcast.xml | Sparkle update check every 86,400 s, EdDSA public key set (project.yml:76-79) | `SUEnableAutomaticChecks: true` | Sparkle |
| (Codex) | no direct call; `codex app-server` talks to OpenAI itself | `codexLiveQuotaEnabled`, default ON | child process |

All endpoints are HTTPS except loopback; no ATS exception, no `allowsArbitraryLoads`. `URLSession.shared` keeps an on-disk URLCache: `~/Library/Caches/ai.padzy.tokei/Cache.db` currently holds the Anthropic usage response, the Cursor usage summary and the appcast (4 KB). Switch those clients to an ephemeral session as Gemini and Antigravity already do. There is no crash reporter or analytics in the code (grep), consistent with open issue #18. Hardened runtime is on for Release only; no entitlements file and no sandbox (BACKLOG says so).

### 4.6 MCP server (TokeiCLI/MCPServer.swift, MCPFrameReader.swift)

- Framing: newline-delimited JSON-RPC 2.0 on stdio. Frames over 1 MiB are discarded without buffering and answered with -32600 (MCPFrameReader.swift:9, 62-75); non-UTF-8 gets -32700; non-object or bad envelope -32600; notifications never get a reply; method names in errors are truncated to 128 bytes (MCPServer.swift:177-186); `tools/call` accepts only an empty `arguments` object (lines 275-281). EOF ends the process. Writing to a closed stdout would terminate the process (default SIGPIPE).
- Reads only `agent-snapshot.json` (path override via `TOKEI_SNAPSHOT_PATH`). No network, Keychain or other app data (the server instructions claim exactly this, and the code agrees).
- Exposed PII-ish data: absolute profile paths, labels (`default`, `account-1`), hashed `accountID`s, token counts; no emails, tokens or cookies (measured on the live file). See finding 6.
- Trust: the snapshot is the root of a routing decision that tells an orchestrator which env map to launch with. `AccountSelector.executable` only requires an absolute existing directory and an allowlisted key (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`; AgentSnapshot.swift:43-72). A same-user process that rewrites the file can steer routing to a different config dir; there is no signature or ownership check on the file. Same-user is already game over for credentials, so low.
- `SnapshotReader` decodes the whole file with no size cap (line 74) and prints decode errors including the path (StatusCommand/SnapshotReadError). Low.

## 5. MCP and CLI surface

### 5.1 CLI (`tokei`, bundled at `Tokei.app/Contents/Helpers/tokei`; main.swift)

| Command | Input | Output | Exit codes |
|---|---|---|---|
| `tokei status` | none | text table: provider/window/used%/resets/confidence/source, account rows beneath providers, recommendation lines, stale banner (StatusFormatting.swift) | 0; 3 missing, 4 unreadable, 5 malformed snapshot |
| `tokei status --json` | `--json` | the snapshot JSON, pretty-printed, with reader-side `stale` and `ageSeconds` | same |
| `tokei mcp` | stdio JSON-RPC | MCP server below | 0 on EOF |
| `tokei help` / `--help` / `-h` | none | usage | 0 |
| `tokei version` / `--version` | none | `tokei 0.10.0` | 0 |
| unknown / none | | usage on stderr | 64 |

No `--provider`, `--account`, `--watch`, `--compact` or `--since` options. Version is a hand-kept literal (main.swift:15). Env: `TOKEI_SNAPSHOT_PATH`.

### 5.2 MCP (protocol `2024-11-05` hard-coded, MCPServer.swift:26; capabilities `{tools:{}}`; server name `tokei`)

Methods handled: `initialize` (always answers its own version, no negotiation), `notifications/initialized`, `notifications/cancelled`, `ping`, `tools/list`, `tools/call`. Everything else returns -32601. No `resources`, `prompts`, `logging`, `listChanged`, tool annotations, `structuredContent` or `outputSchema`.

| Tool | Input | Output (`content[0].text`, JSON) |
|---|---|---|
| `get_usage` | `{}` (additionalProperties false) | full snapshot + `stale`, `ageSeconds`; optional `content[1]` stale warning text |
| `get_route_recommendation` | `{}` | `{generatedAt, ageSeconds, stale, routeTo, avoid[], reason, target{provider, accountID, selector.env}, avoidAccounts[], validUntil}`; `stale` is true if the file is stale or `validUntil` passed |

The server also ships a long `instructions` string (MCPServer+Instructions.swift) telling agents when to call, the 85% avoid line, and how to use `selector.env`.

### 5.3 Snapshot schema v1 (AgentSnapshot.swift; docs/08-agent-snapshot-schema.md)

Top level: `schemaVersion` (1), `generatedAt`, `providers[]`, `aggregateUtilizationPercent`, `recommendation`, reader-only `stale`, `ageSeconds`. Provider: `id`, `displayName`, `windows[]`, `tokensToday`, `lastUpdated`, `accounts[]?`, `headlineAccountID?`. Account: `id` (legacy path), `label`, `windows[]`, `tokensToday`, `accountID` (provider-scoped SHA-256), `selector.env`, `quota{status, usedPercent, headroomPercent, bindingWindowIndex, validUntil, reasonCode}`. Window: `type`, `usedPercent`, `resetsAt`, `confidence` (official/local_estimate/unavailable), `source`, `observedAt`, `label`, `bucketKey`. Recommendation: `routeTo`, `avoid[]`, `reason`, `target`, `avoidAccounts[]`, `validUntil`. Doc and code agree on fields (checked against the live file); they disagree on whether paths are allowed (finding 6). Live file: 8 providers, only claude_code (2 accounts) and codex (1) have accounts.

### 5.4 Held internally but not exposed to agents

- Pace: `QuotaPace` (state ahead/onPace/behind, elapsed %, delta; QuotaPace.swift) and the window length `QuotaWindow.windowDuration` (QuotaWindow.swift:26). An agent can only infer pace from `type` and `resetsAt`.
- Burn trend and history: `QuotaSeriesStore` samples, `dailyTotals`, `hourlyTotals`, `dailyModelUsage` (ProviderSnapshot.swift), `streak` and daily average (DashboardViewModel.swift:221). No "time to limit" projection exists anywhere.
- Value and cost: `MaxxerValueEngine.scorecard` (API-equivalent USD per provider and per model, plan multiple, tier), `costUsage`, week/month/lifetime `TokenUsage` with input/output/cache/reasoning split. The snapshot has only `tokensToday`.
- Provider health: `authStatus` and `warnings` (e.g. "signed out", "request failed") exist per provider; the snapshot carries status only at account level for providers with accounts. A provider with `windows: []` cannot be told apart as signed out vs no data.
- Per-model windows: present via `bucketKey`/`label`, but no per-model token or value breakdown.
- Reset times: exposed (`resetsAt`), good.
- Interaction gaps: no filter arguments (provider, account), no "refresh now" (docs call a wake-the-app refresh out of scope), no change notification or `resources/subscribe`, no `list_accounts`.
- Token cost of calls: the snapshot is pretty-printed (7,476 B vs 4,646 B compact, -38%) and sent as one text block on every `get_usage`; the recommendation payload alone is ~311 B compact.

## 6. Product gaps

### 6.1 BACKLOG items vs code (grep-confirmed)

| BACKLOG item | Status | Evidence |
|---|---|---|
| WidgetKit target (P1) | Not done | `AIUsageDashboardWidgets/` is 2 files, hard-coded `ProviderEntry(providerName: "Claude", tokenCount: 0)` (ProviderStatsWidget.swift:23-33); no target in project.yml or the generated pbxproj; no App Group anywhere; README:225 agrees. Open issue #16 asks for a rebuild. |
| Per-provider alert thresholds (P1) | Not done | Global `[80, 95]` (NotificationEngine.swift:198); Settings has one notifications toggle (SettingsDrawer.swift:231) |
| Daily history chart (P2) | Built, under a different data source | 30-day `LineTrendChart` in the provider pane (ProviderDetailView+Metrics.swift:139-151, `historyRange` default `.thirtyDay`), Overview trend (OverviewView.swift:117), per-account `AccountTrendChart`. Drawn from snapshot `dailyTotals`; `UsageStore.dailyHistory()` still has zero callers, so BACKLOG and README wording is stale and the persisted `dailyUsages` is dead weight |
| Session drill-down (P2) | Not done | no per-session table in UI/ |
| Launch at login (P2) | Not done | no `SMAppService`/login-item code in the repo |
| CSV/JSON export (P2) | Not done | no `NSSavePanel`/`fileExporter`/export code |
| Menu bar display options (P2) | Largely done | `MenuBarDisplayMode`: today tokens, tightest quota %, all-time tokens, icon only (MenuBarDisplayMode.swift); "which providers count" via the show/hide toggles (hidden providers are excluded from totals, DashboardViewModel D13) |
| Sparkline hover (P2) | Done | `onContinuousHover` + `RuleMark` in LineTrendChart.swift:116,161-166 and AccountTrendChart.swift:82,131-136 |
| Antigravity token counts, Cline credits, multi-machine, App Store (P3) | Not done | README "What Is Stubbed" lists Antigravity tokens as `unavailable` |

Built but missing from BACKLOG "DONE" (the DONE list stops at 2026-07-27; code is 0.10.0): pace gauges (QuotaPace, PaceViews), per-model Value scorecard (ValueView, MaxxerValueEngine), multi-account Claude with per-account charts, route chip, Copilot connector, Codex live quota, account-aware MCP. `tasks/todo.md` still describes 0.9.0 as the active plan.

README "What Is Stubbed" is still accurate for: opt-in network paths, Antigravity tokens, Copilot install-detection only, WidgetKit, per-provider thresholds, no plan auto-detection. Its Roadmap item 3 (history chart) is out of date.

### 6.2 Gaps by user impact (beyond the backlog)

1. Customer-facing ship blockers still open: website/appcast host #10 (the appcast URL is live per Cache.db), first-run onboarding and local-only disclosure #12 (only a first-launch seed exists, AddAgentModel.swift:33-61), credential policy #14, crash reporting #18 (none in code), app identity cleanup #17.
2. The things users asked for most from a quota tool and cannot do today: be told per provider (thresholds), see it in Notification Center or desktop (widget), start with the Mac (login item), get data out (export).
3. Agent surface: no pace, no burn rate or projected exhaustion, no filter, no change signal (section 5.4). The biggest missing agent feature is "when will this account hit its limit", which both `QuotaPace` and the series could answer once the series is account-aware (finding 3).
4. Multi-account history is not trustworthy for quota (finding 3), and Gemini/Cursor/Antigravity quota are not account-aware at all.
5. Retention for quota history is a count, not a time span; a "last 30 days of quota" chart needs a time-based rule or a separate downsampled store.

## 7. What was not checked

- Idle refresh cadence and idle Cursor-copy volume are extrapolated from a 75 s and 50 s live window on a machine where agent sessions were writing logs (including this one). The 300 s timer floor is from code.
- No build, test or UI run. The lint gate and `secscan` are the only commands run against the repo.
- Cline/Copilot symlink behaviour was read, not exercised. Antigravity and Cursor network paths were not exercised (toggles are opt-in; I did not change settings).
- "Issue already shipped" claims are from commit messages plus a read of the code named; I did not run the tests behind them.
- Worktree deletion, issue closing, and chmod of existing files change shared state and were not done.
