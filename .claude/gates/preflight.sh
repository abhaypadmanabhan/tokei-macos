#!/usr/bin/env bash
# preflight — repo status sanity before any orchestration step.
# Read-only. Reports branch, tree cleanliness, worktrees, remote sync.
# FAILS if: not a repo, detached HEAD, or (when EXPECT_CLEAN=1) dirty tree.
GATE_NAME="preflight"; source "$(dirname "$0")/_lib.sh"
require_repo

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "HEAD" ] && fail "detached HEAD — checkout a branch first"
log "branch: $branch"
log "head:   $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"

# worktrees
log "worktrees:"; git worktree list | sed 's/^/    /'

# dirty tree
dirty="$(git status --porcelain)"
if [ -n "$dirty" ]; then
  warn "working tree has uncommitted changes:"; echo "$dirty" | sed 's/^/    /' >&2
  [ "${EXPECT_CLEAN:-0}" = "1" ] && fail "EXPECT_CLEAN=1 but tree is dirty"
else
  log "working tree clean"
fi

# remote sync (best-effort, no fetch to stay fast/offline-safe)
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}'..HEAD 2>/dev/null || echo '?')"
  behind="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo '?')"
  log "vs upstream: ahead $ahead, behind $behind (no auto-fetch)"
else
  log "no upstream tracking branch set"
fi

pass "preflight ok on $branch"
