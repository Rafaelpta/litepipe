#!/bin/bash
# litepipe installer. Downloads the latest signed DMG from GitHub releases,
# copies the app to /Applications, and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Rafaelpta/litepipe/main/install.sh | bash
set -euo pipefail

REPO="Rafaelpta/litepipe"
APP="litepipe.app"
DEST="/Applications"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'litepipe install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only."
[ "$(uname -m)" = "arm64" ] || die "Apple Silicon only for now."

say "Looking up the latest release"
DMG_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
  | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
[ -n "$DMG_URL" ] || die "no DMG in the latest release yet. Build from source: https://github.com/$REPO"

TMP=$(mktemp -d)
trap 'hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

say "Downloading $(basename "$DMG_URL")"
curl -fL# -o "$TMP/litepipe.dmg" "$DMG_URL"

say "Verifying the signature"
mkdir -p "$TMP/mnt"
hdiutil attach "$TMP/litepipe.dmg" -mountpoint "$TMP/mnt" -nobrowse -quiet
[ -d "$TMP/mnt/$APP" ] || die "the DMG does not contain $APP"
spctl --assess --type execute "$TMP/mnt/$APP" >/dev/null 2>&1 \
  || die "the app failed Gatekeeper verification, refusing to install"

if [ -d "$DEST/$APP" ]; then
  say "Replacing the copy already in $DEST"
  osascript -e 'tell application "litepipe" to quit' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST/$APP"
fi

say "Installing to $DEST"
cp -R "$TMP/mnt/$APP" "$DEST/"

say "Done. Opening litepipe"
open "$DEST/$APP"
