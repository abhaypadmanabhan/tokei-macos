#!/usr/bin/env bash
# Assert that a staged Tokei.app is actually loadable and stays launched — not
# merely that it built and sealed.
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
#   1. Static signing metadata — every nested code item (including Sparkle's
#      Autoupdate, Updater.app and XPC services) must agree with the app on Team
#      ID, and on a release build must also carry hardened runtime and a secure
#      timestamp. Needs no GUI, so this half always runs.
#   2. Launch assertion — run the app and require it to still be alive at the end
#      of the window. This is a POSITIVE signal: silence is not success. Any
#      early exit fails and reports the exit status.
#
# Exit-status policy: an early exit is a FAILURE. An earlier version of this
# script inferred success from the absence of known error strings, so a binary
# that exited 1 immediately still passed. Do not reintroduce that.
#
# Headless: assertion 2 needs an Aqua session. With no GUI session it is
# SKIPPED — reported distinctly and never as OK — while assertion 1 still runs
# and still catches the signing bug this script was written for.
#   TOKEI_VERIFY_REQUIRE_LAUNCH=1  turn that skip into a hard failure (release CI)
#   TOKEI_VERIFY_SKIP_LAUNCH=1     skip the launch assertion unconditionally
#   TOKEI_VERIFY_LAUNCH_SECONDS=N  liveness window, default 6
#
# Usage: bash scripts/verify-app.sh [/path/to/Tokei.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/Tokei.app}"
[ -d "$APP" ] || { echo "verify-app: no app bundle at $APP" >&2; exit 1; }

BIN="$APP/Contents/MacOS/Tokei"
[ -x "$BIN" ] || { echo "verify-app: no executable at $BIN" >&2; exit 1; }

LAUNCH_SECONDS="${TOKEI_VERIFY_LAUNCH_SECONDS:-6}"

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

timestamp_from() {
  local line
  while IFS= read -r line; do
    case "$line" in
      Timestamp=*) printf 'YES'; return ;;
    esac
  done <<<"$1"
  printf 'NO'
}

# ---- 1. Static signing metadata across every nested code item ---------------
APP_DESC="$(describe "$APP")"
APP_TEAM="$(team_from "$APP_DESC")"
APP_RUNTIME="$(runtime_from "$APP_DESC")"
APP_TS="$(timestamp_from "$APP_DESC")"
echo "verify-app: app TeamIdentifier=$APP_TEAM hardened_runtime=$APP_RUNTIME timestamp=$APP_TS"

# An ad-hoc signature carries no Team ID, so hardened runtime can never be
# satisfied. Check this first: it is the root cause of the unlaunchable build,
# and its error message is far clearer than the per-item mismatch below.
if [ "$APP_TEAM" = "not set" ] && [ "$APP_RUNTIME" = "YES" ]; then
  fail "ad-hoc signature (no Team ID) combined with hardened runtime — library validation cannot be satisfied"
fi

# Enumerate nested code rather than hardcoding a list: `codesign --verify --deep`
# proves the seal is intact, NOT that each nested executable carries the expected
# Team ID / runtime flag / timestamp. Sparkle in particular ships Autoupdate,
# Updater.app and two XPC services, all of which notarization inspects
# individually. -type d keeps the Versions/Current and top-level symlinks from
# producing duplicates.
BUNDLES=()
while IFS= read -r b; do
  [ -n "$b" ] && BUNDLES+=("$b")
done < <(find "$APP/Contents" \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -type d 2>/dev/null | sort)

# A Mach-O executable inside an enumerated bundle's Contents/MacOS is that
# bundle's principal executable and is already covered by the bundle itself.
is_covered() {
  local f="$1" b
  [ "$f" = "$BIN" ] && return 0
  for b in "${BUNDLES[@]:-}"; do
    case "$f" in "$b"/Contents/MacOS/*) return 0 ;; esac
  done
  return 1
}

LOOSE=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  FT="$(file -b "$f" 2>/dev/null || true)"
  case "$FT" in
    *Mach-O*executable*|*"Mach-O universal binary"*) ;;
    *) continue ;;
  esac
  is_covered "$f" && continue
  LOOSE+=("$f")
done < <(find "$APP/Contents" -type f -perm -u+x 2>/dev/null | sort)

CODE_ITEMS=("${BUNDLES[@]:-}" "${LOOSE[@]:-}")
CHECKED=0
for NESTED in "${CODE_ITEMS[@]:-}"; do
  [ -n "$NESTED" ] && [ -e "$NESTED" ] || continue
  NAME="${NESTED#"$APP/"}"
  N_DESC="$(describe "$NESTED")"
  N_TEAM="$(team_from "$N_DESC")"
  N_RUNTIME="$(runtime_from "$N_DESC")"
  N_TS="$(timestamp_from "$N_DESC")"
  CHECKED=$((CHECKED + 1))
  echo "verify-app:   $NAME TeamIdentifier=$N_TEAM hardened_runtime=$N_RUNTIME timestamp=$N_TS"

  # Team ID equality is the condition dyld actually enforces: under library
  # validation the loaded library must carry the same Team ID as the process.
  [ "$N_TEAM" = "$APP_TEAM" ] || \
    fail "$NAME Team ID '$N_TEAM' != app Team ID '$APP_TEAM' (library validation will reject it)"

  # Hardened runtime is a property of the PROCESS, not of the library — a
  # hardened vendored framework inside a non-hardened app loads fine, so only
  # assert the flag in the direction that matters. When the app IS hardened,
  # notarization requires it on every nested executable.
  # (Sparkle ships pre-signed with the runtime flag and Xcode preserves it, so
  # requiring strict equality here would fail every ad-hoc dev build.)
  if [ "$APP_RUNTIME" = "YES" ] && [ "$N_RUNTIME" != "YES" ]; then
    fail "$NAME lacks hardened runtime while the app has it — notarization requires it on every nested executable"
  fi

  # Secure timestamps are a notarization requirement too, and are exactly what
  # the inside-out re-sign in build-app.sh exists to add. Only assert when the
  # app itself has one, i.e. on the signed release path — ad-hoc has none.
  if [ "$APP_TS" = "YES" ] && [ "$N_TS" != "YES" ]; then
    fail "$NAME has no secure timestamp while the app does — notarization will reject it"
  fi
done
[ "$CHECKED" -gt 0 ] || fail "found no nested code items to check — enumeration is broken"
# Deliberately not the word "OK": only the final RESULT line states a verdict, so
# a skipped launch assertion can never be misread as a full pass.
echo "verify-app: static signing metadata verified across $CHECKED nested code item(s)"

# ---- 2. Launch assertion ------------------------------------------------------
# Tokei is a menu-bar app: a correct build stays running. Requiring the process
# to be ALIVE at the end of the window is a positive signal. The previous
# version passed whenever stderr merely failed to match a list of English error
# strings, so an immediate exit 1 read as success.
GUI_SESSION="$(launchctl managername 2>/dev/null || true)"

if [ "${TOKEI_VERIFY_SKIP_LAUNCH:-0}" = "1" ]; then
  echo "verify-app: SKIP — launch assertion disabled by TOKEI_VERIFY_SKIP_LAUNCH=1"
  echo "verify-app: RESULT: STATIC CHECKS PASSED, LAUNCH ASSERTION SKIPPED (not a full pass)"
  exit 0
fi

if [ "$GUI_SESSION" != "Aqua" ]; then
  if [ "${TOKEI_VERIFY_REQUIRE_LAUNCH:-0}" = "1" ]; then
    fail "no Aqua GUI session (managername='${GUI_SESSION:-none}') and TOKEI_VERIFY_REQUIRE_LAUNCH=1 — cannot prove the app launches"
  fi
  echo "verify-app: SKIP — no Aqua GUI session (managername='${GUI_SESSION:-none}'); cannot run the launch assertion"
  echo "verify-app: RESULT: STATIC CHECKS PASSED, LAUNCH ASSERTION SKIPPED (not a full pass)"
  echo "verify-app: set TOKEI_VERIFY_REQUIRE_LAUNCH=1 to make this a failure instead"
  exit 0
fi

LOG="$(mktemp -t tokei-verify)"
trap 'rm -f "$LOG"' EXIT

"$BIN" >"$LOG" 2>&1 &
PID=$!

DEADLINE=$((LAUNCH_SECONDS * 4))
for _ in $(seq 1 "$DEADLINE"); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.25
done

# Report the specific loader diagnosis when we have one — it is far more useful
# than "exited early". Checked before the liveness verdict for that reason.
# grep reads a FILE here, not a pipeline, so the SIGPIPE hazard above does not apply.
if grep -qE 'Library not loaded|code signature.*not valid|different Team IDs|Symbol not found|no suitable image found' "$LOG"; then
  echo "verify-app: loader output was:" >&2
  head -20 "$LOG" >&2
  fail "dyld could not load the app's own libraries"
fi

if kill -0 "$PID" 2>/dev/null; then
  # Positive signal: the process survived the window, so dyld resolved every
  # embedded library and main() is running.
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  echo "verify-app: RESULT: PASS — app launched, loaded all embedded libraries and stayed up ${LAUNCH_SECONDS}s"
  exit 0
fi

# Early exit is a failure. Capture the real status instead of discarding it.
EXIT_STATUS=0
wait "$PID" || EXIT_STATUS=$?
if [ "$EXIT_STATUS" -gt 128 ]; then
  echo "verify-app: process died on signal $((EXIT_STATUS - 128))" >&2
fi
if [ -s "$LOG" ]; then
  echo "verify-app: process output was:" >&2
  head -20 "$LOG" >&2
else
  echo "verify-app: process produced no output" >&2
fi
fail "app exited with status $EXIT_STATUS before the ${LAUNCH_SECONDS}s liveness window — a launchable menu-bar app must stay running"
