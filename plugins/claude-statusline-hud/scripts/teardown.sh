#!/usr/bin/env bash
# Post-uninstall: remove statusLine config from user settings

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  exit 0
fi

# Only remove if it points to our script
EXISTING=$(jq -r '.statusLine.command // ""' "$SETTINGS_FILE" 2>/dev/null)
if echo "$EXISTING" | grep -q "statusline.sh"; then
  TMP=$(mktemp)
  jq 'del(.statusLine)' "$SETTINGS_FILE" > "$TMP" && mv "$TMP" "$SETTINGS_FILE"
  echo "statusLine config removed."
fi
