#!/usr/bin/env bash
# Generate appcast.xml for the current DMG in dist/.
# Usage: scripts/gen-appcast.sh [release-notes-url]
# Output: dist/appcast.xml — served at the SUFeedURL
# (https://abhaypadmanabhan.github.io/tokei-macos/appcast.xml) via GitHub Pages.
# The DMG itself is uploaded as a GitHub Release asset.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Tokei.app"
REPO="abhaypadmanabhan/tokei-macos"
SPARKLE_ACCOUNT="${TOKEI_SPARKLE_ACCOUNT:-tokei}"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
# Hard floor: project.yml deploymentTarget.
MIN_OS="14.0"
DMG="$ROOT/dist/Tokei-$VERSION-arm64.dmg"
NOTES_URL="${1:-https://github.com/$REPO/releases/tag/v$VERSION}"

[ -f "$DMG" ] || { echo "missing $DMG — run scripts/release.sh first" >&2; exit 1; }

SIGN_UPDATE="$(find "$ROOT/build/DerivedData/SourcePackages/artifacts" -name sign_update -type f 2>/dev/null | grep -v old_dsa_scripts | head -1)"
[ -n "$SIGN_UPDATE" ] || { echo "Sparkle sign_update not found — resolve packages first" >&2; exit 1; }

# sign_update prints: sparkle:edSignature="..." length="..." (both attrs)
SIG_ATTRS="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG")"
DATE="$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"
URL="https://github.com/$REPO/releases/download/v$VERSION/Tokei-$VERSION-arm64.dmg"

cat > "$ROOT/dist/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tokei</title>
    <item>
      <title>Tokei $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIG_ATTRS />
    </item>
  </channel>
</rss>
EOF

echo "Wrote: $ROOT/dist/appcast.xml"
echo "Upload the DMG to the GitHub release, then copy dist/appcast.xml to docs/appcast.xml and push."
