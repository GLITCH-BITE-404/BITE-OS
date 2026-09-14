#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# widget-journal — a change log for serpantinum desktop widgets, and single-
# change undo that REBUILDS widgets through the shell's own widget IPC
# (add / geometry / variant / remove) instead of swapping layout files.
#
#   widget-journal.sh record <old.json> <new.json> <monitor>
#       diff two layouts by wId and append events; called by serp-settings-sync
#       right before it mirrors a layout into the vault
#   widget-journal.sh list [N]      newest first, TSV:
#       eid  kind  type  monitor  when  summary
#   widget-journal.sh undo <eid>    undo one change:
#       removed -> re-create it     moved/resized/rotated/changed -> put it back
#       added   -> remove it
#
# Lives outside the rice-managed dirs so `rice save` never wipes it.

set -u

J_DIR="$HOME/.local/share/bite-os/rices/_widget-history/serpantinum"
JOURNAL="$J_DIR/journal.jsonl"
MAX_EVENTS=300
SHELL_QML="$HOME/.local/share/serpantinum/src/quickshell/Shell.qml"

record() {
    local old="$1" new="$2" mon="$3" ns
    [ -f "$new" ] || return 0
    [[ "$mon" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    ns="$(date +%s%N)"
    mkdir -p "$J_DIR"
    local oldsrc="$old"
    [ -f "$oldsrc" ] || oldsrc=/dev/null
    jq -nc --slurpfile o <(cat "$oldsrc" 2>/dev/null; echo) --slurpfile n "$new" \
        --arg ns "$ns" --arg mon "$mon" '
        def arr: if type == "array" then . else [] end;
        def byid: map(select(.wId != null) | {key: (.wId | tostring), value: .}) | from_entries;
        (($o | map(select(. != null)) | .[0]) // [] | arr) as $O
        | ($n[0] // [] | arr) as $N
        | ($O | byid) as $om | ($N | byid) as $nm
        | [ ($N[] | select(.wId != null and $om[(.wId | tostring)] == null)
                  | {kind: "added", after: .}),
            ($O[] | select(.wId != null and $nm[(.wId | tostring)] == null)
                  | {kind: "removed", before: .}),
            ($N[] | select(.wId != null) | . as $a | $om[(.wId | tostring)] as $b
                  | select($b != null)
                  | if   ($a.wWidth != $b.wWidth or $a.wHeight != $b.wHeight) then {kind: "resized", before: $b, after: $a}
                    elif ($a.wX != $b.wX or $a.wY != $b.wY)                   then {kind: "moved",   before: $b, after: $a}
                    elif ($a.wRotation != $b.wRotation)                       then {kind: "rotated", before: $b, after: $a}
                    elif ($a != $b)                                           then {kind: "changed", before: $b, after: $a}
                    else empty end) ]
        | to_entries[]
        | .value + { eid: ($ns + "-" + (.key | tostring)),
                     ts: (($ns | .[0:10]) | tonumber),
                     mon: $mon,
                     id:   ((.value.after // .value.before).wId | tostring),
                     type: ((.value.after // .value.before).wType // "widget") }
    ' >> "$JOURNAL" 2>/dev/null || return 0
    if [ "$(wc -l < "$JOURNAL")" -gt "$MAX_EVENTS" ]; then
        tail -n "$MAX_EVENTS" "$JOURNAL" > "$JOURNAL.tmp" && mv -f "$JOURNAL.tmp" "$JOURNAL"
    fi
}

mark_undone() {
    printf '{"kind":"_undone","ref":"%s","eid":"u-%s","ts":%s}\n' "$1" "$(date +%s%N)" "$(date +%s)" >> "$JOURNAL"
}

list() {
    local n="${1:-20}"
    [[ "$n" =~ ^[0-9]+$ ]] || n=20
    [ -f "$JOURNAL" ] || return 0
    # undone changes (and the "_undone" marker lines themselves) are hidden
    jq -rs --argjson n "$n" '
        def pos(o): "\(o.wX | floor),\(o.wY | floor)";
        def size(o): "\(o.wWidth | floor)×\(o.wHeight | floor)";
        ([ .[] | select(.kind == "_undone") | .ref ]) as $undone
        | [ .[] | select((.kind | startswith("_")) | not)
                | select(.eid as $e | ($undone | any(. == $e)) | not) ]
        | reverse | .[0:$n][]
        | [ .eid, .kind, .type, .mon, (.ts | strflocaltime("%m/%d %H:%M")),
          ( if   .kind == "added"   then "at " + pos(.after) + " · " + size(.after)
            elif .kind == "removed" then "was at " + pos(.before) + " · " + size(.before)
            elif .kind == "moved"   then pos(.before) + " → " + pos(.after)
            elif .kind == "resized" then size(.before) + " → " + size(.after)
            elif .kind == "rotated" then "\(.before.wRotation // 0)° → \(.after.wRotation // 0)°"
            else "style changed" end ) ] | @tsv' "$JOURNAL" 2>/dev/null
}

ipc() { quickshell -p "$SHELL_QML" ipc call "widgets-$MON" "$@" 2>/dev/null; }

undo() {
    local eid="${1:-}" ev kind id
    [[ "$eid" =~ ^[0-9]+-[0-9]+$ ]] || { echo "bad change id"; return 1; }
    ev="$(grep -F "\"eid\":\"$eid\"" "$JOURNAL" 2>/dev/null | tail -n 1)"
    [ -n "$ev" ] || { echo "change not found"; return 1; }
    MON="$(jq -r '.mon' <<<"$ev")"; kind="$(jq -r '.kind' <<<"$ev")"; id="$(jq -r '.id' <<<"$ev")"
    [[ "$MON" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "bad monitor"; return 1; }

    # the widget's state from before the change, one field per line (keeps empty fields)
    local -a B
    mapfile -t B < <(jq -r '.before // .after | .wType, .wX, .wY, .wWidth, .wHeight,
                            (.wOpacity // 1), (.wImagePath // ""), (.wRotation // 0), (.wVariant // "")' <<<"$ev")
    grep -qF "\"ref\":\"$eid\"" "$JOURNAL" && { echo "already undone"; return 0; }

    local exists=false
    ipc list | jq -e --arg id "$id" 'any(.[]?; (.wId | tostring) == $id)' >/dev/null 2>&1 && exists=true

    case "$kind" in
        removed)
            $exists && { echo "already there"; return 0; }
            # FRESH id: the shell keeps a removed widget in its model (isRemoving),
            # so re-adding the same id made a later `remove` hit the dead copy
            local nid="w_$(date +%s%3N)_$((RANDOM % 1000))"
            ipc add "$nid" "${B[0]}" "${B[1]}" "${B[2]}" "${B[3]}" "${B[4]}" "${B[5]}" "${B[6]}" "${B[7]}" >/dev/null
            [ -n "${B[8]}" ] && ipc variant "$nid" "${B[8]}" >/dev/null
            mark_undone "$eid"
            echo "brought back ${B[0]}"
            ;;
        added)
            $exists || { echo "already gone"; return 0; }
            ipc remove "$id" >/dev/null
            mark_undone "$eid"
            echo "removed ${B[0]}"
            ;;
        moved|resized|rotated|changed)
            $exists || { echo "widget no longer exists"; return 1; }
            ipc geometry "$id" "${B[1]}" "${B[2]}" "${B[3]}" "${B[4]}" "${B[5]}" "${B[7]}" >/dev/null
            if [ "$kind" = "changed" ]; then
                [ -n "${B[8]}" ] && ipc variant "$id" "${B[8]}" >/dev/null
                ipc imagePath "$id" "${B[6]}" >/dev/null
            fi
            mark_undone "$eid"
            echo "put back ${B[0]}"
            ;;
        *) echo "unknown change"; return 1 ;;
    esac
}

case "${1:-}" in
    record) shift; record "${1:-}" "${2:-}" "${3:-}" ;;
    list)   shift; list "${1:-20}" ;;
    undo)   shift; undo "${1:-}" ;;
    *) echo "usage: widget-journal.sh record <old> <new> <monitor> | list [N] | undo <eid>"; exit 1 ;;
esac
