# Checkpoint — 2026-10-20 · T3-parity usage measurement (Tokei 0.10.0 candidate)

Ask (Abhay): adopt T3 Code v2's usage-measurement techniques in Tokei and ship.
Spec / source of truth: `tasks/patch-bibles/2026-10-20.md` (read it first).

## State at checkpoint (~08:55 UTC 2026-10-20)

- `dev` @ `3a26c05` (local only, not pushed). Landed: contracts `706aae8` (QuotaWindow.windowDuration,
  ProviderSnapshot.dailyModelUsage + persistence test), `6d8aad6` (MaxxerProviderValue.models), Bible `3a26c05`.
- Unrelated, pre-existing, NOT ours: 5 deleted PNGs under `tasks/brand/` and `tasks/handoff/` in the
  dev checkout. Leave them unstaged.
- Three lanes were dispatched from the previous T3 thread with `delegate_task`; they keep running after
  that chat closes, but their completion notices go to the OLD thread. Check them by files and git:

| Lane | Worktree (branch `patch/2026-10-20/<slug>`) | Agent | State at checkpoint |
|---|---|---|---|
| WP-1 value by model | `../tokei-worktrees/2026-10-20-value-by-model` | Codex gpt-6.1-sol | DONE, 4 commits (fbfad6a, ef10d5b, e72a598, 0ee2e5c); numbers pass (see below); needs Claude review |
| WP-2 live Codex quota + 5-min refresh | `../tokei-worktrees/2026-10-20-codex-live-quota` | Codex gpt-6.1-sol | uncommitted edits + new `CodexRateLimitClient.swift`; running the 10-min idle-CPU proof; holds `/tmp/tokei-live-proof.lock` |
| WP-3 pace + by-model UI | `../tokei-worktrees/2026-10-20-pace-ui` | Claude Opus 5.5 | 3 commits (QuotaPace, gauge pace line, value-by-model drill-in); screenshots pending (waits on the lock) |

Child thread IDs (read with `t3_thread_read`; do not start new review rounds on them):
- WP-1 `thread:delegated-task:command%3Amcp%3A440643f5-c144-4a99-b990-c259e83e6690%3Adelegate-task%3Atokei-2026-10-20-wp1-r1`
- WP-2 `thread:delegated-task:command%3Amcp%3A440643f5-c144-4a99-b990-c259e83e6690%3Adelegate-task%3Atokei-2026-10-20-wp2-r1`
- WP-3 `thread:delegated-task:command%3Amcp%3A440643f5-c144-4a99-b990-c259e83e6690%3Adelegate-task%3Atokei-2026-10-20-wp3-r1`
Done = `tasks/reports/2026-10-20-wpN.result.md` committed in the worktree with first line `STATUS: READY|BLOCKED`.

## WP-1 — finished; numbers now PASS (still needs different-model review)

WP-1 finished `STATUS: BLOCKED` only because its Claude MTD value was 2.24 % off the first baseline.
Cause: Tokei keeps the LARGEST record per message id (the last streaming row carries final output
tokens); the first baseline kept the FIRST (T3's rule). Output tokens price 5–100× cache reads, so a
0.03 % token gap became 2.2 % in dollars. Tokei's rule is the more correct one. Resolved: new baseline
`/tmp/tokei-t3-baseline/mtd_baseline_keepmax.py` (keep largest). Result, Oct 1–20:
Claude baseline $9,086.72 (run 09:04 UTC) vs Tokei REAL-LOGS $9,080.96 (run 08:53 UTC) = 0.06 %, with
`claude-fable-5-1` exact to the cent ($723.29); the remaining gap is usage that landed between the two
runs. Codex 0.043 % (Tokei $315.25). Both within the 0.5 % bar → WP-1 accepted on proof.
Note from WP-1: `run-all.sh fast` fails on PRE-EXISTING swiftlint debt (no new violations); full Core
run 658 tests, 5 skips, 0 failures after one stale assertion was fixed. secscan PASS on the branch.

## Measured facts (do not re-derive)

- Token counts already match T3's rules: Codex 795,898,075 both ways (0 diff); Claude 0.03 % apart.
- Value error before this work: Claude priced as `claude-sonnet-4-6` → +10 % ($16,196 vs $14,704 all-time);
  Codex priced as `gpt-5` → −36 % ($199 vs $312). Baseline MTD (Oct 1–20, keep-first): Claude $8,869.53
  (opus-5-5 $8,042), Codex $312.32 (`codex-auto-review` 32.5 M tokens unpriced — correct).
- `codex app-server` → `account/rateLimits/read` answered in 0.9 s on codex-cli 0.163.0: weekly 0 %,
  `windowDurationMins` 10080, 3 reset credits. Probe: `/tmp/tokei-t3-baseline/codex_rl_probe.py`.
- Baseline scripts (read-only, real logs): `/tmp/tokei-t3-baseline/{codex_compare,claude_compare,cost_compare,mtd_baseline,codex_rl_probe}.py`.
  T3 source clone: `/tmp/t3research-1792484414/t3code` (main @ d2fb83a). `/tmp` may be wiped on reboot;
  re-clone `pingdotgg/t3code` if needed.

## Decisions taken (Abhay can flip)

- Live Codex quota is ON by default (setting `codexLiveQuotaEnabled`), unlike the opt-in network toggles,
  because Tokei never touches Codex credentials — it only asks the installed `codex` binary.
- Out of scope, follow-ups: Antigravity real tokens from `~/.gemini/antigravity*/conversations/*.db`
  protobuf (T3 `antigravityUsageReader.ts`), Codex fast/priority tier pricing, Cline/opencode reported
  cost in the value engine, pace in the MCP snapshot, Grok/Pi (not installed).

## Remaining steps

1. Wait for each lane's result file (or read the child thread). Answer any pending question the lane
   raises (`t3_pending_request_list` on its childThreadId).
2. Review each lane with a different model than its author (`change-review` skill: spec, standards,
   proof): WP-1/WP-2 (Codex-authored) → Claude review; WP-3 (Claude-authored) → Codex review.
   Rerun their tests yourself; a worker's green suite is not evidence.
3. Merge to dev `--no-ff` in order WP-1, WP-2, WP-3 (per `.claude/commands/agents-done.md`), then
   `bash .claude/gates/run-all.sh full` on dev.
4. Integrated proof on the real app: build Debug, quit other Tokei, launch, check
   `~/Library/Application Support/AIUsageDashboard/agent-snapshot.json` (Codex live window, fresh
   `observedAt`, quota `eligible`), Value screen per-model $ vs baseline, pace visible on gauges,
   idle CPU ≤ 1 % with window closed.
5. Release (`/dev-approved` flow): security review, `~/agent-kit/bin/secscan`, bump to 0.10.0 build 10
   (`AIUsageDashboard/project.yml` + `TokeiCLI/main.swift`), CHANGELOG + release notes, notarized
   `scripts/release.sh`, appcast, GitHub release, website version. Publishing is outward-facing: get
   Abhay's explicit yes in that session; see memory `dev-approved-publish-permissions`.
6. Cleanup: remove `/tmp/tokei-live-proof.lock` if stale, relaunch Abhay's normal Tokei
   (`/Applications/Tokei.app` or `AIUsageDashboard/dist/Tokei.app`), remove the three worktrees after merge.

## Session 2 (Claude Opus 5.5, Claude Code + herdr) — ~09:30 UTC 2026-10-20

Abhay's answers before sleeping (binding for this release):
- **Publish:** YES to ship everything if every check passes (merge main, push, GitHub release with
  notarized DMG, appcast, website version). Stop and wait if any check fails.
- **CPU bar:** ship if the new Release build is ≤ 1 % idle when no agent writes logs AND no worse than
  shipped 0.9.0 under the same agent load.
- **Menu-bar quota rows:** add a small state arrow per row (no words); words stay in the headline.

State: T3 runs for WP-2/WP-3 were CANCELLED at 09:11:38Z (parent thread closed); WP-1 completed.
- WP-1: Claude review Spec PASS / Standards 2 fixes → `1340f2f` (Codex delta PASS). Tests 92/0 + mutation red. AC5 pinned 0.004 % / 0.12 %.
- WP-2: Claude review CHANGES (SIGPIPE, cooperative-pool block, probe every refresh, coalescing drops changes,
  live drops log-only windows, real client default, perpetual fetching, grandchild kill) → Codex fixer in herdr
  pane `wp2-codex-fix`, brief `tasks/reports/2026-10-20-wp2.fix-brief.md` in the WP-2 worktree.
- WP-3: Codex review CHANGES → `bcbc781`; delta still wants the Overview/menu pace accessor to require a reported used + per-row state.
- Proof lock `/tmp/tokei-live-proof.lock` now owned by the orchestrator. Baseline `mtd_baseline.py` keeps largest; `BASELINE_NOW` pins time.
