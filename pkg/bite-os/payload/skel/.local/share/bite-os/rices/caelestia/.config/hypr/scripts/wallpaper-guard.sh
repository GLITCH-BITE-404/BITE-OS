#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# wallpaper-guard — background reaper for duplicate/ghost wallpaper daemons.
#
# Why: mpvpaper ghosts (two+ copies of the video wallpaper) silently double your
# idle CPU. The spawn scripts serialize within a shell, but the two desktops
# (caelestia + ilyamiro) don't share a lock, so a cross-shell race can still
# slip an extra through. This watches in the background and cleans up.
#
# Rule: keep at most ONE mpvpaper per monitor (and one hyprpaper). It always
#       keeps the NEWEST instance(s) — the most recently spawned wallpaper is
#       the one you meant — and reaps the older ghosts with a clean
#       CONT -> TERM -> KILL (CONT first so an autopause-frozen ghost can die).
#
# On purpose: create  ~/.cache/bite-os/wallpaper-multi.allow  and the guard
#       leaves mpvpaper alone (e.g. while you're deliberately experimenting).
#       Delete it to re-arm.
#
# Cost: one `ps` every few seconds — negligible. Single-instance via flock.

set -u

CACHE_DIR="$HOME/.cache/bite-os"
ALLOW="$CACHE_DIR/wallpaper-multi.allow"
INTERVAL="${1:-5}"
mkdir -p "$CACHE_DIR"

# Only ever one guard running.
exec 8>"$CACHE_DIR/wallpaper-guard.lock"
flock -n 8 || exit 0

cleanup() { exit 0; }
trap cleanup INT TERM HUP

# How many mpvpaper instances are legitimately allowed = number of monitors.
monitor_count() {
    # Count real monitor blocks. (JSON "id": is unreliable — each monitor also
    # carries activeWorkspace.id + specialWorkspace.id, so it over-counts 3x.)
    local n
    n="$(hyprctl monitors 2>/dev/null | grep -cE '^Monitor ')"
    [[ "${n:-0}" =~ ^[0-9]+$ ]] && (( n >= 1 )) && echo "$n" || echo 1
}

# Reap all but the newest $keep instances of process $name.
reap_extras() {
    local name="$1" keep="$2"
    # "<elapsed_seconds> <pid>", sorted ascending => newest first.
    local rows; mapfile -t rows < <(ps -C "$name" -o etimes=,pid= 2>/dev/null | sort -n)
    local total=${#rows[@]}
    (( total <= keep )) && return 0

    local i pid
    for (( i=keep; i<total; i++ )); do
        pid="${rows[$i]##* }"
        kill -CONT "$pid" 2>/dev/null
        kill -TERM "$pid" 2>/dev/null
    done
    sleep 0.4
    for (( i=keep; i<total; i++ )); do
        pid="${rows[$i]##* }"
        kill -KILL "$pid" 2>/dev/null
    done
    echo "[wallpaper-guard] reaped $((total - keep)) extra $name (kept newest $keep)" >&2
}

while true; do
    if [[ ! -f "$ALLOW" ]]; then
        reap_extras mpvpaper  "$(monitor_count)"
        reap_extras hyprpaper 1
    fi
    sleep "$INTERVAL"
done
