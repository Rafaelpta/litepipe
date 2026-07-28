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
# HFS+ because APFS .DS_Store layouts don't render reliably on older systems (and
# it lets the Finder step below tell our volume apart from any other mounted
# volume that happens to share the name, e.g. a previously opened litepipe.dmg).
hdiutil create -volname "$VOL" -fs HFS+ -srcfolder "$STAGE" -format UDRW -ov litepipe-rw.dmg >/dev/null
rm -rf "$STAGE"

ATTACH_OUT="$(hdiutil attach litepipe-rw.dmg -noautoopen)"
DEV="$(echo "$ATTACH_OUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT="$(echo "$ATTACH_OUT" | grep -o '/Volumes/.*$' | head -1)"
[ -d "$MOUNT" ] || { echo "mount failed"; exit 1; }

# Volume icon (shows on the mounted disk and the DMG file itself).
if [ -f "Resources/AppIcon.icns" ]; then
  cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
  command -v SetFile >/dev/null && SetFile -a C "$MOUNT"
fi

# Finder layout: fixed 660x400 window, icon view, background, icon positions.
# Address our volume as "first HFS+ disk named $VOL" so a stuck or user-mounted
# copy of a released (APFS-imaged) litepipe.dmg can't receive the layout instead.
osascript <<EOF
tell application "Finder"
  tell (first disk whose name begins with "$VOL" and format is Mac OS Extended format)
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

# Finder flushes the layout into .DS_Store asynchronously; without this wait the
# converted DMG ships without background/positions (default alphabetical window).
for i in $(seq 1 10); do
  [ -s "$MOUNT/.DS_Store" ] && break
  sleep 1
done
[ -s "$MOUNT/.DS_Store" ] || echo "warning: .DS_Store not written - layout may be lost"
sleep 2

sync
# Finder can briefly hold the volume after writing .DS_Store; retry the detach.
for i in 1 2 3 4 5; do
  hdiutil detach "$DEV" >/dev/null 2>&1 && break
  sleep 2
  [ "$i" = 5 ] && hdiutil detach "$DEV" -force >/dev/null
done
hdiutil convert litepipe-rw.dmg -format UDZO -o "$DMG" >/dev/null
rm -f litepipe-rw.dmg

echo "created ./$DMG ($(du -h "$DMG" | cut -f1))"
