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
  HARDENED=YES
else
  SIGN_ID="-"
  SIGN_FLAGS=""
  # Hardened runtime MUST be off whenever we sign ad-hoc. Hardened runtime
  # enables library validation, which requires every loaded library to carry the
  # same Team ID as the process. An ad-hoc signature carries no Team ID at all,
  # so the check can never be satisfied and dyld refuses to map the embedded
  # framework with "mapping process and mapped file (non-platform) have
  # different Team IDs" — even though both sides report "TeamIdentifier=not set".
  # CONFIG defaults to Release, whose per-target settings turn hardened runtime
  # ON, so without this override an ordinary dev build produces an app that
  # cannot launch. This overrides ENABLE_HARDENED_RUNTIME for every target in
  # the build, which is exactly the intent: ad-hoc and hardened runtime are
  # mutually exclusive. The signed (TOKEI_RELEASE=1) path keeps it ON —
  # notarization depends on it.
  HARDENED=NO
fi
echo "Signing identity: $SIGN_ID (hardened runtime: $HARDENED)"

# Keep the two signing modes in separate derived-data trees. They were sharing
# one persistent tree, so the first ad-hoc build after a signed build copied in
# a still-Developer-ID-signed Contents/Helpers/tokei: xcodebuild considers that
# target up to date and does not re-sign it, even though the identity changed.
# The result is a cross-contaminated bundle whose helper carries a Team ID the
# app does not. Splitting the path makes each mode's incremental state its own.
if [ "$HARDENED" = "YES" ]; then DERIVED="$ROOT/build/DerivedData-release"
else DERIVED="$ROOT/build/DerivedData-adhoc"; fi

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }

# 1. Generate Xcode project (idempotent; AIUsageDashboard.xcodeproj is gitignored)
(cd "$ROOT" && xcodegen generate)

# 2. Build app headless
xcodebuild -project "$ROOT/AIUsageDashboard.xcodeproj" -scheme AIUsageDashboardApp -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME="$HARDENED" \
  build | tail -5

# 3. Stage output
APP_SRC="$DERIVED/Build/Products/$CONFIG/Tokei.app"
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
  # Sparkle.framework ships its own nested helpers (Autoupdate, Updater.app,
  # XPCServices/*.xpc) that xcodebuild's own signing pass doesn't re-sign with
  # a secure timestamp — notarization rejects them without this. --deep signs
  # innermost-out within the framework bundle.
  SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
  if [ -d "$SPARKLE_FRAMEWORK" ]; then
    codesign --force --deep $SIGN_FLAGS --sign "$SIGN_ID" "$SPARKLE_FRAMEWORK"
  fi
  # The bundled tokei CLI (#57) is copied in by a build phase, so signing the app
  # below (deliberately not --deep) leaves it with xcodebuild's own signature —
  # Developer ID and hardened runtime, but no secure timestamp. Notarization
  # rejects that, so re-sign it here with the same flags as everything else.
  HELPER="$APP/Contents/Helpers/tokei"
  if [ -f "$HELPER" ]; then
    codesign --force $SIGN_FLAGS --sign "$SIGN_ID" "$HELPER"
  fi
  codesign --force $SIGN_FLAGS --sign "$SIGN_ID" "$APP"
fi

# 5. Verify seal
codesign --verify --strict --deep "$ROOT/dist/Tokei.app"

# 6. Verify the app can actually LOAD and STAY UP. A valid seal is not a
# launchable app: a hardened-runtime + ad-hoc build passes step 5 and still dies
# in dyld. verify-app.sh checks signing metadata on every nested executable and
# then requires the app to survive a liveness window — any early exit fails.
# The launch half needs an Aqua session; with no GUI session it is SKIPPED and
# says so explicitly (the static half still runs). Set
# TOKEI_VERIFY_REQUIRE_LAUNCH=1 to turn that skip into a hard failure.
bash "$ROOT/scripts/verify-app.sh" "$ROOT/dist/Tokei.app"

echo "Built: $ROOT/dist/Tokei.app"
