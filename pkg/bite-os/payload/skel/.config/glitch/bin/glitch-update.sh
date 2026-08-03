#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GLITCH BITE updater — checks the update server, falls back to a friendly
# offline message until the server actually exists.

SERVER_URL="${GLITCH_UPDATE_URL:-https://updates.glitchbite.local/check}"
ICON="system-software-update"
APP="GLITCH BITE"

if curl -fsS --max-time 4 "$SERVER_URL" >/dev/null 2>&1; then
    notify-send -a "$APP" -i "$ICON" "Update check" "Connected — fetching update info."
else
    notify-send -a "$APP" -i "$ICON" "GLITCH BITE updates" \
        "sorry, no servers are online yet."
fi
