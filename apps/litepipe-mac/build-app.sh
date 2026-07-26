#!/bin/bash
# Build the executable and wrap it in a proper litepipe.app bundle so the drag
# helper has a real app to drag and macOS TCC has a stable identity to grant.
set -e
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="litepipe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ".build/$CONFIG/litepipe" "$APP/Contents/MacOS/litepipe"
chmod +x "$APP/Contents/MacOS/litepipe"

# Ad-hoc sign so TCC associates grants with a stable identity.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "built ./$APP"
