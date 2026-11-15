#!/usr/bin/env bash
# Package dist/Tokei.app into a DMG.
# Prereqs: scripts/build-app.sh ran; brew install create-dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Tokei.app"
VERSION="${1:-$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 0.0.0)}"
OUT="$ROOT/dist/Tokei-$VERSION-arm64.dmg"

[ -d "$APP" ] || { echo "missing $APP — run scripts/build-app.sh first" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg missing: brew install create-dmg" >&2; exit 1; }

rm -f "$OUT"

# create-dmg lays the window out by scripting Finder, and Finder does not answer scripts
# while the screen is locked (0.13.0, an unattended overnight release: "AppleEvent timed
# out (-1712)" after the app was already notarized). The layout is only a .DS_Store, and
# the names in it never change, so the fallback stages the same folder with the saved
# layout from a release made the normal way and builds the image with hdiutil alone.
finder_answers() {
  osascript -e 'with timeout of 10 seconds' -e 'tell application "Finder" to get name of startup disk' \
    -e 'end timeout' >/dev/null 2>&1
}
if ! finder_answers; then
  LAYOUT="$ROOT/scripts/dmg-layout/DS_Store"
  [ -f "$LAYOUT" ] || { echo "Finder is not answering and $LAYOUT is missing" >&2; exit 1; }
  echo "make-dmg: Finder is not answering scripts; using the saved window layout"
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  ditto "$APP" "$STAGE/Tokei.app"
  ln -s /Applications "$STAGE/Applications"
  cp "$LAYOUT" "$STAGE/.DS_Store"
  hdiutil create -volname "Tokei" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
  echo "DMG: $OUT"
  exit 0
fi

create-dmg \
  --volname "Tokei" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "Tokei.app" 165 185 \
  --hide-extension "Tokei.app" \
  --app-drop-link 495 185 \
  --no-internet-enable \
  "$OUT" \
  "$APP"

echo "DMG: $OUT"
