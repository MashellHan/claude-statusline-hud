#!/usr/bin/env bash
# Refresh the Pi HUD in the current terminal without requiring tmux or watch.

set -f

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  TARGET="$(readlink "$SOURCE")"
  case "$TARGET" in
    /*) SOURCE="$TARGET" ;;
    *) SOURCE="$DIR/$TARGET" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
INTERVAL="${PI_STATUSLINE_INTERVAL:-2}"
LAST_OUTPUT=""

cleanup() {
  printf '\033[?25h\033[0m'
}
trap cleanup EXIT INT TERM

while :; do
  OUTPUT="$(
    PI_STATUSLINE_PRESET="${PI_STATUSLINE_PRESET:-vitals}" \
      bash "$SCRIPT_DIR/statusline.sh"
  )"
  OUTPUT="${OUTPUT}"$'\n\n'$(printf '\033[2mrefresh %ss | Ctrl-C to stop\033[0m' "$INTERVAL")

  if [ "$OUTPUT" != "$LAST_OUTPUT" ]; then
    printf '\033[?25l\033[H%s\033[J' "$OUTPUT"
    LAST_OUTPUT="$OUTPUT"
  fi
  sleep "$INTERVAL" || exit 0
done
