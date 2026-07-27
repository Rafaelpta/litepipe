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

# Bundle the capture engine binary if present (built separately, see Engine.swift).
if [ -f "Resources/screenpipe" ]; then
  cp "Resources/screenpipe" "$APP/Contents/Resources/screenpipe"
  chmod +x "$APP/Contents/Resources/screenpipe"
  echo "bundled engine: Resources/screenpipe"
else
  echo "note: Resources/screenpipe not found - app will use dev fallback (~/projects/litepipe/target/release/screenpipe)"
fi

# Bundle litepipe's own UI sounds (original tones).
if [ -d "Resources/sounds" ]; then
  mkdir -p "$APP/Contents/Resources/sounds"
  cp Resources/sounds/*.wav "$APP/Contents/Resources/sounds/" 2>/dev/null && echo "bundled sounds"
fi

# Sign with a stable local identity if present (so TCC grants persist across
# rebuilds); fall back to ad-hoc otherwise. Replace with an Ottic Developer ID
# for real white-label distribution.
SIGN_ID="litepipe-dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  codesign --force --deep --sign "$SIGN_ID" "$APP"
  echo "signed with: $SIGN_ID (stable)"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
  echo "signed ad-hoc (no stable identity found)"
fi

echo "built ./$APP"
