#!/usr/bin/env bash
# format — SwiftFormat lint-check if available, else SKIP (WARN).
# Read-only (uses --lint, never rewrites). Strict via STRICT_GATES=1.
GATE_NAME="format"; source "$(dirname "$0")/_lib.sh"
have swiftformat || skip "swiftformat not installed (brew install swiftformat)"
cd "$APP_DIR" || fail "missing $APP_DIR"
swiftformat --lint AIUsageDashboardApp Tests 2>&1 | sed 's/^/    /' || \
  fail "swiftformat found unformatted files (run: swiftformat AIUsageDashboardApp Tests)"
pass "swiftformat clean"
