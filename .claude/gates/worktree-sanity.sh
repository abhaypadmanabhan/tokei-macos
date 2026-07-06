#!/usr/bin/env bash
# worktree-sanity — verify a worktree is on the branch we expect and is not
# the main checkout. Optionally verify touched files stay inside an allowed scope.
#
# Usage:
#   worktree-sanity.sh <worktree-path> <expected-branch> [allowed-path-prefix ...]
# Env:
#   BASE_REF (default: dev)  — scope check compares BASE_REF...HEAD.
GATE_NAME="worktree-sanity"; source "$(dirname "$0")/_lib.sh"

wt="${1:?usage: worktree-sanity.sh <path> <branch> [scope-prefix ...]}"
expect="${2:?expected branch required}"
shift 2 || true
scopes=("$@")
base="${BASE_REF:-dev}"

[ -d "$wt" ] || fail "worktree path does not exist: $wt"
cur="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" || fail "not a git worktree: $wt"
[ "$cur" = "$expect" ] || fail "worktree $wt on '$cur', expected '$expect'"

# must not be the primary worktree (main repo root)
top="$(git -C "$wt" rev-parse --show-toplevel)"
main_top="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir | xargs dirname)"
if [ "$top" = "$main_top" ]; then
  warn "worktree resolves to the main checkout — agents must NOT work in the main repo"
fi

log "worktree $wt clean on branch $cur"

# scope check (advisory unless STRICT_GATES=1)
if [ "${#scopes[@]}" -gt 0 ]; then
  files="$(git -C "$wt" diff --name-only "${base}"...HEAD || true)"
  offenders=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    ok=0
    for p in "${scopes[@]}"; do case "$f" in "$p"*) ok=1;; esac; done
    [ "$ok" = "0" ] && offenders+="    $f"$'\n'
  done <<< "$files"
  if [ -n "$offenders" ]; then
    warn "files touched OUTSIDE declared scope (${scopes[*]}):"; printf '%s' "$offenders" >&2
    [ "$STRICT_GATES" = "1" ] && fail "out-of-scope changes with STRICT_GATES=1"
  else
    log "all changes within declared scope"
  fi
fi

pass "worktree sanity ok: $wt @ $cur"
