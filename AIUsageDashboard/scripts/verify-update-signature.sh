#!/usr/bin/env bash
# Verify a Sparkle EdDSA enclosure signature against the public key built into the app,
# with no access to the private key. Exit 0 only when the signature is valid for these
# exact DMG bytes and the length attribute equals the file size.
#
# Usage: scripts/verify-update-signature.sh <dmg> <Tokei.app> '<sparkle:edSignature="..." length="...">'
#
# A wrong signature in the appcast makes every user's in-app update fail, so gen-appcast.sh
# runs this before it writes the feed (2026-11-14: the signing key lived on another Mac).
set -euo pipefail
DMG="$1"; APP="$2"; ATTRS="$3"
OPENSSL="${OPENSSL:-/opt/homebrew/bin/openssl}"
[ -x "$OPENSSL" ] || { echo "verify: need OpenSSL 3+ for Ed25519 ($OPENSSL missing)" >&2; exit 2; }

SIG="$(printf '%s' "$ATTRS" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LEN="$(printf '%s' "$ATTRS" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
[ -n "$SIG" ] && [ -n "$LEN" ] || { echo "verify: attributes need sparkle:edSignature and length" >&2; exit 1; }
SIZE="$(stat -f %z "$DMG")"
[ "$LEN" = "$SIZE" ] || { echo "verify: length $LEN != DMG size $SIZE" >&2; exit 1; }

PUB="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# SubjectPublicKeyInfo for Ed25519 = fixed 12-byte prefix + the raw 32-byte key.
{ printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; printf '%s' "$PUB" | base64 -D; } > "$WORK/pub.der"
[ "$(stat -f %z "$WORK/pub.der")" = 44 ] || { echo "verify: SUPublicEDKey is not a 32-byte key" >&2; exit 1; }
printf '%s' "$SIG" | base64 -D > "$WORK/sig.bin"
"$OPENSSL" pkeyutl -verify -pubin -inkey "$WORK/pub.der" -keyform DER -rawin \
  -in "$DMG" -sigfile "$WORK/sig.bin" >/dev/null 2>&1 \
  || { echo "verify: signature does NOT match $APP's public key" >&2; exit 1; }
echo "verify: signature valid for $(basename "$DMG") ($SIZE bytes) with the app's public key"
