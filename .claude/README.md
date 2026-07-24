# Tokei engineering workflow (`.claude/`)

Deterministic, multi-agent, gated pipeline for shipping Tokei (`ai.padzy.tokei`).
Four slash commands drive the day; real shell gates enforce quality; git worktrees
isolate parallel agents; every step leaves an audit trail.

## The loop

```
/morning-patch  → plan, prioritize, write Patch Bible, create worktrees,
                   dispatch agents directly via herdr, wait for the fleet,
                   then automatically verify/merge/gate/build + manual QA list
      ↓
   manual test
   ┌────────────┴────────────┐
/dev-approved            /dev-reject
 PR dev→main,             triage failure, trace to commits,
 security-review,         fix worktree OR revert bad merge,
 simplify, release        dispatch fixing agent via herdr,
 gates, archive,          auto re-collect on completion
 docs, website
```

`/agents-done` still exists as the collection/verify/merge/gate/build procedure —
it's just no longer a step you type by hand. `/morning-patch` runs it inline once
its dispatched agents finish, and `/dev-reject`'s recovery loop runs it again after
a fix-forward worktree. It's still fully runnable standalone (e.g. to re-collect
after a manual/fallback-dispatched agent).

Branch model: `main` (release, protected) ← `dev` (integration) ← `patch/<date>/<slug>`
(one per agent, in its own worktree under `../tokei-worktrees/`). Each package merges to
`dev` as one `--no-ff` commit, so rollback is a single `git revert -m 1 <sha>`.

## Commands (`.claude/commands/`)

| Command | Role |
|---------|------|
| `/morning-patch` | Plan, launch, dispatch via herdr, and auto-collect the day's parallel work |
| `/agents-done` | Collect, verify, merge to `dev`, build for manual test — invoked automatically by `/morning-patch` and `/dev-reject`; still runnable standalone |
| `/dev-approved` | Promote `dev` toward release (PR, security, simplify, archive, docs) |
| `/dev-reject` | Recover safely from failed manual testing; dispatches the fix via herdr, auto re-collects |

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

## Orchestrator dispatch (herdr)

`/morning-patch` and `/dev-reject` dispatch work-package/fix agents directly via the
`herdr` skill (terminal multiplexer control, requires `HERDR_ENV=1`) instead of
printing a copy-paste prompt for a human to paste in. Verified 2026-07-23 (see
`herdr-agent-fleet-test` memory for the full write-up):

| Kind | herdr `--kind` | Auto-approve flag | Notes |
|---|---|---|---|
| Claude Code | `claude` | `--dangerously-skip-permissions` | real lifecycle tracking |
| Codex | `codex` | `--dangerously-bypass-approvals-and-sandbox` | real lifecycle tracking |
| Cursor | `cursor` | `--trust --force` | real lifecycle tracking; async paste — submit via `pane send-text`+`pane send-keys enter` |
| opencode | `opencode` | `--auto` | **pinned to a local model here** — 80s+ per response is normal, not stalled; has crashed once (Bun segfault); least reliable kind currently |
| Cline | `cline` | `--auto-approve true` | **no herdr lifecycle tracking** — submit via `pane send-text`+`pane send-keys enter`, confirm completion only via a task-specific marker string, never trust `agent_status` |
| Antigravity | `agy` | `--dangerously-skip-permissions` | **no herdr lifecycle tracking** (like cline) — submit via `pane send-text`+`pane send-keys enter`; the herdr skill itself had to be installed into agy's own plugin system (`agy plugin install`, `~/.gemini/config/plugins/herdr/`) before it could see it — see `herdr-agent-fleet-test` memory for how |
| Kimi | `kimi` | untested | verify before relying on it |
| GLM | *(no herdr kind)* | — | fall back to the old copy-paste prompt for that package |

Dispatched agents are polled (bounded iterations), not babysat synchronously. Any
agent reaching `blocked` is surfaced immediately with its pane contents so the human
can intervene — never silently retried or hung on forever.

## Internal research subagents

Separately from the table above (which is about the *external work-package agents*),
`/morning-patch` and `/agents-done` also spawn Claude Code's own Agent-tool
subagents for their own research/gathering/review substeps (repo inspection, diff
review before a merge decision) instead of doing that work inline in the
orchestrator's context. Model tier by stakes: mundane/repetitive gathering (issue
lists, TODO greps, test-run summaries) → **Sonnet** or smaller; high-stakes judgment
(reviewing a merge diff for architecture-rule/frozen-contract compliance, deciding
what's safe to land) → **Opus**. This is a different rule from the UI-agent
Sonnet/Opus tiering in "Agent selection" below — that one picks the model for the
*external* Claude Code work-package agent; this one picks the model for the
orchestrator's *own* internal helpers.

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
