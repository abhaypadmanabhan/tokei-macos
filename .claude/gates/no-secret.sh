#!/usr/bin/env bash
# no-secret — scan the diff for secrets and provider credentials.
# Read-only. FAILS on any match. Scope: staged+unstaged, or BASE_REF...HEAD.
GATE_NAME="no-secret"; source "$(dirname "$0")/_lib.sh"
require_repo

diff="$(diff_text || true)"
[ -z "$diff" ] && pass "empty diff, nothing to scan"

# Drop hunks belonging to this gate's own source. The `patterns` array below contains
# secret-shaped string literals (aws_secret_access_key, sk-…, "access_token") that would
# otherwise self-match when .claude/gates/ is part of the scanned diff. Only the gate
# source dir is excluded; every other file (incl. real credentials) is still scanned.
diff="$(printf '%s\n' "$diff" | awk '
  /^diff --git / { skip = ($3 ~ /^a\/\.claude\/gates\//); next }
  !skip
')"
[ -z "$diff" ] && pass "empty diff after excluding gate sources, nothing to scan"

# Only inspect added lines (leading '+', not the '+++' file header).
added="$(printf '%s\n' "$diff" | grep -E '^\+' | grep -Ev '^\+\+\+' || true)"

patterns=(
  'BEGIN [A-Z ]*PRIVATE KEY'                 # PEM private keys
  'AKIA[0-9A-Z]{16}'                         # AWS access key id
  'aws_secret_access_key'
  'sk-[A-Za-z0-9]{20,}'                      # OpenAI-style keys
  'sk-ant-[A-Za-z0-9_-]{20,}'               # Anthropic keys
  'gh[pousr]_[A-Za-z0-9]{20,}'              # GitHub tokens
  'xox[baprs]-[A-Za-z0-9-]{10,}'            # Slack tokens
  'AIza[0-9A-Za-z_-]{20,}'                   # Google API key
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' # JWT
  '"access_token"[[:space:]]*:'              # OAuth token json (e.g. codex auth.json)
  '"refresh_token"[[:space:]]*:'
  '(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{6,}'
)

hits=""
for p in "${patterns[@]}"; do
  m="$(printf '%s\n' "$added" | grep -EIn "$p" || true)"
  [ -n "$m" ] && hits+="  pattern /$p/:"$'\n'"$(printf '%s\n' "$m" | sed 's/^/    /')"$'\n'
done

# Also block committing known-credential files outright.
for f in $(diff_files); do
  case "$f" in
    *auth.json|*.pem|*.p12|*.mobileprovision|*.env|.env.*|*id_rsa*|*credentials*)
      hits+="  credential-like file staged: $f"$'\n' ;;
  esac
done

[ -n "$hits" ] && fail "potential secrets detected — remove before commit:"$'\n'"$hits"
pass "no secrets detected"
