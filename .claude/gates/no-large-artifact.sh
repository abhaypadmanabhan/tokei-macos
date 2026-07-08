#!/usr/bin/env bash
# no-large-artifact — block build artifacts and oversized blobs from the diff.
# Read-only. FAILS on any offender. Max size: MAX_MB (default 5).
GATE_NAME="no-large-artifact"; source "$(dirname "$0")/_lib.sh"
require_repo
max_mb="${MAX_MB:-5}"
max_bytes=$(( max_mb * 1024 * 1024 ))

bad=""
for f in $(diff_files); do
  # forbidden paths / extensions (generated, signed, or binary bundles)
  case "$f" in
    */DerivedData/*|DerivedData/*|*/build/*|build/*|dist/*|*/dist/*) bad+="    artifact path: $f"$'\n'; continue;;
    *.xcuserstate|*.xcworkspacedata~|*.app/*|*.dmg|*.zip|*.pkg|*.ipa) bad+="    build/bundle file: $f"$'\n'; continue;;
    *.xcodeproj/*) bad+="    generated xcodeproj (gitignored, regen via xcodegen): $f"$'\n'; continue;;
  esac
  # oversized (only check files that exist in the worktree)
  if [ -f "$REPO_ROOT/$f" ]; then
    sz=$(wc -c < "$REPO_ROOT/$f" 2>/dev/null || echo 0)
    [ "$sz" -gt "$max_bytes" ] && bad+="    >${max_mb}MB ($((sz/1024/1024))MB): $f"$'\n'
  fi
done

[ -n "$bad" ] && fail "large / artifact files in diff:"$'\n'"$bad"
pass "no large artifacts (limit ${max_mb}MB)"
