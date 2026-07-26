# /morning-patch live dry run — workflow hindrance log (2026-07-24)

Separate from the Patch Bible. This tracks friction in the NEW herdr-dispatch +
auto-collect pipeline itself (not the product bugs being patched) — anything that
required deviation, manual intervention, a stall, a wrong assumption, or that would
trip up a fresh session running this cold.

## Step 0 — Preflight
- PASS, but WARN: uncommitted changes on `main` — these are this session's own
  pipeline-restructure edits (.claude/README.md, commands/*.md, hooks/pre-commit,
  TEMPLATE.md, tasks/todo.md) never committed before first live use. Not blocking
  (worktrees come from `dev`'s tree, not the dirty `main` working copy, so no
  contamination) but worth deciding: should preflight hard-fail on this before
  creating worktrees, or is WARN-only correct? Flagging, not fixing mid-run.
- `dev` @ 3e16ed4 is 2 commits behind `main` @ 95f3f8e (the trailing 0.6.1
  version-bump + signed-appcast commits, which are release-only and arguably
  shouldn't be in `dev` anyway). Expected under the documented branch model, not
  a bug — noting for context in case new worktrees look "behind."
- 4 pre-existing worktrees found from 2026-07-22 (codex-parser-cache,
  cursor-cooldown-scope, gemini-signin-docs, plan-cost-presets) — all already
  merged per commit history (95f3f8e/85f512e). Stale leftovers, not cleaned up
  after that release. Not touched this run (out of scope), but the pipeline docs
  don't currently say who's responsible for pruning merged worktrees.

## Step 1/2 — Inspection + prioritization
- Real hygiene gap found (not a herdr issue, a pipeline-completeness gap): issues
  #49/#51/#54 were fully merged into `dev`→`main` on 2026-07-22/23 (commit 85f512e
  names them explicitly) but were never closed on GitHub. Same almost-certainly
  true for #1/#2 (P0, but the features they describe are already shipped per
  README "What Works"). Neither `/agents-done`'s auto-collect nor `/dev-approved`
  currently closes the GitHub issue(s) a merged package addresses — pure gap, no
  step does this today. Worth adding a "close linked issue" sub-step to
  agents-done or dev-approved in a future pass; not fixing mid-run, just logging.
- Delegated Step 1 to a Sonnet-tier general-purpose subagent per the new rule —
  worked cleanly, saved the orchestrator from running ~6 read-only commands
  inline. Report came back well-structured, correctly flagged the MCP issue on
  request, correctly caught 4 stale worktrees. No friction here.

## Step 2/3 — Prioritization near-miss (important)
- Initial selection (before verification) picked #55, #41 as work packages —
  **both already fully shipped** (#55 on 2026-07-22 commit 99b38d8/314 tests;
  #41 on 2026-07-19 across 3 commits). Caught by cross-referencing every
  candidate against prior tasks/patch-bibles/*.md completion logs AND against
  live source (grep for the feature's expected symbols) before locking Step 2.
  Without that extra check, /morning-patch would have dispatched two real coding
  agents to redo already-done work, burned real tokens/API cost, and produced a
  merge conflict or a no-op diff.
- **Root cause: nothing in the pipeline closes a GitHub issue when its work
  merges.** Confirmed this is now a 5th+ instance of the pattern (#41, #48, #49,
  #51, #54, #55 all shipped-but-open). This is systemic, not a one-off.
- **Recommendation for a future pass:** add a step to `/agents-done` (or
  `/dev-approved`) that greps the merged diff/commit messages for "#<N>" and
  either auto-closes via `gh issue close <N> --comment "shipped in <sha>"` or at
  minimum lists "issues this merge appears to close" in its output for the human
  to confirm. Also: `/morning-patch` Step 2 should explicitly instruct
  cross-checking candidates against `tasks/patch-bibles/*.md` before scoring, not
  just against open `gh issue list` — the current Step 1/2 text doesn't say this
  anywhere and should have. Not fixed in this run's doc edits (would need another
  plan-mode round) — flagging for next iteration.
- Net effect on this run: selection dropped from a planned 4 packages to 3
  verified-clean ones (#57, #26-Copilot-half, #19-Core-slice). Judged correct to
  under-fill rather than force a 4th unverified pick.

## Step 5 — Worktree creation + pre-commit hook "install" (pre-existing doc bug, not introduced this session)
- Created all 3 worktrees cleanly from `dev` @ 3e16ed4, `worktree-sanity` N/A-checked
  (script requires args I'll verify at Step 6).
- **Found a real inaccuracy in the existing Step 5 script** (unrelated to the
  herdr work, pre-dates this session): `git -C <worktree> rev-parse --git-path
  hooks/pre-commit` resolves to the **shared main-repo** `.git/hooks/pre-commit`
  for every worktree — confirmed directly (`.git/worktrees/<name>/` has no
  per-worktree `hooks/` subdir; git hooks are shared across all worktrees unless
  `core.hooksPath` is set, which it isn't here). So the "copy the hook into each
  worktree" step doesn't install anything per-worktree — it just re-copies the
  same file to the same single shared location 3 times (harmless, idempotent,
  no damage), but the docs' framing ("installed into each agent worktree's
  `.git/hooks/pre-commit`" — README, morning-patch.md Step 5, pre-commit's own
  header comment) is factually wrong about git's behavior. Not actually broken
  in effect — the one shared hook already fires for commits in any worktree, and
  its own internal logic already resolves gates via `--git-common-dir`
  correctly — but the docs should stop claiming per-worktree isolation that
  doesn't exist. Small doc-wording fix for a future pass, not touched now.

## Step 8 — Dispatch
- All 3 launched clean (correct cwd per pane, correct kind/flags).
- WP-1 (claude/opus): same stall pattern as the earlier fleet test —
  `agent_prompt_stalled`, text landed as a "[Pasted text #1 +29 lines]" block in
  the composer, one bare `agent send-keys enter` submitted it. Consistent,
  reproducible, easy workaround — Step 8's doc text already covers this exact
  case correctly.
- WP-2 (codex): `agent prompt --wait --timeout 120000` got killed by my own Bash
  tool's default 120-second client-side timeout before it returned — NOT a herdr
  failure, confirmed by checking `agent get` right after: codex had actually
  received the prompt fine and was already `working`. Real lesson for next time:
  when calling `herdr agent prompt --wait --timeout <ms>`, pass a Bash tool
  `timeout` parameter comfortably longer than the herdr `--timeout` (or don't
  block synchronously on long dispatches at all — fire the prompt, then poll
  `agent list`/`agent get` separately instead of using `--wait` on a slow agent).
- WP-3 (cline): two-step `pane send-text`+`pane send-keys enter` worked with no
  visible issue (consistent with the earlier fleet test).

## Step 8.5 — Real blocked-state detection gap (important finding)
- WP-2 (Codex) legitimately stopped and asked a scope question: adding
  `ProviderID.copilot` makes existing exhaustive `switch` statements over
  `ProviderID` in UI files fail to compile; fixing requires touching UI files,
  which its prompt explicitly prohibited. It asked permission rather than
  guessing or silently violating scope — correct behavior.
- **But herdr's `agent_status` for this codex session reported `idle`, not
  `blocked`.** The doc's Step 8.5 plan ("poll for `blocked`, surface
  immediately") would have silently treated this as done-and-ready-to-collect
  if I'd only checked status instead of reading the pane content. Real gap:
  codex's herdr integration doesn't (at least in this case) classify "agent
  returned to prompt after explicitly asking a question" as `blocked` the way
  it presumably does for a genuine tool-approval popup. **Lesson: always read
  the pane content on every "idle" agent before treating it as ready for
  collection — don't trust `agent_status` alone, even for kinds with "real"
  lifecycle tracking.** Worth a doc fix: Step 8.5 should say to read output on
  every idle transition, not just act on the status field.
- Decision made as orchestrator: told Codex yes, add the minimal exhaustive-
  switch case arms needed to compile (not full UI/taste work) — this is a
  legitimate judgment call the orchestrator should make live, matching how a
  human running this pipeline would actually respond mid-run.

## Step 8.5 — Fleet completion summary
All 3 packages finished successfully, no timeouts/quarantine-by-cap needed:
- WP-3 (Cline): fastest, ~15 min wall-clock including my dispatch overhead. Clean,
  scoped exactly as instructed, 329 tests green, marker-based completion worked
  perfectly (no false positives/negatives observed).
- WP-2 (Codex): ~7 min to first blocked-in-spirit stop (correctly asked a real
  scope question instead of guessing or silently overreaching), ~1 min more
  after I answered it. 329 tests green, App build green, honest stub for
  undocumented Copilot storage format.
- WP-1 (Claude Opus): ~23.5 min — biggest scope, delivered the FULL feature
  including the stretch-goal MCP stdio server (not just the core writer), 344
  tests green, both `tokei` CLI target and App build clean, wrote its own docs
  file, and proactively flagged a real cross-package compatibility note (WP-2's
  new ProviderID case flows through automatically since it used
  `allCases`/`.rawValue` rather than an exhaustive switch — no conflict expected
  at merge). Best single output of the three, matches "Opus for
  architecture-sensitive work" being the right call.
- No agent violated its file scope. No frozen contract was touched. All three
  independently converged on 329 (or 344, WP-1's own count including its new
  tests) passing tests before WP-1/WP-2 needed to reconcile — good sign the
  file-disjoint scoping in the Bible actually held in practice, not just on paper.

## Step 9 / agents-done Step 5 — Full gate run on dev
- **7/8 PASS, 1 FAIL: `no-uncommitted`.** Build PASS, test PASS (329+ tests),
  no-secret PASS, no-large-artifact PASS — the 3 merged packages themselves are
  completely clean.
- The failure is 100% caused by files unrelated to today's 3 work packages: this
  session's still-uncommitted pipeline-restructure docs (`.claude/README.md`,
  `commands/*.md`, `hooks/pre-commit`, `TEMPLATE.md`, `tasks/todo.md` — from
  earlier in this same session) plus the new Bible/hindrance-log files this run
  created. Per my own standing instruction (never commit without being asked), I
  did NOT commit these to force a clean gate — reporting the real FAIL instead
  and leaving the commit decision to the user.
- **Real design question for a future pass:** `no-uncommitted` is repo-wide, not
  scoped to the day's patch — any unrelated stray uncommitted file anywhere fails
  the full gate run even when the actual merged packages are pristine. That's
  arguably correct behavior (dev should always be fully committed, no exceptions)
  but it means a session that does both pipeline-building AND pipeline-testing in
  one sitting (like this one) will always trip it unless it commits mid-stream.
  Not a bug, just worth the user knowing why this specific run shows a FAIL sign
  overall despite exemplary per-package results.

## Step 9 / agents-done Step 6 — dev build
- First attempt FAILED: `LinkAssetCatalog` — "Assets.car couldn't be copied... Operation
  not permitted" (POSIX). Not a code issue — a stale `build/dev/` derived-data directory
  from a prior build attempt in this session had a permission state the sandbox
  couldn't write into. Fix: `rm -rf` the (gitignored, disposable) `build/dev/` dir and
  rebuild clean — succeeded immediately. Worth a doc note: agents-done Step 6 / the
  `/run` skill should default to a clean derived-data path per run, or at least know
  this failure mode isn't a real build break before reporting it as one.
- Second attempt: **BUILD SUCCEEDED.** `Tokei.app` (v0.6.1) at
  `AIUsageDashboard/build/dev/Build/Products/Debug/Tokei.app`, `tokei` helper correctly
  embedded at `Contents/Helpers/tokei` and runnable (`tokei version` → `tokei 0.6.1`).

## CodeRabbit review (PR #58) — triage
14 actionable comments. 12 fixed directly (fallback-collection guards in morning-patch/
dev-reject, Step 8.5's blocked-detection gap now documented — the exact bug hit live
with Codex today, independently caught by CodeRabbit too — Antigravity/Kimi/GLM table
tightening, ClineMessagesParser TOCTOU fix via bounded read instead of stat-then-read,
MCPServer protocol-version validation, markdown fence labels, README provider list,
Bible scope/count corrections, BATON.md workflow-distinction note, todo.md machine-local
path removed). 1 explicitly skipped (not fixed): Patch Bible §8's shared-file concurrent-
completion-append pattern (multiple agents appending to one Bible file) is a real
architectural gap for TRUE simultaneous completions — CodeRabbit tagged it "Heavy lift"
itself; today's actual agents completed at different times (no real collision), so
tracking as a follow-up rather than redesigning the completion-recording mechanism now.
1 rejected as a misread: CodeRabbit suggested retroactively rewriting the already-
published `tasks/reports/release-notes-0.6.1.md` to include today's new features —
declined, that file is a correct historical record of the 0.6.1 release's own scope;
today's features belong in (and are already in) `release-notes-0.7.0.md`.
