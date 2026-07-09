#!/usr/bin/env bash
# Cut a distributable Tokei build: Developer ID build -> notarize -> staple
# -> DMG -> sign DMG -> notarize DMG -> staple -> Gatekeeper verify.
#
# Prereqs (one-time):
#   - "Developer ID Application" cert in login keychain
#   - xcrun notarytool store-credentials <profile> --apple-id ... --team-id ... --password ...
#   - brew install create-dmg
#
# Usage: scripts/release.sh   # version comes from project.yml MARKETING_VERSION
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${TOKEI_NOTARY_PROFILE:-voxi-notary}"
APP="$ROOT/dist/Tokei.app"

# 1. Build with Developer ID + secure timestamps
TOKEI_RELEASE=1 "$ROOT/scripts/build-app.sh"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
echo "Releasing Tokei $VERSION ($BUILD)"

# 2. Notarize the app (zip upload), then staple the ticket onto the .app
ZIP="$ROOT/dist/Tokei-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# 3. Package, sign, and notarize the DMG (an unsigned DMG fails spctl even
# with a stapled ticket on the app inside it)
"$ROOT/scripts/make-dmg.sh" "$VERSION"
DMG="$ROOT/dist/Tokei-$VERSION-arm64.dmg"
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# 4. Verify exactly what a downloader's Gatekeeper will check
spctl -a -vv -t install "$APP"
spctl -a -vv -t open --context context:primary-signature "$DMG"

# 5. Generate the signed Sparkle appcast for this release
"$ROOT/scripts/gen-appcast.sh"

echo ""
echo "Release artifact: $DMG"
echo "Appcast: $ROOT/dist/appcast.xml"
echo "Next: upload $DMG to the GitHub release, copy dist/appcast.xml -> docs/appcast.xml, commit + push."
