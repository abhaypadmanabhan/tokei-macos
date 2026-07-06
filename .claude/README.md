# Tokei engineering workflow (`.claude/`)

Deterministic, multi-agent, gated pipeline for shipping Tokei (`ai.padzy.tokei`).
Four slash commands drive the day; real shell gates enforce quality; git worktrees
isolate parallel agents; every step leaves an audit trail.

## The loop

```
/morning-patch  → plan, prioritize, write Patch Bible, create worktrees, emit agent prompts
      ↓            (you dispatch the emitted prompts to the chosen external agents)
/agents-done    → verify each worktree, merge accepted work into dev, full gates, dev build + manual QA list
      ↓
   manual test
   ┌────────────┴────────────┐
/dev-approved            /dev-reject
 PR dev→main,             triage failure, trace to commits,
 security-review,         fix worktree OR revert bad merge,
 simplify, release        update Bible → back to /agents-done
 gates, archive,
 docs, website
```

Branch model: `main` (release, protected) ← `dev` (integration) ← `patch/<date>/<slug>`
(one per agent, in its own worktree under `../tokei-worktrees/`). Each package merges to
`dev` as one `--no-ff` commit, so rollback is a single `git revert -m 1 <sha>`.

## Commands (`.claude/commands/`)

| Command | Role |
|---------|------|
| `/morning-patch` | Plan & launch the day's parallel work |
| `/agents-done` | Collect, verify, merge to `dev`, build for manual test |
| `/dev-approved` | Promote `dev` toward release (PR, security, simplify, archive, docs) |
| `/dev-reject` | Recover safely from failed manual testing |

## Gates (`.claude/gates/`)

Each script exits 0 = PASS, non-zero = FAIL. Optional-tool-missing = SKIP (exit 0)
unless `STRICT_GATES=1`. All read-only except where the name says otherwise; none push.

| Gate | Checks | When |
|------|--------|------|
| `preflight.sh` | repo/branch/tree/worktree/upstream sanity | start of every command |
| `worktree-sanity.sh` | worktree on expected branch, changes in scope | per worktree |
| `no-secret.sh` | keys/tokens/JWT/credential files in diff | per-commit + merge |
| `no-large-artifact.sh` | build artifacts & >`MAX_MB` blobs (default 5) | per-commit + merge |
| `no-uncommitted.sh` | clean (work)tree | merge + release |
| `format.sh` | swiftformat --lint (SKIP if absent) | per-commit + merge |
| `lint.sh` | swiftlint --strict (SKIP if absent) | merge |
| `build.sh` | xcodegen generate + build `AIUsageDashboardApp` | merge + release |
| `test.sh` | xcodegen generate + test `AIUsageDashboardCore` | merge + release |
| `run-all.sh` | orchestrates the above: `fast` \| `full` \| `release` | any step |

Env knobs: `BASE_REF` (diff base, e.g. `dev` or `main`), `MAX_MB`, `EXPECT_CLEAN`,
`STRICT_GATES`. Examples:

```bash
bash .claude/gates/run-all.sh fast                 # cheap checks, staged diff
BASE_REF=dev  bash .claude/gates/run-all.sh full    # everything, dev..HEAD range
BASE_REF=main bash .claude/gates/run-all.sh release  # strict: lint/format become hard fails
```

`swiftlint`/`swiftformat` are not installed on this machine → those gates SKIP by default.
`brew install swiftlint swiftformat` to make them enforce (or use `release` mode to require them).

## Hook (`.claude/hooks/pre-commit`)

`/morning-patch` copies this into each worktree's `.git/hooks/pre-commit`. It runs the
fast gates (`no-secret`, `no-large-artifact`, `format`) so bad commits never enter an
agent branch. Heavy gates (build/test) run at merge time, not per-commit.

## Audit trail

- `tasks/patch-bibles/<date>.md` — the day's plan of record (from `TEMPLATE.md`): issues,
  scopes, agents, acceptance, risks, merge order, rollback, and agents' completion notes.
- `tasks/relay/BATON.md` — running current-state handover.
- `tasks/reports/` — per-agent, security, release, and rejection reports.

## Agent selection (don't use every agent)

Internal skills (`padzy-os`, `superpowers`, `/security-review`, `/simplify`, `caveman`) run
ONLY in Claude Code — external agents cannot invoke them. So: Codex → bounded Swift core/
parsers/storage. **Claude Code (Sonnet; Opus for hero/display-tier) + `padzy-os` → ALL
SwiftUI / menu bar / widgets**, LOCKED to a dedicated UI agent in its own worktree scoped to
`AIUsageDashboardApp/UI/` (+ `Resources/`) — never baked into a core package, never a
non-Claude agent. Kimi K2.7 → watchers/sync/infra/docs. Cursor → wide multi-file refactor/
research. Claude Code (Opus) → high-risk/architecture/review + any skill-dependent work.
GLM 5.2 → cheap bulk/mechanical. Antigravity available but not assigned UI under the lock.
Non-Claude agents get theme tokens + invariants inlined as plain text, never "run the skill."
Minimum set that maximizes safe parallelism; never two agents on the same files.
