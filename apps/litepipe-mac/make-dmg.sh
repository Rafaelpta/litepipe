#!/bin/bash
# Package litepipe.app into a designed drag-to-Applications DMG: fixed Finder
# window, background art, big icons, volume icon. For real beta distribution the
# app must first be Developer ID signed + notarized.
# Note: the Finder layout step (osascript) triggers a one-time Automation prompt
# (Terminal -> Finder) the first time it runs.
set -e
cd "$(dirname "$0")"

APP="litepipe.app"
DMG="litepipe.dmg"
VOL="litepipe"
BG="Resources/dmg-background.png"
[ -d "$APP" ] || { echo "build $APP first (./build-app.sh release)"; exit 1; }

rm -f "$DMG" litepipe-rw.dmg
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [ -f "$BG" ]; then
  mkdir "$STAGE/.background"
  cp "$BG" "$STAGE/.background/background.png"
fi

# Read-write image first so the Finder layout can be written into its .DS_Store.
# HFS+ because APFS .DS_Store layouts don't render reliably on older systems.
hdiutil create -volname "$VOL" -fs HFS+ -srcfolder "$STAGE" -format UDRW -ov litepipe-rw.dmg >/dev/null
rm -rf "$STAGE"

MOUNT="/Volumes/$VOL"
hdiutil attach litepipe-rw.dmg -mountpoint "$MOUNT" -nobrowse >/dev/null

# Volume icon (shows on the mounted disk and the DMG file itself).
if [ -f "Resources/AppIcon.icns" ]; then
  cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
  command -v SetFile >/dev/null && SetFile -a C "$MOUNT"
fi

# Finder layout: fixed 660x400 window, icon view, background, icon positions.
osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set icon size of opts to 100
    set text size of opts to 13
    set arrangement of opts to not arranged
    if exists file ".background:background.png" then
      set background picture of opts to file ".background:background.png"
    end if
    set position of item "$APP" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    close
    open
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert litepipe-rw.dmg -format UDZO -o "$DMG" >/dev/null
rm -f litepipe-rw.dmg

echo "created ./$DMG ($(du -h "$DMG" | cut -f1))"
