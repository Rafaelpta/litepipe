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

# The terminal stays quiet while recording: engine output goes to a log file,
# so the panel below (what is captured, where it lives, how to stop) is always
# the last thing on screen instead of scrolling away under engine internals.
LOG="$HOME_DIR/headless.log"
: > "$LOG"

# Short display paths (~ instead of /Users/name) and text styles. DIM is the
# quiet ink for labels, RED pulses the recording dot. Both degrade to plain
# text on terminals without color support.
DIR_S="${HOME_DIR/#$HOME/~}"; BIN_S="${BIN/#$HOME/~}"; LOG_S="${LOG/#$HOME/~}"
DIM=$(printf '\033[2m'); RED=$(printf '\033[31m'); REDDIM=$(printf '\033[2;31m'); N=$(printf '\033[0m')
row() { printf '  %s%-11s%s  %s\n' "$DIM" "$1" "$N" "$2"; }

cat <<'BANNER'

    ___ __             _
   / (_) /____  ____  (_)___  ___
  / / / __/ _ \/ __ \/ / __ \/ _ \
 / / / /_/  __/ /_/ / / /_/ /  __/
/_/_/\__/\___/ .___/_/ .___/\___/
            /_/     /_/

  a local memory of everything you have seen, said or heard
  open source | fully local | agent friendly

BANNER
row "recording"  "screen on all monitors, microphone and system audio"
row "your data"  "open $DIR_S  (never leaves this Mac)"
row "local API"  "http://127.0.0.1:3030"
row "API key"    "$BIN_S auth token"
row "full log"   "$LOG_S"
printf '\n'
row "stop"       "press Control C in this window (or close it)"
row "resume"     "run this script again, memory continues where it left off"
printf '\n'

export PATH="$HOME_DIR/bin:$PATH"
export SCREENPIPE_NO_UPDATE_CHECK=1
export SCREENPIPE_NO_REMINDERS=1

# Engine runs in the background writing to the log; the terminal keeps a live
# recording line: a pulsing red dot plus elapsed time. Control C reaches the
# engine (same process group) which shuts down cleanly; we just stop animating.
"$BIN" record \
  --data-dir "$HOME_DIR" \
  --use-all-monitors \
  --disable-telemetry \
  --async-pii-redaction \
  --async-image-pii-redaction \
  -a whisper-large-v3-turbo-quantized \
  "$@" >> "$LOG" 2>&1 &
ENGINE=$!
trap ' ' INT
tick=0
while kill -0 "$ENGINE" 2>/dev/null; do
  if [ $((tick % 2)) -eq 0 ]; then dot="${RED}\xE2\x97\x8F${N}"; else dot="${REDDIM}\xE2\x97\x8F${N}"; fi
  printf '\r  %b %s%02d:%02d:%02d%s ' "$dot" "$DIM" $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)) "$N"
  tick=$((tick+1))
  sleep 0.5
done
wait "$ENGINE" 2>/dev/null || true

printf '\r                    \r'
printf '  stopped. Your memory is intact: open %s\n\n' "$DIR_S"
