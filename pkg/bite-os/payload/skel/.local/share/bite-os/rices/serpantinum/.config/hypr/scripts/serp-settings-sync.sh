#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# serp-settings-sync — mirror serpantinum's live state into the rice vault.
#
# Two separate places matter, and only one of them is obvious:
#   ~/.config/serpantinum/settings.json      theme, bar modules, notifications
#   ~/.local/state/serpantinum/widgets/      widget LAYOUT (positions/sizes) —
#                                            what the widget redactor writes
# Both are rice-managed, so without this a change lives only in the live tree
# until someone remembers `rice save`, and the next swap silently reverts it.
#
# Exits immediately unless serpantinum is the active rice. Never touches
# another rice's vault entry.

SRC_CFG="$HOME/.config/serpantinum"
SRC_STATE="$HOME/.local/state/serpantinum"
VAULT="$HOME/.local/share/bite-os/rices/serpantinum"
ACTIVE_FILE="$HOME/.local/share/bite-os/rices/.active"
CACHE_DIR="$HOME/.cache/serp-settings-sync"
mkdir -p "$CACHE_DIR"

# Single-instance guard. noclobber, NOT flock: inotifywait is a child here and
# would inherit and pin an flock fd if this script died first — the same defect
# that let settings_watcher stack up and double autostart.conf.
LOCK="$CACHE_DIR/sync.pid"
_take_lock() { ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; }
if ! _take_lock; then
    _holder="$(cat "$LOCK" 2>/dev/null)"
    if [ -n "$_holder" ] && kill -0 "$_holder" 2>/dev/null; then exit 0; fi
    rm -f "$LOCK"; _take_lock || exit 0
fi
# NOTE: a TERM/INT/HUP handler that does not exit makes bash run the handler
# and RESUME -- the script then ignores SIGTERM forever and piles up across
# reloads, which is exactly what happened before. Always exit from it.
cleanup() { rm -f "$LOCK"; [ -n "${CFG_WATCH:-}" ] && kill "$CFG_WATCH" 2>/dev/null; }
trap 'cleanup' EXIT
trap 'cleanup; exit 0' INT TERM HUP

active_is_serpantinum() {
    [ "$(cat "$ACTIVE_FILE" 2>/dev/null)" = "serpantinum" ]
}

# settings.json: validate before mirroring so a half-written file never lands
sync_settings() {
    local src="$SRC_CFG/settings.json" dst="$VAULT/.config/serpantinum/settings.json"
    [ -f "$src" ] || return 0
    jq -e . "$src" >/dev/null 2>&1 || return 0
    cmp -s "$src" "$dst" && return 0
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst.tmp" && mv -f "$dst.tmp" "$dst"
}

# widget layouts: one layout.json per monitor, written by the widget redactor
sync_widgets() {
    local src="$SRC_STATE/widgets" dst="$VAULT/.local/state/serpantinum/widgets"
    [ -d "$src" ] || return 0
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        jq -e . "$f" >/dev/null 2>&1 || continue
        # NB: two statements. `local a=x b=$a` expands $a BEFORE assigning a,
        # so combining these silently produced out="$dst/" (a directory).
        local rel="${f#$src/}"
        local out="$dst/$rel"
        cmp -s "$f" "$out" && continue
        mkdir -p "$(dirname "$out")"
        cp -a "$f" "$out.tmp" && mv -f "$out.tmp" "$out"
    done < <(find "$src" -type f -name '*.json' 2>/dev/null)
}

sync_all() { active_is_serpantinum || return 0; sync_settings; sync_widgets; }

sync_all
command -v inotifywait >/dev/null || exit 0
# Watch both trees; -r on state/widgets so per-monitor subdirs are covered.
inotifywait -m -q -e close_write,moved_to --format '%w%f' \
    "$SRC_CFG" 2>/dev/null | while read -r _; do sync_all; done &
CFG_WATCH=$!
mkdir -p "$SRC_STATE/widgets"
inotifywait -m -q -r -e close_write,moved_to,create --format '%w%f' \
    "$SRC_STATE/widgets" 2>/dev/null | while read -r _; do sync_all; done
