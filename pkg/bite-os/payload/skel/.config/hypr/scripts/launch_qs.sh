#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# --- BITE-OS shell (re)launcher ---
# Kills any existing quickshell instances and launches exactly one.
# Bound to Super+Shift+R and run once at startup.
#
# NOTE: this script deliberately does NOT touch mpvpaper. The video wallpaper
# is owned by wallpaper.sh; killing it here meant every bar reload nuked your
# wallpaper without restarting it.

set -u

# 1. Tear down any running quickshell instances (prevents the stacking you saw).
#    SIGTERM first for a clean exit, SIGKILL only stragglers.
#    NOTE: the ilyamiro shell runs under the binary name `quickshell` (not
#    `qs`) — it must die too, or it keeps owning the notification D-Bus
#    service and popups stay styled like the other rice.
if pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null; then
    pkill -TERM -x qs 2>/dev/null || true
    pkill -TERM -x quickshell 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null || break
        sleep 0.1
    done
    pkill -KILL -x qs 2>/dev/null || true
    pkill -KILL -x quickshell 2>/dev/null || true
fi

# 2. Launch a single detached instance. setsid so it survives this script
#    exiting; no 'exec ... &' (that was contradictory — exec replaces the
#    process, & backgrounds it, you can't do both).
setsid -f qs -c caelestia -n -d >/dev/null 2>&1
