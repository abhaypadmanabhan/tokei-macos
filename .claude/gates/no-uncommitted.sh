#!/usr/bin/env bash
# no-uncommitted — fail if the (work)tree has staged or unstaged changes.
# Usage: no-uncommitted.sh [worktree-path]   (default: current repo)
GATE_NAME="no-uncommitted"; source "$(dirname "$0")/_lib.sh"
target="${1:-$REPO_ROOT}"
dirty="$(git -C "$target" status --porcelain)"
if [ -n "$dirty" ]; then
  fail "uncommitted changes in $target:"$'\n'"$(echo "$dirty" | sed 's/^/    /')"
fi
pass "no uncommitted changes in $target"
