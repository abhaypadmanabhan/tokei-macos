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
