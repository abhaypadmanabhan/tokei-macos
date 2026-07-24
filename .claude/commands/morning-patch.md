---
description: Plan and launch the day's parallel engineering — inspect repo, prioritize issues, write the Patch Bible, create per-agent worktrees from dev, dispatch agents directly via herdr, wait for completion, then automatically collect/verify/merge/gate/build and emit a manual QA checklist.
argument-hint: "[optional: issue filter, e.g. 'labels=bug' or a milestone]"
allowed-tools: Bash(git*), Bash(gh*), Bash(bash .claude/gates/*), Bash(xcodegen*), Bash(xcodebuild*), Bash(grep*), Bash(rg*), Bash(find*), Bash(ls*), Bash(cp*), Bash(chmod*), Bash(mkdir*), Bash(herdr*), Read, Write, Edit, Skill, Agent
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

This is mundane gathering work — do not burn your own context doing it inline.
Spawn it to a Claude Code Agent-tool subagent (model tier: **Sonnet** or smaller —
this is repetitive collection, not judgment), and have it return a concise summary
covering:

- Current branch, `git status --short`, recent commits, existing `git worktree list`.
- **Open issues:** `gh issue list --state open --limit 50` (if `gh` unauthenticated,
  say so and fall back to `tasks/BACKLOG.md` + the README "What Is Stubbed" section).
- **TODOs/FIXMEs:** `rg -n 'TODO|FIXME|HACK|XXX' AIUsageDashboard/AIUsageDashboardApp` (cap output).
- **Failing tests:** `bash .claude/gates/test.sh` (record pass count / failures).
- **Lint/format problems:** `bash .claude/gates/lint.sh`, `bash .claude/gates/format.sh`
  (both SKIP cleanly if swiftlint/swiftformat absent — note that).
- **Product gaps:** read `tasks/BACKLOG.md`, `tasks/todo.md`, README stubbed list,
  `AIUsageDashboard/docs/` roadmap. Note Cursor (stubbed) and Antigravity (skeleton).

Read the subagent's summary and proceed from it — do not re-run the same commands
yourself.

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

## Step 8 — Dispatch via herdr

Requires `HERDR_ENV=1` (check first: `test "${HERDR_ENV:-}" = 1`). If unset, you are
not running inside Herdr — fall back to the old copy-paste behavior for every
package (see the fallback block at the end of this step) and say so plainly.

Build the same self-contained prompt as before for each work package — the content
is unchanged, only the delivery mechanism changes:

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
what's stubbed, tests run + result, files touched, risks), then print the exact line
HERDR_TEST_DONE as your last line if you are cline (marker convention — see below).
```

Tailor scope/criteria/tests per package. Then, per package, resolve its assigned
agent kind and dispatch:

**Kind → verified auto-approve flag** (no permission prompts; confirmed working
2026-07-23, see `herdr-agent-fleet-test` memory):

| Kind | herdr `--kind` | Auto-approve flag |
|---|---|---|
| Claude Code | `claude` | `--dangerously-skip-permissions` |
| Codex | `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| Cursor | `cursor` | `--trust --force` |
| opencode | `opencode` | `--auto` — **this repo's opencode is pinned to a local model: 80s+ per response is normal, not stalled, and it has crashed once (Bun segfault). Treat as the least reliable/slowest kind; give it a much longer timeout than the others.** |
| Cline | `cline` | `--auto-approve true` (also its CLI default) |
| Antigravity | `agy` | `--dangerously-skip-permissions` — like cline, **no herdr lifecycle tracking**; submit via `pane send-text`+`pane send-keys enter` (not `agent prompt`), and confirm completion only via a task-specific marker string appended to the prompt (same convention as cline — e.g. "print HERDR_TEST_DONE as your last line"), read back with `pane read`; never trust `agent_status` for it. The herdr skill must be installed into its own plugin system first (`agy plugin install`, one-time — already done as of 2026-07-24, see `herdr-agent-fleet-test` memory) or it won't recognize itself as running inside herdr. |
| Kimi | `kimi` | **untested — do not herdr-dispatch until a flag is verified.** Treat like GLM: fall back to the copy-paste block for any Kimi-assigned package until this row is updated with a confirmed flag. |
| **GLM** | **not a herdr kind today** | **no herdr dispatch available — fall back to printing the copy-paste block for this package only, and say so in Output** |

For each herdr-dispatchable package:

```bash
herdr pane split --current --direction right --cwd "<ABSOLUTE worktree path>" --no-focus
# → read new pane_id from .result.pane.pane_id
herdr agent start "<wp-slug>" --kind <kind> --pane <pane_id> --timeout 45000 -- <verified-flag>
```

Submit the prompt:
- **claude / codex / opencode:** `herdr agent prompt "<wp-slug>" "<prompt text>" --wait --timeout <ms>`
  (use a long timeout for opencode per the caveat above).
- **cursor / cline:** these apply bracketed-paste text asynchronously — submit as two
  separate calls instead: `herdr pane send-text <pane_id> "<prompt text>"` then
  `herdr pane send-keys <pane_id> enter`. Cursor still has real lifecycle tracking
  afterward (`agent wait`); cline does not — its `agent_status` is not trustworthy,
  confirm completion only via the `HERDR_TEST_DONE`-style marker you asked it to
  print, read back with `herdr pane read <pane_id> --source recent-unwrapped`.

If a prompt lands in the composer but doesn't submit (`agent_prompt_stalled`), don't
resend the text — send one bare `herdr agent send-keys "<name>" enter` and re-check.

## Step 8.5 — Wait for the fleet, surface blockers

Poll the dispatched agents rather than babysitting synchronously. Loop (bounded —
e.g. 20 iterations max so this can never hang forever):

- claude/codex/cursor: `herdr agent wait "<name>" --until blocked --timeout 60000`
  (or poll `herdr agent list` for status) run concurrently across all dispatched
  names.
- cline: poll `herdr pane read <pane_id> --source recent-unwrapped` for its
  completion marker; ignore `agent_status` for it entirely.
- opencode: same polling, much longer per-iteration timeout (local model).

**`agent_status` is not sufficient proof of completion — it can report `idle` for an
agent that actually stopped to ask a real question.** Verified live 2026-07-24: Codex
correctly stopped mid-task and asked a scope question, but herdr reported it as
`idle`, not `blocked`. Before moving ANY agent from `done`/`idle` to "ready for
collection," read its pane output (`herdr agent read <name> --source
recent-unwrapped` or `herdr pane read <pane_id>`) and check whether it contains an
unresolved question, a request for permission, or anything else that isn't a genuine
finished/stopped state. If it does, treat it as blocked: surface it immediately (name,
pane id, pane contents) so the human can intervene, same as an explicit `blocked`
status — do not silently collect it. Agents reporting `blocked` from herdr itself are
surfaced the same way. Do not silently retry a blocked agent. Agents still `working`
loop again. If the iteration cap is hit with packages still outstanding, stop and
report exactly which ones, rather than hanging.

Once every dispatched package is done or explicitly quarantined-by-timeout, continue
directly to Step 9 in the same run — do not stop and wait for the user to type
anything.

## Step 9 — Auto-collect (was: tell the user to run `/agents-done`)

**If any package fell back to a copy-paste prompt** (`HERDR_ENV` unset, or a
GLM/kind-with-no-herdr-support package — see the Fallback block below), do NOT run
this step automatically for those packages. Stop and ask the human to confirm each
fallback package is committed before including it in collection; auto-collect only
the herdr-dispatched packages that Step 8.5 actually confirmed done. Do not infer
"probably committed by now" — get an explicit yes.

Once every herdr-dispatched package is confirmed done (and any fallback packages are
either confirmed committed by the human or explicitly excluded), execute
`.claude/commands/agents-done.md` Steps 1–7 now, inline, in this same run, exactly as
written there (inspect every worktree, quarantine gate, verify + merge accepted
worktrees in Bible §2 order, full gate run on `dev`, build a testable dev `.app`,
emit the tailored manual QA checklist). That file's step logic is the source of
truth — read it and follow it; do not duplicate or diverge from it here.

For the diff-review sub-step specifically (agents-done Step 4.1 — reading each
merge diff and judging architecture-rule compliance before merging): spawn it to a
Claude Code Agent-tool subagent tiered **Opus** — this is the risky, judgment-heavy
gate that decides what reaches `dev`, not mundane collection.

## Output (produce all of these)

1. **Prioritized issue plan** (scored table + selection rationale).
2. **Worktree map** (path → branch → agent).
3. **Agent assignment table.**
4. **Dispatch log** — which packages went via herdr (kind + pane id) vs. fell back
   to a copy-paste block (GLM, or `HERDR_ENV` unset).
5. **Gates created/verified.**
6. **Fleet wait outcome** — done/blocked/timed-out per package.
7. **Collection results** — everything `/agents-done` used to output: per-agent
   summary, what merged (shas + order), what was quarantined and why, gate/build
   output, dev build path, manual QA checklist.
8. **Next step:** `/dev-approved` if you expect manual testing to pass, or point at
   `/dev-reject` if something's already known-broken.

### Fallback (no herdr, or GLM packages)

For any package without herdr dispatch, output its fenced copy-paste prompt block
(same shape as above) instead, and do not include it in Step 8.5's polling — it
will only enter Step 9's collection once the human confirms it's committed.
