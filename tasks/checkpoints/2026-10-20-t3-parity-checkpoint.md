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
| WP-1 value by model | `../tokei-worktrees/2026-10-20-value-by-model` | Codex gpt-6.1-sol | 4 commits; result file says `STATUS: BLOCKED` (see below) |
| WP-2 live Codex quota + 5-min refresh | `../tokei-worktrees/2026-10-20-codex-live-quota` | Codex gpt-6.1-sol | uncommitted edits + new `CodexRateLimitClient.swift`; running the 10-min idle-CPU proof; holds `/tmp/tokei-live-proof.lock` |
| WP-3 pace + by-model UI | `../tokei-worktrees/2026-10-20-pace-ui` | Claude Opus 5.5 | 3 commits (QuotaPace, gauge pace line, value-by-model drill-in); screenshots pending (waits on the lock) |

Child thread IDs (read with `t3_thread_read`; do not start new review rounds on them):
- WP-1 `thread:delegated-task:command%3Amcp%3A440643f5-c144-4a99-b990-c259e83e6690%3Adelegate-task%3Atokei-2026-10-20-wp1-r1`
- WP-2 `thread:delegated-task:command%3Amcp%3A440643f5-c144-4a99-b990-c259e83e6690%3Adelegate-task%3Atokei-2026-10-20-wp2-r1`
- WP-3 `thread:delegated-task:command%3Amcp%3A440643f5-c144-4a99-b990-c259e83e6690%3Adelegate-task%3Atokei-2026-10-20-wp3-r1`
Done = `tasks/reports/2026-10-20-wpN.result.md` committed in the worktree with first line `STATUS: READY|BLOCKED`.

## WP-1 blocker — decision already reasoned, needs applying

WP-1's Claude MTD value is 2.24 % off the Python baseline. Cause: Tokei keeps the LARGEST record per
message id (streaming rows; the last row carries final output tokens); the baseline
(`/tmp/tokei-t3-baseline/mtd_baseline.py`) keeps the FIRST (T3's rule). Tokens differ only 0.03 %, but
output tokens price 5–100× cache reads, so dollars diverge. Tokei's keep-largest is the more correct rule
(final output count) and was verified against independent baselines before. Action: change the baseline
to keep the largest-total record per `id:requestId`, rerun, and accept WP-1 if both providers land
within 0.5 %. Codex already within 0.5 %.

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
