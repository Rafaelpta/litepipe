#!/bin/bash
# litepipe headless. Runs the capture engine on its own: no app, no icon, no
# window. A local memory filling up in ~/.litepipe for your agent to read.
#
#   curl -fsSL https://raw.githubusercontent.com/Rafaelpta/litepipe/main/headless.sh | bash
#
# Screen Recording and Accessibility permissions belong to the terminal you run
# this from, not to litepipe. Stop it with control C.
set -euo pipefail

REPO="Rafaelpta/litepipe"
HOME_DIR="${LITEPIPE_HOME:-$HOME/.litepipe}"
BIN="$HOME_DIR/bin/screenpipe"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'litepipe headless: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only."
[ "$(uname -m)" = "arm64" ] || die "Apple Silicon only for now."

if [ ! -x "$BIN" ]; then
  say "Fetching the capture engine"
  DMG_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
    | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
  [ -n "$DMG_URL" ] || die "no release yet. Build from source: https://github.com/$REPO"

  TMP=$(mktemp -d)
  trap 'hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
  curl -fL# -o "$TMP/litepipe.dmg" "$DMG_URL"
  mkdir -p "$TMP/mnt"
  hdiutil attach "$TMP/litepipe.dmg" -mountpoint "$TMP/mnt" -nobrowse -quiet
  spctl --assess --type execute "$TMP/mnt/litepipe.app" >/dev/null 2>&1 \
    || die "the download failed Gatekeeper verification, refusing to run it"

  mkdir -p "$HOME_DIR/bin"
  cp "$TMP/mnt/litepipe.app/Contents/Resources/screenpipe" "$BIN"
  cp "$TMP/mnt/litepipe.app/Contents/Resources/bin/ffmpeg" "$HOME_DIR/bin/" 2>/dev/null || true
  cp "$TMP/mnt/litepipe.app/Contents/Resources/bin/ffprobe" "$HOME_DIR/bin/" 2>/dev/null || true
  chmod +x "$HOME_DIR/bin/"*
  say "Engine at $BIN"
fi

say "Recording into $HOME_DIR. Local API on 127.0.0.1:3030. Control C to stop."
export PATH="$HOME_DIR/bin:$PATH"
export SCREENPIPE_NO_UPDATE_CHECK=1
export SCREENPIPE_NO_REMINDERS=1
exec "$BIN" record \
  --data-dir "$HOME_DIR" \
  --use-all-monitors \
  --disable-telemetry \
  --async-pii-redaction \
  --async-image-pii-redaction \
  -a whisper-large-v3-turbo-quantized \
  "$@"
