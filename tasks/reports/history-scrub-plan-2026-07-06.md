# History Scrub Plan — remove leaked Anthropic token fragment (#11)

**Status: DRAFT — awaiting your approval. Nothing destructive has been run.**

## What we're removing
One secret in git history: a truncated `sk-ant-oat01-…` Anthropic OAuth access-token
fragment (+ its expiry timestamp) in `research/raw-findings.md`. Present in ~all commits
since the first (`76a1a60`), live on **public** `main`. Full-history scan found **no other
secrets** (no AWS/GitHub/JWT/Slack keys). Already redacted going forward on dev (`8b9ecae`);
this plan removes it from **history**.

Replacement rules (raw secret kept OUT of the repo — in scratchpad only):
`…/scratchpad/scrub-replacements.txt` →
- the leaked `sk-ant-oat01-…` fragment (exact literal lives only in the scratchpad
  replacements file, never in the repo) → `sk-ant-oat01-[REDACTED]`
- the expiry timestamp → `[REDACTED]`

## Prerequisites (you)
1. **Rotate the Anthropic credential NOW.** History rewrite does NOT un-leak it —
   GitHub keeps unreachable commits reachable by SHA for a while, and any existing
   clone/fork still has it. Rotation is the real fix; the scrub is cleanup.
2. Confirm no one else has in-flight clones/PRs against `main`/`dev` (they'll need to re-clone).

## Steps (me, only after you approve — the force-push is the point of no return)
```bash
cd /Users/abhayp/Downloads/Projects/AI_tracker

# 1. Full mirror backup first (recoverable if anything goes wrong)
git clone --mirror . ../tokei-backup-2026-07-06.git

# 2. Remove the merged worktrees (filter-repo needs a clean single working tree;
#    these branches are already merged into dev)
for wt in ui-padzy-compliance cursor-connector codex-cost-estimate \
          fix-codex-pricing-settings inapp-settings-pane; do
  git worktree remove --force ../tokei-worktrees/2026-07-06-$wt
done

# 3. Rewrite ALL history, replacing the secret in every blob (idempotent).
#    NOTE: rewrites every commit SHA and drops the 'origin' remote by design.
git filter-repo --replace-text \
  "<SCRATCHPAD>/scrub-replacements.txt" --force

# 4. Re-add the remote (filter-repo removed it as a safety measure)
git remote add origin https://github.com/abhaypadmanabhan/tokei-macos.git

# 5. VERIFY the fragment is gone from all history (expect empty output)
git rev-list --all | while read c; do git grep -lI 'sk-ant-oat01-<HEAD-FRAG>' "$c"; done  # head fragment kept in scratchpad only

# 6. Force-push the rewritten history to the PUBLIC repo  ← DESTRUCTIVE, point of no return
git push --force origin main
git push --force origin dev
```

## After
- All commit SHAs change — the release doc's SHA references become historical; I'll
  regenerate them.
- Re-create any worktrees you still need off the new dev.
- Anyone with an old clone must delete and re-clone.
- Consider asking GitHub Support to purge cached unreachable commits, and check for forks.

## Fallback
- Restore from `../tokei-backup-2026-07-06.git` (mirror) if the rewrite goes wrong,
  before the force-push. After force-push, restore by pushing the backup's refs.

## Approval
Reply to run steps 1–5 (safe, local, reversible) and pause before step 6 for a final
look, or approve all the way through the force-push.
