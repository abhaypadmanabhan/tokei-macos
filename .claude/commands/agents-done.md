---
description: Collect completed work from every agent worktree, verify it, merge accepted work into dev in safe order, run full gates, produce a testable dev build, and emit a manual QA checklist.
argument-hint: "[optional: specific worktree/branch to process]"
allowed-tools: Bash(git*), Bash(bash .claude/gates/*), Bash(xcodegen*), Bash(xcodebuild*), Bash(open*), Bash(ls*), Bash(find*), Bash(rg*), Bash(grep*), Bash(cp*), Read, Write, Edit, Skill
---

# /agents-done — collect, verify, merge into dev, build for manual test

You are the **integration owner**. Merge only what is safe; keep a clean audit trail.
Never merge broken, untested, or suspicious work. Never hide a failing test. Optional
scope from user: `$ARGUMENTS`.

Announce: "Using /agents-done to verify agent work and integrate into dev."

## Step 1 — Ensure `dev`

`git show-ref --verify --quiet refs/heads/dev || git branch dev main`. Report.
Read today's Patch Bible (`tasks/patch-bibles/<date>.md`) — it defines the expected
worktrees, scopes, merge order, and acceptance criteria you verify against.

## Step 2 — Inspect every agent worktree

`git worktree list`. For each `patch/*` worktree, gather:

- branch, commits ahead of `dev` (`git -C <wt> log --oneline dev..HEAD`),
- changed files (`git -C <wt> diff --name-only dev...HEAD`),
- the completion note appended to Bible §8,
- uncommitted changes (`bash .claude/gates/no-uncommitted.sh <wt>`),
- any test results the agent recorded.

## Step 3 — Quarantine gate (reject before merge)

Quarantine (do NOT merge; record why) any worktree with ANY of:

- broken build or failing core tests,
- suspicious/credential files (`bash .claude/gates/no-secret.sh` with `BASE_REF=dev`),
- large artifacts (`no-large-artifact.sh` with `BASE_REF=dev`),
- unrelated / out-of-scope changes (`bash .claude/gates/worktree-sanity.sh <wt> <branch> <scope-prefixes>`),
- frozen-contract violations (Bible §4) — check `UsageProvider`, `UsageStore`,
  `ProviderSnapshot`/`ModelCodableExtensions.swift`, deleted or weakened tests,
- messy/unsafe history (secrets in older commits, force-pushes, giant squashes hiding work).

For each quarantined worktree: state the exact reason and leave the branch untouched
for `/dev-reject` or a fix pass. Continue with the acceptable ones.

## Step 4 — Verify & merge accepted worktrees (safe dependency order)

Follow the Bible §2 merge order. For each accepted worktree, per package:

1. **Review the diff** (`git -C <wt> diff dev...HEAD`) — read it, don't rubber-stamp.
   Check architecture rules: no UI→provider direct calls, new metrics carry confidence
   labels, no secrets outside Keychain, raw responses debug-only.
2. **Targeted tests** in the worktree before merge:
   `cd <wt>/AIUsageDashboard && xcodegen generate && xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test`.
3. **Merge into `dev`** from the main checkout, preserving clean history:
   `git checkout dev && git merge --no-ff patch/<date>/<slug> -m "merge(patch/<date>/<slug>): <summary>"`.
   Resolve conflicts deliberately, favoring the architecture docs; re-run the targeted
   test after resolving. One `--no-ff` merge per package → one-command revert later.

## Step 5 — Integration verification on `dev`

After all accepted merges, on `dev`, run the **full** gate set and record output:

```bash
bash .claude/gates/run-all.sh full     # preflight, secrets, artifacts, uncommitted, format, lint, build, test
```

If `build` or `test` FAIL after merge → the integration is broken: identify the culprit
merge, `git revert -m 1 <merge-sha>` it, re-run gates, and move that package to quarantine.
Then: run `/security-review` on the merged diff; run housekeeping (regen check, no stray
files); update `README.md` "What Works", `tasks/relay/BATON.md` state, and a CHANGELOG /
dev-notes entry if one exists.

## Step 6 — Produce a testable dev build

Build a runnable app from `dev` for manual testing:

```bash
cd AIUsageDashboard && xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath build/dev build
```

Report the built `.app` path (`build/dev/Build/Products/Debug/Tokei.app`) and offer
`open <path>`. Note the effective version (`MARKETING_VERSION` + short git sha of `dev`).
Prefer the `verify`/`run` skill to actually launch it if available.

## Step 7 — Manual test checklist (emit, tailored to what changed)

Always include, and mark which items the day's patch touched:

- [ ] Core flows: multi-provider dashboard loads; Claude Code + Codex + Cline totals correct.
- [ ] UI regressions: menu bar extra, provider detail, gauges/meters, countdown timers.
- [ ] Settings/preferences: notification toggle, provider selection persist.
- [ ] Onboarding / empty states (no logs on machine) render intentionally, not blank.
- [ ] Error states: malformed logs, missing provider dir, revoked permissions.
- [ ] Data persistence: `~/Library/Application Support/AIUsageDashboard/usage-store.json`
      survives relaunch and log rotation (daily rollups intact).
- [ ] Performance paths: FSEvents auto-refresh (2s debounce), large log dirs, ⌘R refresh.
- [ ] macOS permission/security flows: notification authorization, Keychain, sandbox/entitlements.
- [ ] Anything named in the Patch Bible acceptance criteria (list each explicitly).

## Output

1. Per-agent summary (branch, commits, files, completion note).
2. What was merged (with merge shas + order).
3. What was rejected/quarantined and exactly why.
4. Test/build/gate results (real output, not claims).
5. Known risks.
6. Manual testing checklist (above, tailored).
7. **Exact next step:** `/dev-approved` if manual testing passes, `/dev-reject` if it fails.
