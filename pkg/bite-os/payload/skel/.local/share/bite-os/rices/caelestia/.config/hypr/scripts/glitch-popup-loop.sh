#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Popup loop while glitch mode is engaged.
# Pops ONE thing at a time at random — skull flash or a hacking terminal —
# waits for it to close, then a random gap before the next.

set -u

STATE="$HOME/.cache/bite-os/glitch.state"
STAGE="$HOME/.bite-os-stage"
SKULL=""
for c in "$STAGE/skull.gif" "$STAGE/fangs.png"; do
    [[ -f "$c" ]] && { SKULL="$c"; break; }
done

# Pick a random hacker-shell command (fall back if a tool is missing).
pick_hack_cmd() {
    local cmds=()
    command -v cmatrix   >/dev/null && cmds+=("cmatrix -b -u 8 -C green")
    command -v cmatrix   >/dev/null && cmds+=("cmatrix -b -u 6 -C red")
    # hollywood intentionally NOT included — it spawns ccze/jp2a/mplayer
    # children that pin CPU at 100% and survive pkill via tmux re-parenting.
    command -v pipes.sh  >/dev/null && cmds+=("pipes.sh -t 0 -p 4 -f 75")
    command -v pipes.sh  >/dev/null && cmds+=("pipes.sh -t 1 -p 6 -f 60")
    [[ ${#cmds[@]} -eq 0 ]] && { echo "echo 'No hacker tools installed'; sleep 8"; return; }
    printf '%s' "${cmds[$((RANDOM % ${#cmds[@]}))]}"
}

# Pick one of 4 quadrant slots, rotating so popups don't stack.
slot_idx=0
next_slot() {
    slot_idx=$(( (slot_idx + 1) % 4 ))
    echo $(( slot_idx + 1 ))
}

flash_skull() {
    [[ -z "$SKULL" ]] && return 0
    setsid -f mpv --no-config --really-quiet --no-audio \
        --no-osc --no-osd-bar --no-input-default-bindings \
        --no-border --keep-open=no --loop=no --length=1.4 \
        --wayland-app-id=bite-skull --x11-name=bite-skull --title=bite-skull \
        "$SKULL" >/dev/null 2>&1
    # Wait until it closes naturally (or we're disengaged)
    local waited=0
    while pgrep -fa "wayland-app-id=bite-skull" >/dev/null 2>&1; do
        sleep 0.4
        waited=$((waited + 1))
        [[ $waited -gt 12 ]] && break
        [[ -f "$STATE" ]] || break
    done
}

pop_terminal() {
    local slot
    slot="$(next_slot)"
    local cmd
    cmd="$(pick_hack_cmd)"
    setsid -f kitty \
        --class "bite-hack-$slot" --title "bite-hack-$slot" \
        -o background_opacity=0.85 \
        -o background=#000000 \
        -o foreground=#39ff7a \
        -o cursor_shape=block -o cursor_blink_interval=0 \
        -o font_size=9 -o window_padding_width=6 \
        -o confirm_os_window_close=0 \
        -o "map escape close_window" \
        -o "map ctrl+q close_window" \
        -o "map ctrl+w close_window" \
        sh -c "$cmd" >/dev/null 2>&1 &
    disown

    # Hold this terminal up for a random 4-8s, then close it ourselves
    # unless the user already closed it.
    local hold=$(( RANDOM % 5 + 4 ))
    local elapsed=0
    while pgrep -f "kitty --class bite-hack-$slot" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        [[ $elapsed -ge $hold ]] && {
            pkill -f "kitty --class bite-hack-$slot" 2>/dev/null
            break
        }
        [[ -f "$STATE" ]] || { pkill -f "kitty --class bite-hack-$slot" 2>/dev/null; break; }
    done
}

# Initial breather
sleep 6

while [[ -f "$STATE" && "$(cat "$STATE" 2>/dev/null)" == "on" ]]; do
    # Weighted random: 35% skull flash, 65% terminal
    if (( RANDOM % 100 < 35 )); then
        flash_skull
    else
        pop_terminal
    fi
    # Random gap 10-20s before the next popup
    sleep $(( RANDOM % 11 + 10 ))
done
