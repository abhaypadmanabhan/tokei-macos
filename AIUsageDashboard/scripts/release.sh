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

# Submit to the notary service and block until it resolves.
#
# Deliberately NOT `notarytool submit --wait`: that call died with `Bus error: 10`
# mid-poll during the 0.7.1 release, aborting the script even though the upload had
# already landed. Submit, capture the id, then poll `notarytool info` separately.
#
# Also note the parsing: the submit output is captured to a variable and parsed by an
# awk that reads to EOF. Piping submit straight into `grep -m1` makes grep close the
# pipe on the first match, SIGPIPEs notarytool, and `set -o pipefail` turns that into
# a fatal exit 141 — again after a successful upload.
notarize() {
  local target="$1" label="$2" submit_out id status
  submit_out="$(xcrun notarytool submit "$target" --keychain-profile "$PROFILE")"
  printf '%s\n' "$submit_out"
  id="$(printf '%s\n' "$submit_out" | awk '/^  id:/ && !seen { print $2; seen = 1 }')"
  [ -n "$id" ] || { echo "notarize($label): could not parse submission id" >&2; return 1; }
  echo "notarize($label): submission $id"

  # Normally resolves in well under a minute; the ceiling is for Apple-side backlog
  # (a 0.7.1 submission once sat In Progress for 1h27m and had to be resubmitted).
  local i
  for i in $(seq 1 120); do
    status="$(xcrun notarytool info "$id" --keychain-profile "$PROFILE" 2>&1 \
      | sed -n 's/.*status: //p')"
    echo "notarize($label): $status"
    case "$status" in
      Accepted) return 0 ;;
      Invalid|Rejected)
        xcrun notarytool log "$id" --keychain-profile "$PROFILE" || true
        return 1 ;;
    esac
    sleep 20
  done
  echo "notarize($label): still In Progress after ~40min (Apple-side); id $id" >&2
  echo "notarize($label): resubmitting usually clears a wedged submission" >&2
  return 1
}

# 1. Build with Developer ID + secure timestamps
TOKEI_RELEASE=1 "$ROOT/scripts/build-app.sh"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
echo "Releasing Tokei $VERSION ($BUILD)"

# 2. Notarize the app (zip upload), then staple the ticket onto the .app
ZIP="$ROOT/dist/Tokei-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP" app
xcrun stapler staple "$APP"
rm -f "$ZIP"

# 3. Package, sign, and notarize the DMG (an unsigned DMG fails spctl even
# with a stapled ticket on the app inside it)
"$ROOT/scripts/make-dmg.sh" "$VERSION"
DMG="$ROOT/dist/Tokei-$VERSION-arm64.dmg"
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize "$DMG" dmg
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
