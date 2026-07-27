#!/usr/bin/env bash
# Assert that a staged Tokei.app is actually loadable, not merely built.
#
# Why this exists: `xcodebuild` succeeding and `codesign --verify --strict --deep`
# exiting 0 do NOT prove the app can launch. A hardened-runtime app signed ad-hoc
# passes both, then dies at load with
#   "mapping process and mapped file (non-platform) have different Team IDs"
# because hardened runtime enables library validation, which requires every
# loaded library to carry the same Team ID as the process — and an ad-hoc
# signature carries none. That shipped an unlaunchable dist/Tokei.app.
#
# Two independent assertions:
#   1. Signature consistency — the app and every nested code item agree on both
#      Team ID and the hardened-runtime flag. This catches the mismatch class
#      directly and statically.
#   2. dyld load check — actually execute the main binary and fail if dyld
#      refuses to map anything. dyld errors occur before main() runs, so this
#      needs no GUI and works headless.
#
# Usage: bash scripts/verify-app.sh [/path/to/Tokei.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/Tokei.app}"
[ -d "$APP" ] || { echo "verify-app: no app bundle at $APP" >&2; exit 1; }

BIN="$APP/Contents/MacOS/Tokei"
[ -x "$BIN" ] || { echo "verify-app: no executable at $BIN" >&2; exit 1; }

fail() { echo "verify-app: FAIL — $*" >&2; exit 1; }

# Parse `codesign -dvv` with bash builtins only — deliberately NO pipelines here.
# Under `set -o pipefail`, `codesign ... | grep -q` makes codesign die of SIGPIPE
# when grep exits early on a match, so the pipeline reports failure on a
# SUCCESSFUL match. That misreads hardened runtime as "off" and would let the
# exact bug this script exists to catch slip through.
describe() { codesign -dvv "$1" 2>&1 || true; }

team_from() {
  local line
  while IFS= read -r line; do
    case "$line" in TeamIdentifier=*) printf '%s' "${line#TeamIdentifier=}"; return ;; esac
  done <<<"$1"
  printf 'not set'
}

runtime_from() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *flags=*)
        case "$line" in *runtime*) printf 'YES' ;; *) printf 'NO' ;; esac
        return ;;
    esac
  done <<<"$1"
  printf 'NO'
}

# ---- 1. Signature consistency across the bundle -----------------------------
APP_DESC="$(describe "$APP")"
APP_TEAM="$(team_from "$APP_DESC")"
APP_RUNTIME="$(runtime_from "$APP_DESC")"
echo "verify-app: app TeamIdentifier=$APP_TEAM hardened_runtime=$APP_RUNTIME"

# An ad-hoc signature carries no Team ID, so hardened runtime can never be
# satisfied. Check this first: it is the root cause of the unlaunchable build,
# and its error message is far clearer than the per-item mismatch below.
if [ "$APP_TEAM" = "not set" ] && [ "$APP_RUNTIME" = "YES" ]; then
  fail "ad-hoc signature (no Team ID) combined with hardened runtime — library validation cannot be satisfied"
fi

for NESTED in \
  "$APP/Contents/Frameworks/AIUsageDashboardCore.framework" \
  "$APP/Contents/Frameworks/Sparkle.framework" \
  "$APP/Contents/Helpers/tokei"
do
  [ -e "$NESTED" ] || continue
  NAME="${NESTED#"$APP/"}"
  N_DESC="$(describe "$NESTED")"
  N_TEAM="$(team_from "$N_DESC")"
  N_RUNTIME="$(runtime_from "$N_DESC")"
  echo "verify-app:   $NAME TeamIdentifier=$N_TEAM hardened_runtime=$N_RUNTIME"
  # Team ID equality is the condition dyld actually enforces: under library
  # validation the loaded library must carry the same Team ID as the process.
  [ "$N_TEAM" = "$APP_TEAM" ] || \
    fail "$NAME Team ID '$N_TEAM' != app Team ID '$APP_TEAM' (library validation will reject it)"

  # Hardened runtime is a property of the PROCESS, not of the library — a
  # hardened vendored framework inside a non-hardened app loads fine, so only
  # assert the flag in the direction that matters. When the app IS hardened,
  # notarization requires every nested executable to be hardened too.
  # (Sparkle ships pre-signed with the runtime flag and Xcode preserves it, so
  # requiring strict equality here would fail every ad-hoc dev build.)
  if [ "$APP_RUNTIME" = "YES" ] && [ "$N_RUNTIME" != "YES" ]; then
    fail "$NAME lacks hardened runtime while the app has it — notarization requires it on every nested executable"
  fi
done

# ---- 2. dyld load check ------------------------------------------------------
# dyld resolves and validates every embedded library before main() runs, so a
# short-lived execution is enough. We only fail on loader/signature errors: a
# process that dies for an unrelated reason (e.g. no GUI session on a headless
# runner) must not fail this assertion.
LOG="$(mktemp -t tokei-verify)"
trap 'rm -f "$LOG"' EXIT

"$BIN" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 24); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.25
done
if kill -0 "$PID" 2>/dev/null; then
  ALIVE=1
  kill "$PID" 2>/dev/null || true
else
  ALIVE=0
fi
wait "$PID" 2>/dev/null || true

if grep -qE 'Library not loaded|code signature.*not valid|different Team IDs|Symbol not found|no suitable image found' "$LOG"; then
  echo "verify-app: loader output was:" >&2
  head -20 "$LOG" >&2
  fail "dyld could not load the app's own libraries"
fi

if [ "$ALIVE" = "1" ]; then
  echo "verify-app: OK — dyld loaded all embedded libraries and the app stayed up"
else
  echo "verify-app: OK — no loader errors (process exited early; not a GUI session?)"
  [ -s "$LOG" ] && { echo "verify-app: process output:"; head -10 "$LOG"; } || true
fi
