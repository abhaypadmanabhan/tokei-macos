---
description: Plan and launch the day's parallel engineering — inspect repo, prioritize issues, write the Patch Bible, create per-agent worktrees from dev, verify gates, emit copy-paste agent prompts.
argument-hint: "[optional: issue filter, e.g. 'labels=bug' or a milestone]"
allowed-tools: Bash(git*), Bash(gh*), Bash(bash .claude/gates/*), Bash(xcodegen*), Bash(xcodebuild*), Bash(grep*), Bash(rg*), Bash(find*), Bash(ls*), Bash(cp*), Bash(chmod*), Bash(mkdir*), Read, Write, Edit, Skill
---

# /morning-patch — plan & launch parallel work

You are the **release engineer / orchestrator** for Tokei (`ai.padzy.tokei`, local-first
macOS AI-usage dashboard; xcodegen + xcodebuild; test scheme `AIUsageDashboardCore`,
build scheme `AIUsageDashboardApp`). Execute the steps below **in order, deterministically**.
Do not skip steps. Do not write any product code — you only plan, scaffold, and hand off.
Optional filter from the user: `$ARGUMENTS`.

Announce: "Using /morning-patch to plan and launch today's parallel work."

## Step 0 — Preflight & base branch

1. `bash .claude/gates/preflight.sh` — abort and report if it FAILS.
2. Ensure `dev` exists: `git show-ref --verify --quiet refs/heads/dev || git branch dev main`.
   Report whether `dev` was found or created (and from which `main` sha).
3. Confirm the gate scripts exist and are executable (`ls -l .claude/gates`). If any is
   missing, stop and say so — the workflow depends on them.

## Step 1 — Inspect repo state

Gather, in parallel where possible, and summarize concisely:

- Current branch, `git status --short`, recent commits, existing `git worktree list`.
- **Open issues:** `gh issue list --state open --limit 50` (if `gh` unauthenticated,
  say so and fall back to `tasks/BACKLOG.md` + the README "What Is Stubbed" section).
- **TODOs/FIXMEs:** `rg -n 'TODO|FIXME|HACK|XXX' AIUsageDashboard/AIUsageDashboardApp` (cap output).
- **Failing tests:** `bash .claude/gates/test.sh` (record pass count / failures).
- **Lint/format problems:** `bash .claude/gates/lint.sh`, `bash .claude/gates/format.sh`
  (both SKIP cleanly if swiftlint/swiftformat absent — note that).
- **Product gaps:** read `tasks/BACKLOG.md`, `tasks/todo.md`, README stubbed list,
  `AIUsageDashboard/docs/` roadmap. Note Cursor (stubbed) and Antigravity (skeleton).

## Step 2 — Prioritize

Score every candidate issue:

`priority = user_impact × release_value ÷ implementation_risk`,
then order ties by **dependency order** (blockers first), then **parallelization
potential** (independent file-scopes preferred so agents never collide).

Produce a ranked table. Select only what can land cleanly today (default ≤ 4 work
packages so review stays tractable). **Never assign two agents the same files** unless
you explicitly declare a shared, sequenced dependency in the Bible.

## Step 3 — Assign agents (choose per issue; do NOT use every agent)

**Skill availability is the first constraint.** The internal skills — `padzy-os`,
`superpowers`, `/security-review`, `/simplify`, `caveman` — exist ONLY inside Claude Code.
External agents (Codex, Cursor, Antigravity, Kimi K2.7, GLM 5.2) CANNOT run them. So any
package whose quality depends on a skill must be owned by a **Claude Code agent** (Sonnet
default; Opus for display-tier UI or high-risk work), or have those rules INLINED as plain
text in the prompt. UI/UX taste (`padzy-os`) → Claude Code. External agents get the theme
tokens + invariants written out verbatim, never "run the skill."

Pick the minimum set that fits the work. Selection matrix for Tokei:

| Work type | Preferred agent | Why |
|-----------|-----------------|-----|
| Bounded Swift core: provider adapters, parsing, storage, contract-bound modules | **Codex** | Staff-eng/integration owner in this repo; strong at bounded, contract-respecting Swift |
| Taste-critical SwiftUI / menu bar / widgets / visual polish | **Claude Code (Sonnet; Opus for hero/display-tier)** + `padzy-os` | `padzy-os` runs only in Claude Code; it carries Padzy taste + the "aitracker" theme |
| File watchers, background sync, infra, docs scaffolding | **Kimi K2.7** | Owns storage/watcher/docs infra in this repo |
| Broad multi-file refactor, endpoint/API research across the codebase | **Cursor** | Best at wide, cross-file edits |
| High-risk, architecture-sensitive, judgment-heavy, or any skill-dependent work | **Claude Code (Opus)** | Reasoning + review depth; the ONLY agent that can run internal skills |
| Cheap bulk/mechanical transforms, test generation, repetitive grunt | **GLM 5.2** | Cost-efficient parallel throughput |

Antigravity is available but is NOT assigned UI under the lock below; use it only if a
package genuinely needs it and no better fit exists (it cannot run internal skills).

Rules: prefer 1 agent per independent file-scope; never two agents on the same files.
**UI ownership (LOCKED):** ALL SwiftUI/UI work goes to a **dedicated Claude Code UI agent**
in its own worktree, scoped to `AIUsageDashboardApp/UI/` (+ `Resources/` assets), running
`padzy-os`. Never bake UI into a core/logic package; never assign UI to a non-Claude agent.
This keeps UI (taste + padzy-os) on its own branch, disjoint from the Codex core agent on
`Core/`, so they parallelize without file collisions. If a core change needs a matching UI
tweak, the UI agent owns the `UI/` file and the core agent stays out of `UI/`. Don't spin
up an agent that adds coordination cost without parallelization value.

## Step 4 — Write the Patch Bible

Copy `tasks/patch-bibles/TEMPLATE.md` → `tasks/patch-bibles/$(date +%F).md` and fill
**every** section: selected issues + why, target branch/worktree, assigned agent, exact
in/out scope, files likely involved, acceptance criteria, test requirements, design/UX
constraints (§5 Padzy), known risks + mitigations, merge order, per-package + global
rollback. This file is the audit trail — precise and complete.

## Step 5 — Create worktrees from `dev`

For each work package (slug = kebab issue name):

```bash
mkdir -p ../tokei-worktrees
git worktree add ../tokei-worktrees/$(date +%F)-<slug> -b patch/$(date +%F)/<slug> dev
# install the fast pre-commit gate into the worktree
cp .claude/hooks/pre-commit ../tokei-worktrees/$(date +%F)-<slug>/.git/hooks/pre-commit 2>/dev/null \
  || cp .claude/hooks/pre-commit "$(git -C ../tokei-worktrees/$(date +%F)-<slug> rev-parse --git-path hooks/pre-commit)"
chmod +x "$(git -C ../tokei-worktrees/$(date +%F)-<slug> rev-parse --git-path hooks/pre-commit)"
```

Then `bash .claude/gates/worktree-sanity.sh ../tokei-worktrees/<...> patch/$(date +%F)/<slug>`
for each. Worktrees live OUTSIDE the repo (`../tokei-worktrees/`) so they never pollute
the main checkout. (Prefer the `superpowers:using-git-worktrees` skill if available.)

## Step 6 — Gates created / verified

Confirm and list: preflight · worktree-sanity · lint · format · build · test ·
no-secret · no-large-artifact · no-uncommitted, plus the per-worktree pre-commit hook.
State which run per-commit (no-secret, no-large-artifact, format) vs at-merge (build, test).

## Step 7 — Padzy taste rules (attach to every UI package)

Premium macOS quality, no generic SaaS look; clean information hierarchy; polished
empty/loading/error states; strong visual consistency; accent `#FF3B70` = state/action only.

UI is LOCKED to Claude Code (Step 3). The dedicated Claude Code UI agent runs the `padzy-os`
skill with the Tokei **"aitracker"** theme (tokens below; also Bible §5), Functional tier
(Dense for menu bar / tables), plus `frontend-design` where useful. **No non-Claude agent is
ever assigned a UI package.** The tokens below still travel in the Bible as reference and as
a guard if a non-UI agent incidentally touches a view.

aitracker theme (inline verbatim for non-Claude agents):
ground `#131316` · surface `#1D1D22` · ink `#ECECF1` · muted `#6E6E78` · ONE accent `#FF3B70`
(accent = active/running/primary-action only; cost values use ink, never accent). Mono for all
numeric data. No shadows, no gradients, no rounded card grids, radius ≤ 4px. Numbered mono
kickers (`01 / OVERVIEW`). Exposed 1px hairline structure. 2px accent tick on active state.
Real empty / loading / error states on every surface.

## Step 8 — Emit one copy-paste prompt per agent

For each work package output a fenced block the user can paste verbatim into that agent.
Every prompt MUST contain, in this shape:

```
cd <ABSOLUTE worktree path>
Work ONLY in this directory. Never touch the main repo or another worktree.

You are <AGENT> on Tokei. Branch: patch/<date>/<slug> (already checked out here).
Read the Patch Bible first: <repo>/tasks/patch-bibles/<date>.md  →  work package WP-<n>.

Issue: <id + one line>
Scope IN: <files/modules you may edit>
Scope OUT: everything else, and NEVER change frozen contracts (Bible §4).
Skills: internal skills (padzy-os/superpowers/security-review/simplify/caveman) run ONLY in
  Claude Code. If you are NOT Claude Code, do not reference them — follow inlined rules.
Design (UI packages are Claude-Code-only — LOCKED):
  - This UI package runs in Claude Code → run the padzy-os skill, Tokei "aitracker"
    theme (Bible §5). No non-Claude agent is ever assigned a UI package.

Acceptance criteria: <bulleted, testable>
Tests to run before you finish (regenerate first — .xcodeproj is gitignored):
  cd AIUsageDashboard && xcodegen generate
  xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardCore -destination 'platform=macOS' test
Add/keep tests for your change; existing tests must stay green.

Commit ONLY in this worktree (small, reviewable commits). Do NOT merge, do NOT push,
do NOT open a PR. The pre-commit hook runs secret/artifact/format checks — respect it.

When done, APPEND a completion note to the Patch Bible §8 (branch+commits, what's done,
what's stubbed, tests run + result, files touched, risks). Then stop.
```

Tailor scope/criteria/tests per package. Keep prompts self-contained.

## Output (produce all of these)

1. **Prioritized issue plan** (scored table + selection rationale).
2. **Worktree map** (path → branch → agent).
3. **Agent assignment table.**
4. **Agent prompts** (one fenced block each).
5. **Gates created/verified.**
6. **Next command:** tell the user to run **`/agents-done`** once agents have committed.

Do not launch the external agents yourself — you emit prompts the user dispatches.
