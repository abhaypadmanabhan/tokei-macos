#!/usr/bin/env bash
# test — regenerate the xcodeproj, then run the Core test suite.
# Requires xcodegen + xcodebuild. FAILS on any test failure.
GATE_NAME="test"; source "$(dirname "$0")/_lib.sh"
have xcodegen  || fail "xcodegen not installed (brew install xcodegen)"
have xcodebuild|| fail "xcodebuild not found (install Xcode command line tools)"
cd "$APP_DIR" || fail "missing $APP_DIR"

log "xcodegen generate"
xcodegen generate >/dev/null || fail "xcodegen generate failed"

log "xcodebuild test ($TEST_SCHEME)"
set -o pipefail
out="$(xcodebuild -project "$XCODEPROJ" -scheme "$TEST_SCHEME" -destination "$DEST" \
  -quiet test 2>&1)" || { printf '%s\n' "$out" | tail -60 >&2; fail "tests failed ($TEST_SCHEME)"; }
# surface the test summary line if present
printf '%s\n' "$out" | grep -Ei 'Test (Suite|Case).*(passed|failed)|Executed [0-9]+ test' | tail -5 || true
pass "tests passed ($TEST_SCHEME)"
