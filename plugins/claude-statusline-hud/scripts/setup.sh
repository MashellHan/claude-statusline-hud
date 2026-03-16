#!/usr/bin/env bash
# Post-install: inject statusLine config into user settings
# Uses CLAUDE_PLUGIN_ROOT to resolve the dynamic install path

SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SL_CMD="bash ${SCRIPT_DIR}/statusline.sh"

# Ensure settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$HOME/.claude"
  echo '{}' > "$SETTINGS_FILE"
fi

# Check if statusLine is already configured
EXISTING=$(jq -r '.statusLine.command // ""' "$SETTINGS_FILE" 2>/dev/null)
if [ "$EXISTING" = "$SL_CMD" ]; then
  echo "statusLine already configured."
  exit 0
fi

# Inject statusLine config
TMP=$(mktemp)
jq --arg cmd "$SL_CMD" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS_FILE" > "$TMP" && mv "$TMP" "$SETTINGS_FILE"
echo "statusLine configured: $SL_CMD"

# Create default preset if none exists
if [ ! -f "$HOME/.claude/statusline-preset" ]; then
  echo "full" > "$HOME/.claude/statusline-preset"
  echo "Default preset set to: full"
fi
