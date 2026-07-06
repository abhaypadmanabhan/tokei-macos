#!/usr/bin/env bash
# build — regenerate the (gitignored) xcodeproj, then build the app scheme.
# Requires xcodegen + xcodebuild. FAILS on any build error.
GATE_NAME="build"; source "$(dirname "$0")/_lib.sh"
have xcodegen  || fail "xcodegen not installed (brew install xcodegen)"
have xcodebuild|| fail "xcodebuild not found (install Xcode command line tools)"
cd "$APP_DIR" || fail "missing $APP_DIR"

log "xcodegen generate"
xcodegen generate >/dev/null || fail "xcodegen generate failed"

log "xcodebuild build ($BUILD_SCHEME)"
set -o pipefail
xcodebuild -project "$XCODEPROJ" -scheme "$BUILD_SCHEME" -destination "$DEST" \
  -quiet build 2>&1 | tail -40 || fail "build failed (scheme $BUILD_SCHEME)"
pass "build succeeded ($BUILD_SCHEME)"
