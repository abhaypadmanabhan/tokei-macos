---
description: Handle failed manual testing safely — capture the failure, trace it to the responsible commits/worktrees, keep dev off main, build a fix plan, spin a focused fix worktree or revert the bad merge, update the Patch Bible, and emit a prompt for the fixing agent.
argument-hint: "[failure description, or leave blank to be asked]"
allowed-tools: Bash(git*), Bash(bash .claude/gates/*), Bash(xcodegen*), Bash(xcodebuild*), Bash(rg*), Bash(grep*), Bash(cp*), Bash(chmod*), Bash(mkdir*), Read, Write, Edit, Skill
---

# /dev-reject — manual testing failed; recover safely

Manual QA failed. Contain the damage, diagnose the root cause, and set up a clean fix
pass. **Do NOT promote `dev` to `main`.** Failure details from user: `$ARGUMENTS`.

Announce: "Using /dev-reject to triage the failure and plan the fix."
Use the `superpowers:systematic-debugging` skill to drive diagnosis (root cause, not band-aid).

## Step 1 — Capture the failure

If `$ARGUMENTS` is empty, ask the user (per their preference, via the dictation question
tool) for: what they did, expected vs actual, which screen/flow, any console output.
Record it verbatim in the Patch Bible §8 and in `tasks/reports/reject-<date>.md`.

## Step 2 — Trace to responsible commits/worktrees

Correlate the failing flow to the day's merges:

- `git log --oneline --merges main..dev` — list the `--no-ff` package merges.
- Map the failing area to a work package via the Bible §3 scopes and changed files
  (`git diff --name-only main..dev`, `git log -p -S'<symbol>' main..dev`).
- If unclear, `git bisect` between last-known-good (`main`) and `dev`, using the failing
  behavior (or a new failing test) as the check.
- Reproduce first. If you cannot reproduce, say so and mark it low-priority rather than
  guessing (do not two blind fixes in a row — instrument the path with checkpoints).

## Step 3 — Keep dev off main

Confirm no PR was merged. If a dev→main PR is open, mark it blocked/needs-fix; do not merge.

## Step 4 — Fix plan

Write into the Bible §8 + reject report:
- **Bug summary**, **suspected root cause**, **owner/agent recommendation** (reuse the
  original package's agent unless the miss suggests another — e.g. UI regression → Antigravity,
  parser/data bug → Codex, high-risk/ambiguous → Claude Code),
- **files involved**, **acceptance criteria** (must include a regression test that fails now),
  **tests needed**.

## Step 5 — Contain: fix-forward OR revert (choose the safer)

- **Isolated to one package, dev otherwise healthy → fix-forward.** New worktree:
  ```bash
  git worktree add ../tokei-worktrees/$(date +%F)-fix-<slug> -b patch/$(date +%F)/fix-<slug> dev
  cp .claude/hooks/pre-commit "$(git -C ../tokei-worktrees/$(date +%F)-fix-<slug> rev-parse --git-path hooks/pre-commit)"
  chmod +x "$(git -C ../tokei-worktrees/$(date +%F)-fix-<slug> rev-parse --git-path hooks/pre-commit)"
  bash .claude/gates/worktree-sanity.sh ../tokei-worktrees/$(date +%F)-fix-<slug> patch/$(date +%F)/fix-<slug>
  ```
- **Merge is broadly broken / risky / entangled → revert it.**
  `git checkout dev && git revert -m 1 <bad-merge-sha>`, then `bash .claude/gates/run-all.sh full`
  to prove `dev` is green again, and quarantine that package's branch for rework.

Prefer whichever restores a known-good `dev` fastest with least risk. State the choice + why.

## Step 6 — Update the audit trail

Update Patch Bible §8 (rejection reason, decision, new branch/revert sha) and
`tasks/relay/BATON.md` current-state so the next session sees the true state.

## Step 7 — Emit the fixing-agent prompt (if a fix pass is needed)

Same self-contained shape as `/morning-patch` Step 8: worktree path, branch, Bible path +
WP reference, the bug summary, scope in/out, frozen contracts, the regression test to add,
tests to run, commit-in-worktree-only, no-merge/no-push, append completion note.

## Output

1. Rejection summary (verbatim failure + repro status).
2. Suspected root cause + responsible package/merge.
3. Fix vs revert decision and why.
4. New fix worktree (path/branch) or revert sha.
5. Prompt for the fixing agent.
6. **Next command after the fix is committed:** `/agents-done`.
