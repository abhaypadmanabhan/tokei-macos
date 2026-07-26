# Fold herdr dispatch + auto-collection into release pipeline — DONE 2026-07-24

Restructured `/morning-patch` and `/dev-reject` to dispatch work-package agents
directly via herdr instead of copy-paste prompts, and to auto-invoke
`/agents-done`'s collection inline instead of a separately-typed command. Full
context and rationale: `.claude/README.md`'s "Orchestrator dispatch (herdr)"
section, and the `tokei-release-workflow`/`herdr-agent-fleet-test` memory entries.
Live-verified via the 2026-07-24 patch run (`tasks/patch-bibles/2026-07-24.md`).

- [x] `.claude/commands/morning-patch.md` — Step 8 herdr dispatch, Step 8.5 wait/surface blockers, Step 9 inline auto-collect, Step 1 + diff-review delegated to subagents (Sonnet/Opus tiering), Output rewritten, allowed-tools += Bash(herdr*)/Agent
- [x] `.claude/commands/agents-done.md` — header note: also auto-invoked by morning-patch Step 9 + dev-reject recovery
- [x] `.claude/commands/dev-reject.md` — Step 7 herdr dispatch, Output auto-collect, allowed-tools += Bash(herdr*)/Agent
- [x] `.claude/README.md` — loop diagram, "Orchestrator dispatch (herdr)" section, "Internal research subagents" section
- [x] `tasks/patch-bibles/TEMPLATE.md` §8 wording fix
- [x] `.claude/hooks/pre-commit` comment fix
- [x] `.claude/commands/dev-approved.md` — two `/agents-done` reference wording fixes
- [x] Verify: grep all cross-references, confirm no broken/stale mentions remain
