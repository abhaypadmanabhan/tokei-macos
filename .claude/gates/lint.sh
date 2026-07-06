#!/usr/bin/env bash
# lint — SwiftLint if available, else SKIP (WARN). Strict via STRICT_GATES=1.
GATE_NAME="lint"; source "$(dirname "$0")/_lib.sh"
have swiftlint || skip "swiftlint not installed (brew install swiftlint)"
cd "$APP_DIR" || fail "missing $APP_DIR"
if [ -f "$REPO_ROOT/.swiftlint.yml" ] || [ -f "$APP_DIR/.swiftlint.yml" ]; then
  swiftlint lint --quiet --strict || fail "swiftlint reported violations"
else
  swiftlint lint --quiet || fail "swiftlint reported violations"
fi
pass "swiftlint clean"
