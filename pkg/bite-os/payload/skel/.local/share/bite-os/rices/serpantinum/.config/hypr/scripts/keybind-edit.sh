#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# keybind-edit — read/modify the keybinds in ~/.config/hypr/settings.json.
#
# settings.json is the single source of truth: settings_watcher.sh regenerates
# config/keybindings.conf from it and reloads hyprland. So NEVER hand-edit the
# .conf — write here and the rest follows automatically.
#
# Usage:
#   keybind-edit.sh list                       JSON array of {i,type,mods,key,dispatcher,command}
#   keybind-edit.sh set <i> <mods> <key> <dispatcher> <command>
#   keybind-edit.sh add <mods> <key> <dispatcher> <command>
#   keybind-edit.sh delete <i>
#   keybind-edit.sh restore                    revert to the last backup
#
# Every write snapshots settings.json first (keeps the 20 most recent).

set -uo pipefail

SETTINGS="$HOME/.config/hypr/settings.json"
BACKUP_DIR="$HOME/.local/state/bite-os/keybind-backups"
mkdir -p "$BACKUP_DIR"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "$SETTINGS" ] || die "no settings.json at $SETTINGS"
jq -e . "$SETTINGS" >/dev/null 2>&1 || die "settings.json is not valid JSON"

snapshot() {
    cp -a "$SETTINGS" "$BACKUP_DIR/settings-$(date +%Y%m%d-%H%M%S).json"
    # keep the newest 20
    ls -1t "$BACKUP_DIR"/settings-*.json 2>/dev/null | tail -n +21 | while read -r f; do rm -f "$f"; done
}

# Write atomically, and only if the result is still valid JSON. A truncated
# settings.json would leave the desktop with no keybinds at all.
commit() {
    local tmp="$1"
    jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die "refusing to write invalid JSON"; }
    mv -f "$tmp" "$SETTINGS"
}

case "${1:-}" in
    list)
        jq -c '[.keybinds[]? | {type: (.type//"bind"), mods: (.mods//""), key: (.key//""),
                                dispatcher: (.dispatcher//"exec"), command: (.command//"")}]
               | to_entries | map(.value + {i: .key})' "$SETTINGS"
        ;;
    set)
        [ $# -ge 5 ] || die "usage: set <i> <mods> <key> <dispatcher> <command>"
        i="$2"; mods="$3"; key="$4"; disp="$5"; shift 5; cmd="${*:-}"
        snapshot
        tmp="$(mktemp "${SETTINGS}.XXXXXX")"
        jq --argjson i "$i" --arg m "$mods" --arg k "$key" --arg d "$disp" --arg c "$cmd" \
           '.keybinds[$i] |= (.mods=$m | .key=$k | .dispatcher=$d | .command=$c)' \
           "$SETTINGS" > "$tmp" || die "jq failed"
        commit "$tmp"; echo ok
        ;;
    add)
        [ $# -ge 4 ] || die "usage: add <mods> <key> <dispatcher> <command>"
        mods="$2"; key="$3"; disp="$4"; shift 4; cmd="${*:-}"
        snapshot
        tmp="$(mktemp "${SETTINGS}.XXXXXX")"
        jq --arg m "$mods" --arg k "$key" --arg d "$disp" --arg c "$cmd" \
           '.keybinds += [{type:"bind", mods:$m, key:$k, dispatcher:$d, command:$c}]' \
           "$SETTINGS" > "$tmp" || die "jq failed"
        commit "$tmp"; echo ok
        ;;
    delete)
        [ $# -ge 2 ] || die "usage: delete <i>"
        snapshot
        tmp="$(mktemp "${SETTINGS}.XXXXXX")"
        jq --argjson i "$2" 'del(.keybinds[$i])' "$SETTINGS" > "$tmp" || die "jq failed"
        commit "$tmp"; echo ok
        ;;
    restore)
        last="$(ls -1t "$BACKUP_DIR"/settings-*.json 2>/dev/null | head -1)"
        [ -n "$last" ] || die "no backups"
        cp -a "$last" "$SETTINGS"; echo "restored $(basename "$last")"
        ;;
    *)
        sed -n '2,22p' "$0" | sed 's/^# \?//'
        ;;
esac
