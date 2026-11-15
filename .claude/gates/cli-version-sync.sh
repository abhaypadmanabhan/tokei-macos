#!/usr/bin/env bash
# The helper embeds MARKETING_VERSION, rather than maintaining a second string.
# Set TOKEI_CLI_BINARY to additionally verify the real built artifact.
GATE_NAME="cli-version-sync"; source "$(dirname "$0")/_lib.sh"
require_repo

project_yml="$APP_DIR/project.yml"
main_swift="$APP_DIR/TokeiCLI/main.swift"
[ -f "$project_yml" ] || fail "missing project.yml"
[ -f "$main_swift" ] || fail "missing TokeiCLI/main.swift"
marketing="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^" ]*\)".*/\1/p' "$project_yml" | head -1)"
[ -n "$marketing" ] || fail "could not parse MARKETING_VERSION"
tool_settings="$(sed -n '/^  tokei:/,$p' "$project_yml")"
printf '%s\n' "$tool_settings" | grep -Eq 'CREATE_INFOPLIST_SECTION_IN_BINARY:[[:space:]]*YES' || fail "helper must embed its Info.plist"
printf '%s\n' "$tool_settings" | grep -Fq 'INFOPLIST_KEY_CFBundleShortVersionString: $(MARKETING_VERSION)' || fail "helper version must use MARKETING_VERSION"
grep -Fq 'Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")' "$main_swift" || fail "helper must read its embedded build version"
if grep -Eq 'static let version[[:space:]]*=[[:space:]]*"' "$main_swift"; then
    fail "helper version must not be hardcoded"
fi
if [ -n "${TOKEI_CLI_BINARY:-}" ]; then
    [ -x "$TOKEI_CLI_BINARY" ] || fail "TOKEI_CLI_BINARY is not executable"
    actual="$("$TOKEI_CLI_BINARY" version)"
    [ "$actual" = "tokei $marketing" ] || fail "built helper reports $actual; expected tokei $marketing"
fi
pass "helper version derives from MARKETING_VERSION ($marketing)"
