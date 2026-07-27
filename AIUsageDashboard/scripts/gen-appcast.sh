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

# Sparkle ships sign_update as an SPM binary artifact, so it only exists inside a
# derived-data tree that has resolved packages. build-app.sh keeps one tree per
# signing mode (build/DerivedData-{release,adhoc}), so consider both explicitly
# and in a fixed order rather than globbing for whichever turns up first — an
# appcast describes a signed release, so the release tree wins when both exist.
# Both resolve the same pinned Sparkle version, so either produces a valid
# signature; the order only makes the choice deterministic.
DERIVED_ROOTS=(
  "$ROOT/build/DerivedData-release"
  "$ROOT/build/DerivedData-adhoc"
)

SIGN_UPDATE=""
for DD in "${DERIVED_ROOTS[@]}"; do
  ARTIFACTS="$DD/SourcePackages/artifacts"
  [ -d "$ARTIFACTS" ] || continue
  # `find | grep -v | head -1` would be shorter, but head exits after one line
  # and kills the upstream process with SIGPIPE, which under `set -o pipefail`
  # makes a SUCCESSFUL match report failure. Read the whole list instead.
  while IFS= read -r CANDIDATE; do
    # old_dsa_scripts/sign_update is the legacy DSA tool, not the EdDSA one.
    case "$CANDIDATE" in *old_dsa_scripts*) continue ;; esac
    [ -x "$CANDIDATE" ] || continue
    SIGN_UPDATE="$CANDIDATE"
    break
  done < <(find "$ARTIFACTS" -name sign_update -type f 2>/dev/null | sort)
  if [ -n "$SIGN_UPDATE" ]; then break; fi
done

if [ -z "$SIGN_UPDATE" ]; then
  echo "Sparkle sign_update not found. Searched:" >&2
  for DD in "${DERIVED_ROOTS[@]}"; do echo "  $DD/SourcePackages/artifacts" >&2; done
  echo "Run scripts/build-app.sh (or TOKEI_RELEASE=1 scripts/build-app.sh) first to resolve packages." >&2
  exit 1
fi
echo "Using Sparkle sign_update: $SIGN_UPDATE"

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
