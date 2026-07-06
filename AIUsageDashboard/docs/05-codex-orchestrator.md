# Codex Orchestrator Guide

## Purpose

This document tells Codex how to act as the orchestrator when implementing the AI Usage Dashboard.

## First Step: Read the Docs

Before writing any code, Codex must read all docs in this order:
1. `01-engineering-research.md`
2. `02-prd.md`
3. `03-architecture.md`
4. `04-implementation-roadmap.md`
5. `06-provider-spec.md`
6. `05-codex-orchestrator.md` (this file)

## Role

Codex acts as the staff engineer, orchestrator, and integration owner. It coordinates work, enforces architecture, and performs the final merge.

## Workflow

1. **Create worktrees or branches for each agent.**
   - Use `git worktree` or feature branches so agents do not step on each other's files.
2. **Assign bounded tasks.**
   - Each task must have a clear file/module boundary.
   - No two agents should own the same file at the same time.
3. **Prevent file ownership conflicts.**
   - Maintain a shared `AGENTS.md` file with task assignments.
   - Require agents to claim files before editing.
4. **Run build/tests before any merge.**
   - Every agent branch must pass `swift build` and `swift test` before Codex merges it.
5. **Review every agent's diff.**
   - Codex must review the diff, not just accept it.
   - Look for violations of the no-UI-to-provider-direct-call rule.
   - Look for hardcoded assumptions about quota models.
   - Look for secrets outside Keychain.
6. **Consolidate branches.**
   - Merge into a single integration branch.
   - Resolve conflicts in favor of the architecture docs.
7. **Keep architecture consistent.**
   - If a decision changes, update the docs first, then the code.
8. **Update docs when decisions change.**
   - New provider endpoint discovered? Update `01-engineering-research.md` and `06-provider-spec.md`.
   - New UI pattern? Update `03-architecture.md`.

## Agent Assignments

| Agent | Primary Responsibility |
|-------|------------------------|
| Codex | Orchestration, architecture, integration, tests, final merge |
| Cursor | Provider adapters (Claude, Codex, Cursor), endpoint research, local detection |
| Antigravity | SwiftUI dashboard, menu bar, widgets, visual polish |
| Kimi | Storage, file watchers, parser infrastructure, background sync, documentation scaffold |

## Communication Rules

- Use GitHub issues or a shared task file for cross-agent coordination.
- Before any agent starts a task, they must state which files they will touch.
- When an agent finishes, they must provide a summary, test results, and a diff.

## Merge Checklist

- [ ] `swift build` passes.
- [ ] `swift test` passes.
- [ ] No UI-to-provider direct calls.
- [ ] All new metrics have confidence labels.
- [ ] No secrets outside Keychain.
- [ ] Raw provider response storage is debug-only.
- [ ] Docs updated if any architecture decision changed.
- [ ] Provider adapters are isolated from shared core.

## Common Mistakes to Catch

- Hardcoding private endpoint URLs in shared core code.
- Loading large JSONL files into memory.
- Missing confidence labels.
- Forcing a provider into a quota model it does not support.
- Storing tokens or credentials in UserDefaults.
- Calling provider APIs from SwiftUI views.
- Skipping tests.
