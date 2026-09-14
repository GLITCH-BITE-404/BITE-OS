#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# widget-saves — named saves of the serpantinum desktop-widget layout (every
# monitor), like rice saves but just for widgets.
#
# Kept OUTSIDE the rice vault on purpose: rice save / restore / load / switch
# never touch this folder, so the list can't reset or reshuffle under you.
#
#   widget-saves.sh save [name]        save the current layout (manual save)
#   widget-saves.sh list               newest first, TSV: id name when count kind
#   widget-saves.sh load <id>          rebuild the widgets exactly as saved
#                                      (auto-saves the current layout first, so
#                                      a load can always be undone)
#   widget-saves.sh delete <id>
#   widget-saves.sh auto on|off|status auto-save when the layout changes
#   widget-saves.sh auto-tick          called by serp-settings-sync on a change
#
# Loading goes through the shell's widget IPC (clear / add / variant) with
# FRESH ids -- the shell keeps removed widgets in its model for a while, and
# re-adding the same id made a later remove hit the dead copy.

set -u

DIR="$HOME/.local/share/bite-os/widget-saves/serpantinum"
STATE="$HOME/.local/state/serpantinum/widgets"
CONF="$HOME/.config/bite-os/widget-saves.conf"
SHELL_QML="$HOME/.local/share/serpantinum/src/quickshell/Shell.qml"
AUTO_KEEP=10          # auto saves kept; manual saves are never pruned
AUTO_MIN_GAP=120      # seconds between auto saves while you're dragging things

mkdir -p "$DIR"

conf_get() { [ -f "$CONF" ] && sed -n "s/^$1=//p" "$CONF" | tail -n 1; }
conf_set() {
    mkdir -p "$(dirname "$CONF")"
    { [ -f "$CONF" ] && grep -v "^$1=" "$CONF"; echo "$1=$2"; } > "$CONF.tmp" && mv -f "$CONF.tmp" "$CONF"
}

# every monitor's layout.json -> {"<monitor>": [widgets...]}
current_layouts() {
    local f mon args=()
    for f in "$STATE"/*/layout.json; do
        [ -f "$f" ] || continue
        mon="$(basename "$(dirname "$f")")"
        [[ "$mon" =~ ^[A-Za-z0-9_-]+$ ]] || continue
        args+=(--slurpfile "m_$mon" "$f")
    done
    [ ${#args[@]} -eq 0 ] && { echo '{}'; return; }
    jq -n "${args[@]}" '$ARGS.named | with_entries(.key |= ltrimstr("m_") | .value |= (.[0] // []))' 2>/dev/null
}

new_id() {
    local id; id="$(date +%Y%m%d-%H%M%S)"
    # same-second collision: bump the time part (base 10 -- "095959" would be
    # read as octal and error) and keep it 6 digits
    while [ -e "$DIR/$id.json" ]; do id="${id%-*}-$(printf '%06d' $(( 10#${id##*-} + 1 )))"; done
    echo "$id"
}

save() {
    local name="${1:-}" kind="${2:-manual}" layouts id
    # names are shown in the UI: keep them printable and short
    name="$(printf '%s' "$name" | tr -d '\000-\037' | cut -c1-60)"
    layouts="$(current_layouts)"
    [ "$(jq '[.[] | length] | add // 0' <<<"$layouts")" -gt 0 ] || { echo "no widgets to save"; return 1; }
    if [ "$kind" = "auto" ]; then
        # skip an auto save that would be identical to the newest save
        local newest; newest="$(ls -1t "$DIR"/*.json 2>/dev/null | head -n 1)"
        if [ -n "$newest" ] && [ "$(jq -cS '.layouts' "$newest")" = "$(jq -cS . <<<"$layouts")" ]; then return 0; fi
    fi
    id="$(new_id)"
    [ -n "$name" ] || name="$([ "$kind" = auto ] && echo "auto" || echo "widgets $(date +'%m/%d %H:%M')")"
    jq -n --arg id "$id" --arg name "$name" --arg kind "$kind" --argjson saved "$(date +%s)" \
          --argjson layouts "$layouts" '{id: $id, name: $name, kind: $kind, saved: $saved, layouts: $layouts}' \
        > "$DIR/$id.json.tmp" && mv -f "$DIR/$id.json.tmp" "$DIR/$id.json"
    [ "$kind" = "auto" ] && prune_auto
    echo "saved '$name'"
}

prune_auto() {
    local f n=0
    while IFS= read -r f; do
        n=$((n + 1)); [ "$n" -gt "$AUTO_KEEP" ] && rm -f "$f"
    done < <(for f in "$DIR"/*.json; do [ -f "$f" ] && [ "$(jq -r '.kind' "$f" 2>/dev/null)" = "auto" ] && echo "$f"; done | xargs -r ls -1t 2>/dev/null)
}

list() {
    local f
    for f in "$DIR"/*.json; do [ -f "$f" ] && cat "$f" && echo; done \
        | jq -rs 'sort_by(-.saved) | .[]
                  | [ .id, .name, (.saved | strflocaltime("%m/%d %H:%M")),
                      ([.layouts[] | length] | add // 0), .kind ] | @tsv' 2>/dev/null
}

ipc() { timeout 5 quickshell -p "$SHELL_QML" ipc call "widgets-$1" "${@:2}" 2>/dev/null; }

load() {
    local id="${1:-}" f
    [[ "$id" =~ ^[0-9]{8}-[0-9]+$ ]] || { echo "bad save id"; return 1; }
    f="$DIR/$id.json"; [ -f "$f" ] || { echo "save not found"; return 1; }
    # a load can always be undone: park what's on screen now
    save "before loading $(jq -r '.name' "$f")" auto >/dev/null 2>&1
    local mon n=0
    for mon in $(jq -r '.layouts | keys[]' "$f"); do
        [[ "$mon" =~ ^[A-Za-z0-9_-]+$ ]] || continue
        [ "$(ipc "$mon" list)" != "" ] || { echo "monitor $mon isn't running — skipped"; continue; }
        ipc "$mon" clear >/dev/null
        sleep 0.3
        local -a W
        while IFS= read -r line; do
            mapfile -t W < <(jq -r '.wType, .wX, .wY, .wWidth, .wHeight, (.wOpacity // 1),
                                    (.wImagePath // ""), (.wRotation // 0), (.wVariant // "")' <<<"$line")
            local nid="w_$(date +%s%3N)_$((RANDOM % 1000))"
            ipc "$mon" add "$nid" "${W[0]}" "${W[1]}" "${W[2]}" "${W[3]}" "${W[4]}" "${W[5]}" "${W[6]}" "${W[7]}" >/dev/null
            [ -n "${W[8]}" ] && ipc "$mon" variant "$nid" "${W[8]}" >/dev/null
            n=$((n + 1))
        done < <(jq -c --arg m "$mon" '.layouts[$m][]' "$f")
    done
    echo "loaded '$(jq -r '.name' "$f")' ($n widgets)"
}

delete() {
    local id="${1:-}"
    [[ "$id" =~ ^[0-9]{8}-[0-9]+$ ]] || { echo "bad save id"; return 1; }
    [ -f "$DIR/$id.json" ] || { echo "save not found"; return 1; }
    rm -f "$DIR/$id.json" && echo "deleted"
}

auto_tick() {
    [ "$(conf_get AUTO)" = "1" ] || return 0
    local stamp="$DIR/.last-auto" now; now="$(date +%s)"
    if [ -f "$stamp" ] && [ $((now - $(cat "$stamp" 2>/dev/null || echo 0))) -lt "$AUTO_MIN_GAP" ]; then return 0; fi
    echo "$now" > "$stamp"
    save "" auto >/dev/null 2>&1
}

case "${1:-}" in
    save)      shift; save "${1:-}" manual ;;
    list)      list ;;
    load)      shift; load "${1:-}" ;;
    delete)    shift; delete "${1:-}" ;;
    auto)      shift
               case "${1:-status}" in
                   on)  conf_set AUTO 1; echo "auto-save on" ;;
                   off) conf_set AUTO 0; echo "auto-save off" ;;
                   *)   [ "$(conf_get AUTO)" = "1" ] && echo on || echo off ;;
               esac ;;
    auto-tick) auto_tick ;;
    *) echo "usage: widget-saves.sh save [name] | list | load <id> | delete <id> | auto on|off|status"; exit 1 ;;
esac
