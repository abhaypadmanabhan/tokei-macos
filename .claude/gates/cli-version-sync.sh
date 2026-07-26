#!/usr/bin/env bash
# cli-version-sync — TokeiCLI.version must equal project.yml MARKETING_VERSION.
# Read-only. FAILS on drift.
#
# Why this gate exists: the tokei helper hardcodes its version string (it is a
# standalone `tool` target with no Info.plist to read). A 0.7.1 build shipped
# reporting `tokei 0.7.0`, which is the first thing you check when working out
# which binary is actually live — so the drift actively misleads debugging.
GATE_NAME="cli-version-sync"; source "$(dirname "$0")/_lib.sh"
require_repo

project_yml="$APP_DIR/project.yml"
main_swift="$APP_DIR/TokeiCLI/main.swift"

[ -f "$project_yml" ] || fail "missing $project_yml"
[ -f "$main_swift" ]  || fail "missing $main_swift"

# MARKETING_VERSION lives under settings.base; take the first match.
marketing="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$project_yml" | head -1)"
cli="$(sed -n 's/^[[:space:]]*static let version = "\([^"]*\)".*/\1/p' \
  "$main_swift" | head -1)"

[ -n "$marketing" ] || fail "could not parse MARKETING_VERSION from project.yml"
[ -n "$cli" ]       || fail "could not parse TokeiCLI.version from TokeiCLI/main.swift"

if [ "$marketing" != "$cli" ]; then
  fail "version drift: project.yml MARKETING_VERSION=$marketing but TokeiCLI.version=$cli
      Fix: set 'static let version = \"$marketing\"' in AIUsageDashboard/TokeiCLI/main.swift"
fi

pass "TokeiCLI.version matches MARKETING_VERSION ($marketing)"
