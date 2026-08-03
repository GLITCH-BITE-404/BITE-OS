#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GLITCH BITE power-profile switcher.
# Usage: glitch-power.sh saver|balanced|perf
set -u

mode="${1:-balanced}"
APP="GLITCH BITE"

hypr() { command -v hyprctl >/dev/null && hyprctl --batch "$*" >/dev/null 2>&1 || true; }
ppd()  { command -v powerprofilesctl >/dev/null && powerprofilesctl set "$1" >/dev/null 2>&1 || true; }

# Patch Caelestia's shell.json so the bar/drawer's own animations & transparency
# react too — Hyprland-side toggles don't touch Quickshell-rendered effects.
shell_json="$HOME/.config/caelestia/shell.json"
caelestia() {
    local anim="$1" transp="$2"   # anim: 0 or 1 ; transp: true or false
    [ -f "$shell_json" ] || return 0
    # tmp MUST live on the same filesystem as shell_json so `mv` is a real
    # atomic rename — otherwise it degrades to copy+unlink and Quickshell's
    # file watcher can fire mid-write, reading half a JSON doc and glitching
    # the bar/drawer until the next mode switch.
    local dir; dir="$(dirname "$shell_json")"
    local tmp; tmp="$(mktemp -p "$dir" .shell.json.XXXXXX)" || return 0
    if jq --argjson s "$anim" --argjson t "$transp" '
        .appearance = (.appearance // {}) |
        .appearance.anim = (.appearance.anim // {}) |
        .appearance.anim.durations = (.appearance.anim.durations // {}) |
        .appearance.anim.durations.scale = $s |
        .appearance.transparency = (.appearance.transparency // {}) |
        .appearance.transparency.enabled = $t
    ' "$shell_json" > "$tmp"; then
        mv -f "$tmp" "$shell_json"
    else
        rm -f "$tmp"
    fi
}

# Root-tunable knobs. All wrapped in `sudo -n` so a missing sudoers rule just
# silently no-ops instead of prompting or breaking.
turbo() {  # 0 = enable boost, 1 = disable boost
    local want="$1" path=/sys/devices/system/cpu/intel_pstate/no_turbo
    [ -w "$path" ] && { echo "$want" > "$path"; return; }
    sudo -n /usr/bin/tee "$path" >/dev/null 2>&1 <<<"$want" || true
}
freq_cap() {  # MHz upper bound, or "unlimited"
    local mhz="$1"
    if [ "$mhz" = "unlimited" ]; then
        sudo -n /usr/bin/cpupower frequency-set -u 5000MHz >/dev/null 2>&1 || true
    else
        sudo -n /usr/bin/cpupower frequency-set -u "${mhz}MHz" >/dev/null 2>&1 || true
    fi
}
governor() {  # powersave | performance | schedutil
    sudo -n /usr/bin/cpupower frequency-set -g "$1" >/dev/null 2>&1 || true
}

case "$mode" in
    saver)
        ppd power-saver
        hypr "keyword animations:enabled 0 ; keyword decoration:blur:enabled false ; keyword decoration:shadow:enabled false ; keyword misc:vfr true"
        caelestia 0 false
        turbo 1
        governor powersave
        freq_cap 1800
        notify-send -a "$APP" -i "battery-low-symbolic" "Power: Saver" \
            "CPU capped 1.8GHz, turbo off, eye-candy off."
        ;;
    balanced|balance)
        ppd balanced
        # Explicit keyword resets instead of `hyprctl reload`. A full reload
        # re-parses hyprland.conf and repaints every surface — that's what
        # was flashing the UI on every switch into balanced. Mirror perf's
        # incremental keyword set (vfr left on for power).
        hypr "keyword animations:enabled 1 ; keyword decoration:blur:enabled true ; keyword decoration:shadow:enabled true ; keyword misc:vfr true"
        caelestia 1 true
        turbo 0
        governor powersave
        freq_cap unlimited
        notify-send -a "$APP" -i "battery-good-symbolic" "Power: Balanced" \
            "Full clocks, turbo on, normal rice."
        ;;
    perf|performance)
        ppd performance
        hypr "keyword animations:enabled 1 ; keyword decoration:blur:enabled true ; keyword decoration:shadow:enabled true ; keyword misc:vfr false"
        caelestia 1 true
        turbo 0
        governor performance
        freq_cap unlimited
        notify-send -a "$APP" -i "battery-full-charging-symbolic" "Power: Performance" \
            "Performance governor, full boost, going hard."
        ;;
    *)
        notify-send -a "$APP" "Unknown power mode" "$mode"
        exit 1
        ;;
esac
