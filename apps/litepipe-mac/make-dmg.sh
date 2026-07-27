#!/bin/bash
# Package litepipe.app into a distributable .dmg (drag-to-Applications layout).
# For real beta distribution the app must first be Developer ID signed + notarized;
# this produces the DMG either way.
set -e
cd "$(dirname "$0")"

APP="litepipe.app"
DMG="litepipe.dmg"
[ -d "$APP" ] || { echo "build $APP first (./build-app.sh release)"; exit 1; }

rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "litepipe" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "created ./$DMG ($(du -h "$DMG" | cut -f1))"
