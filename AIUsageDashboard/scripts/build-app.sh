#!/usr/bin/env bash
# Build Tokei.app: xcodegen -> xcodebuild -> dist/Tokei.app
# Env: TOKEI_RELEASE=1 -> Developer ID Application signing + hardened runtime
#      + secure timestamp (required for notarization). Default: ad-hoc ("-"),
#      no hardened runtime, for day-to-day dev builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${TOKEI_CONFIG:-Release}"

if [ "${TOKEI_RELEASE:-0}" = "1" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
  [ -n "$SIGN_ID" ] || { echo "TOKEI_RELEASE=1 but no 'Developer ID Application' identity in keychain" >&2; exit 1; }
  SIGN_FLAGS="--options runtime --timestamp"
else
  SIGN_ID="-"
  SIGN_FLAGS=""
fi
echo "Signing identity: $SIGN_ID"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }

# 1. Generate Xcode project (idempotent; AIUsageDashboard.xcodeproj is gitignored)
(cd "$ROOT" && xcodegen generate)

# 2. Build app headless
xcodebuild -project "$ROOT/AIUsageDashboard.xcodeproj" -scheme AIUsageDashboardApp -configuration "$CONFIG" \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGNING_ALLOWED=YES \
  build | tail -5

# 3. Stage output
APP_SRC="$ROOT/build/DerivedData/Build/Products/$CONFIG/Tokei.app"
mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Tokei.app"
ditto "$APP_SRC" "$ROOT/dist/Tokei.app"

# 4. Re-sign inside-out (nested code first, app last) with the secure timestamp
# + hardened runtime notarization needs. xcodebuild's own signing pass during
# `build` already used the right identity, but doesn't add --timestamp, so
# notarization rejects it without this explicit re-sign.
if [ "$SIGN_ID" != "-" ]; then
  APP="$ROOT/dist/Tokei.app"
  FRAMEWORK="$APP/Contents/Frameworks/AIUsageDashboardCore.framework"
  if [ -d "$FRAMEWORK" ]; then
    codesign --force $SIGN_FLAGS --sign "$SIGN_ID" "$FRAMEWORK"
  fi
  codesign --force $SIGN_FLAGS --sign "$SIGN_ID" "$APP"
fi

# 5. Verify seal
codesign --verify --strict --deep "$ROOT/dist/Tokei.app"
echo "Built: $ROOT/dist/Tokei.app"
