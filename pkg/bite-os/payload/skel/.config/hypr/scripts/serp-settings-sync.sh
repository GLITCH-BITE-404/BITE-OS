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

# Safety net: this sync makes every widget change permanent within a second,
# so on 2026-09-14 an accidental "delete all widgets" overwrote the vault's
# only good copy. Whenever a layout is about to LOSE widgets, park the vault's
# previous version first. Lives outside the rice-managed dirs so `rice save`
# never wipes it. Restore: copy a file back over
# ~/.local/state/serpantinum/widgets/<monitor>/layout.json, then `serpantinum reload`.
WIDGET_HIST="$HOME/.local/share/bite-os/rices/_widget-history/serpantinum"
backup_if_shrunk() {
    local new="$1" old="$2" rel="$3" n o
    [ -f "$old" ] || return 0
    n="$(jq 'if type=="array" then length else 0 end' "$new" 2>/dev/null)" || return 0
    o="$(jq 'if type=="array" then length else 0 end' "$old" 2>/dev/null)" || return 0
    [[ "$n" =~ ^[0-9]+$ && "$o" =~ ^[0-9]+$ ]] || return 0
    [ "$n" -lt "$o" ] || return 0
    mkdir -p "$WIDGET_HIST"
    cp -a "$old" "$WIDGET_HIST/${rel//\//_}-$(date +%Y%m%d-%H%M%S)-${o}widgets.json"
    # keep the newest 30
    ls -1t "$WIDGET_HIST"/*.json 2>/dev/null | tail -n +31 | xargs -r rm -f
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
        backup_if_shrunk "$f" "$out" "$rel"
        # per-change log (added / moved / resized / removed ...) that the Rice
        # tab undoes one change at a time via the shell's widget IPC
        [ -x "$HOME/.config/hypr/scripts/widget-journal.sh" ] && \
            "$HOME/.config/hypr/scripts/widget-journal.sh" record "$out" "$f" "${rel%%/*}"
        # named widget saves: an auto save when the user switched auto-save
        # on (rate-limited inside widget-saves.sh; a no-op when it's off)
        [ -x "$HOME/.config/hypr/scripts/widget-saves.sh" ] && \
            "$HOME/.config/hypr/scripts/widget-saves.sh" auto-tick
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
