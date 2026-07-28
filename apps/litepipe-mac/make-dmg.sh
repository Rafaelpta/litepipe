#!/bin/bash
# Package litepipe.app into a designed drag-to-Applications DMG: fixed Finder
# window, background art, big icons, volume icon. For real beta distribution the
# app must first be Developer ID signed + notarized.
#
# Two macOS quirks shape this script (both bit us in practice):
# - Once litepipe.app is registered/installed, TCC App Management blocks the
#   shell (and hdiutil's copier) from writing a bundle with that name onto the
#   image. Finder has the permission, so FINDER does the app copy.
# - Finder only flushes the window layout into .DS_Store when IT ejects the
#   volume; detaching underneath it ships a DMG with a default window.
# The Finder steps need the one-time Terminal -> Finder Automation approval.
set -e
cd "$(dirname "$0")"

APP="litepipe.app"
DMG="litepipe.dmg"
VOL="litepipe"
BG="Resources/dmg-background.png"
[ -d "$APP" ] || { echo "build $APP first (./build-app.sh release)"; exit 1; }

rm -f "$DMG" litepipe-rw.dmg

# Any mounted litepipe volume (a previously opened release DMG) would steal the
# mountpoint AND match the Finder disk query below, sending the layout to a
# read-only volume. Clear them all so the build volume gets the exact name.
for v in /Volumes/${VOL}*; do
  [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1 || true
done

# Blank read-write image; contents are copied in while it is mounted.
hdiutil create -size 250m -volname "$VOL" -fs HFS+ litepipe-rw.dmg >/dev/null
ATTACH_OUT="$(hdiutil attach litepipe-rw.dmg -noautoopen)"
DEV="$(echo "$ATTACH_OUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT="$(echo "$ATTACH_OUT" | grep -o '/Volumes/.*$' | head -1)"
[ -d "$MOUNT" ] || { echo "mount failed"; exit 1; }
[ "$MOUNT" = "/Volumes/$VOL" ] || { echo "mountpoint conflict: $MOUNT (eject other litepipe volumes)"; hdiutil detach "$DEV" >/dev/null 2>&1; exit 1; }

osascript -e "tell application \"Finder\" to duplicate (POSIX file \"$PWD/$APP\" as alias) to (POSIX file \"$MOUNT\" as alias)" >/dev/null
ln -s /Applications "$MOUNT/Applications"
if [ -f "$BG" ]; then
  mkdir "$MOUNT/.background"
  cp "$BG" "$MOUNT/.background/background.png"
fi
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
    -- Read the layout back: if this errors the build must fail rather than
    -- ship a DMG with a default window.
    if icon size of (icon view options of container window) is not 100 then
      error "layout not applied (icon size)"
    end if
    if item 1 of (get position of item "$APP" of container window) is not 165 then
      error "layout not applied (app position)"
    end if
    close
  end tell
end tell
EOF

sync
osascript -e "tell application \"Finder\" to eject (first disk whose name begins with \"$VOL\" and format is Mac OS Extended format)" 2>/dev/null || true
for i in $(seq 1 10); do
  mount | grep -q "on $MOUNT " || break
  sleep 1
done
# Fallback if Finder didn't let go.
if mount | grep -q "on $MOUNT "; then
  for i in 1 2 3 4 5; do
    hdiutil detach "$DEV" >/dev/null 2>&1 && break
    sleep 2
    [ "$i" = 5 ] && hdiutil detach "$DEV" -force >/dev/null
  done
fi
hdiutil convert litepipe-rw.dmg -format UDZO -o "$DMG" >/dev/null
rm -f litepipe-rw.dmg

echo "created ./$DMG ($(du -h "$DMG" | cut -f1))"
