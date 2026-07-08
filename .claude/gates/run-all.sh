#!/usr/bin/env bash
# run-all — run gates in a defined order and report a summary table.
# Deterministic order; stops nothing (runs all), exits non-zero if any FAIL.
#
# Usage:
#   run-all.sh fast     # cheap gates only: preflight,no-secret,no-large-artifact,no-uncommitted,format,lint
#   run-all.sh full     # fast + build + test          (default)
#   run-all.sh release  # full + STRICT_GATES=1        (lint/format become hard)
#
# Env passthrough: BASE_REF, MAX_MB, EXPECT_CLEAN, STRICT_GATES.
GATE_NAME="run-all"; source "$(dirname "$0")/_lib.sh"
here="$(cd "$(dirname "$0")" && pwd)"
mode="${1:-full}"
[ "$mode" = "release" ] && export STRICT_GATES=1

case "$mode" in
  fast)    gates=(preflight no-secret no-large-artifact no-uncommitted format lint) ;;
  full|release) gates=(preflight no-secret no-large-artifact no-uncommitted format lint build test) ;;
  *) fail "unknown mode: $mode (use fast|full|release)" ;;
esac

log "mode=$mode  base_ref=${BASE_REF:-<staged>}  strict=${STRICT_GATES:-0}"
declare -a results
rc=0
for g in "${gates[@]}"; do
  printf '\n%s──── %s ────%s\n' "$_B" "$g" "$_Z"
  if bash "$here/$g.sh"; then results+=("PASS  $g"); else results+=("FAIL  $g"); rc=1; fi
done

printf '\n%s══════ SUMMARY (%s) ══════%s\n' "$_B" "$mode" "$_Z"
for r in "${results[@]}"; do
  case "$r" in FAIL*) printf '%s%s%s\n' "$_R" "$r" "$_Z";; *) printf '%s%s%s\n' "$_G" "$r" "$_Z";; esac
done
[ "$rc" = "0" ] && log "ALL GATES GREEN" || warn "one or more gates failed"
exit $rc
