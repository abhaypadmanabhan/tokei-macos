#!/usr/bin/env bash
# Shared helpers for Tokei workflow gates.
# Source this at the top of every gate:  source "$(dirname "$0")/_lib.sh"
#
# Conventions:
#   - Every gate exits 0 on PASS, non-zero on FAIL.
#   - A gate that cannot run because an OPTIONAL tool is missing prints SKIP
#     and exits 0, UNLESS STRICT_GATES=1 is set (then it FAILS).
#   - All gates are read-only unless their name says otherwise. They never push.

set -euo pipefail

# --- repo root (works from any cwd, including a worktree) ---
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
APP_DIR="${REPO_ROOT}/AIUsageDashboard"
XCODEPROJ="AIUsageDashboard.xcodeproj"
BUILD_SCHEME="AIUsageDashboardApp"
TEST_SCHEME="AIUsageDashboardCore"
DEST="platform=macOS"

STRICT_GATES="${STRICT_GATES:-0}"

# --- pretty output (no color if not a tty) ---
if [ -t 1 ]; then
  _R=$'\033[31m'; _G=$'\033[32m'; _Y=$'\033[33m'; _B=$'\033[34m'; _Z=$'\033[0m'
else
  _R=""; _G=""; _Y=""; _B=""; _Z=""
fi

gate_name="${GATE_NAME:-gate}"

log()  { printf '%s[%s]%s %s\n'      "$_B" "$gate_name" "$_Z" "$*"; }
pass() { printf '%s[%s] PASS%s %s\n' "$_G" "$gate_name" "$_Z" "$*"; exit 0; }
warn() { printf '%s[%s] WARN%s %s\n' "$_Y" "$gate_name" "$_Z" "$*" >&2; }
fail() { printf '%s[%s] FAIL%s %s\n' "$_R" "$gate_name" "$_Z" "$*" >&2; exit 1; }

# skip: optional-tool missing. Honors STRICT_GATES.
skip() {
  if [ "$STRICT_GATES" = "1" ]; then
    fail "$* (STRICT_GATES=1 → treated as failure)"
  fi
  printf '%s[%s] SKIP%s %s\n' "$_Y" "$gate_name" "$_Z" "$*"
  exit 0
}

have() { command -v "$1" >/dev/null 2>&1; }

# The diff range to inspect. Default: staged changes. Override with BASE_REF.
#   BASE_REF=main  → inspect commits/files that differ from main.
diff_files() {
  if [ -n "${BASE_REF:-}" ]; then
    git diff --name-only "${BASE_REF}"...HEAD
  else
    git diff --cached --name-only
    git diff --name-only            # unstaged too, so nothing hides
  fi | sort -u | sed '/^$/d'
}

diff_text() {
  if [ -n "${BASE_REF:-}" ]; then
    git diff "${BASE_REF}"...HEAD
  else
    git diff --cached; git diff
  fi
}

require_repo() { [ -n "$REPO_ROOT" ] || fail "not inside a git repository"; }
