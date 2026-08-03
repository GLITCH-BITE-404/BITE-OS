#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# blend-toggle — enable/disable individual ilyamiro "options" on top of caelestia.
#
# Each component is independent. Toggling one never touches the others.
# All disk swaps autobackup first (move, not delete) so nothing is destroyed.
#
# Usage:
#   blend-toggle.sh status <component>
#   blend-toggle.sh on     <component>
#   blend-toggle.sh off    <component>
#   blend-toggle.sh toggle <component>
#   blend-toggle.sh restore                   # login hook
#
# Components:
#   animations   ilyamiro's bezier + popin window animations (hyprctl, no disk)
#   rofi         his rofi theme (file swap, ~/.config/rofi)
#   cava         his cava config  (file swap, ~/.config/cava)
#
# State:
#   ~/.local/state/bite-os/blend-<component> = on|off
# Vault (read-only source):
#   ~/.local/share/bite-os/rices/ilyamiro/.config/<component>
# Backups (per-toggle, never deleted):
#   ~/.local/share/bite-os/rices/_autobackup/<ts>-blend-<component>/

set -euo pipefail
APP="BITE-OS"
STATE_DIR="${HOME}/.local/state/bite-os"
VAULT="${HOME}/.local/share/bite-os/rices/ilyamiro/.config"
BACKUP_ROOT="${HOME}/.local/share/bite-os/rices/_autobackup"
mkdir -p "$STATE_DIR" "$BACKUP_ROOT"

state_file() { echo "${STATE_DIR}/blend-$1"; }
read_state() { local f; f="$(state_file "$1")"; [[ -f "$f" ]] && cat "$f" || echo off; }
write_state() { echo "$2" > "$(state_file "$1")"; }

ts() { date +%Y%m%d-%H%M%S; }

backup_dir() {
    local comp="$1" rel="$2"
    local dir="${BACKUP_ROOT}/$(ts)-blend-${comp}"
    mkdir -p "$dir"
    if [[ -e "${HOME}/${rel}" ]]; then
        mkdir -p "$(dirname "${dir}/${rel}")"
        mv "${HOME}/${rel}" "${dir}/${rel}"
    fi
    printf '%s' "$dir"
}

notify() {
    [[ "${BLEND_QUIET:-0}" == "1" ]] && return 0
    notify-send -a "$APP" -i "applications-graphics" "$1" "$2" 2>/dev/null || true
}

# ─── animations ────────────────────────────────────────────────────────────
ani_on() {
    local hk='hyprctl keyword'
    $hk bezier    'blendBezier, 0.05, 0.9, 0.1, 1.05'             >/dev/null
    $hk animation 'windows,             1, 5, blendBezier, popin 80%' >/dev/null
    $hk animation 'windowsOut,          1, 5, blendBezier, popin 80%' >/dev/null
    $hk animation 'layers,              1, 5, blendBezier, fade'  >/dev/null
    $hk animation 'fade,                1, 5, blendBezier'        >/dev/null
    $hk animation 'workspaces,          1, 5, blendBezier, slide' >/dev/null
}
ani_off() { hyprctl reload >/dev/null; }

# ─── rofi ──────────────────────────────────────────────────────────────────
rofi_on() {
    local src="${VAULT}/rofi"
    [[ -d "$src" ]] || { echo "vault missing rofi"; return 1; }
    local bk; bk="$(backup_dir rofi .config/rofi)"
    cp -a "$src" "${HOME}/.config/rofi"
    echo "$bk" > "$(state_file rofi).backup"
}
rofi_off() {
    local bkfile; bkfile="$(state_file rofi).backup"
    [[ -e "${HOME}/.config/rofi" ]] && {
        local dir="${BACKUP_ROOT}/$(ts)-blend-rofi-installed"
        mkdir -p "$dir/.config"
        mv "${HOME}/.config/rofi" "$dir/.config/rofi"
    }
    if [[ -f "$bkfile" ]]; then
        local bk; bk="$(cat "$bkfile")"
        [[ -e "${bk}/.config/rofi" ]] && cp -a "${bk}/.config/rofi" "${HOME}/.config/rofi"
        rm -f "$bkfile"
    fi
}

# ─── cava ──────────────────────────────────────────────────────────────────
cava_on() {
    local src="${VAULT}/cava"
    [[ -d "$src" ]] || { echo "vault missing cava"; return 1; }
    local bk; bk="$(backup_dir cava .config/cava)"
    cp -a "$src" "${HOME}/.config/cava"
    echo "$bk" > "$(state_file cava).backup"
}
cava_off() {
    local bkfile; bkfile="$(state_file cava).backup"
    [[ -e "${HOME}/.config/cava" ]] && {
        local dir="${BACKUP_ROOT}/$(ts)-blend-cava-installed"
        mkdir -p "$dir/.config"
        mv "${HOME}/.config/cava" "$dir/.config/cava"
    }
    if [[ -f "$bkfile" ]]; then
        local bk; bk="$(cat "$bkfile")"
        [[ -e "${bk}/.config/cava" ]] && cp -a "${bk}/.config/cava" "${HOME}/.config/cava"
        rm -f "$bkfile"
    fi
}

# ─── dispatcher ────────────────────────────────────────────────────────────
do_action() {
    local action="$1" comp="$2"
    case "$comp:$action" in
        animations:on)  ani_on  ;;
        animations:off) ani_off ;;
        rofi:on)        rofi_on ;;
        rofi:off)       rofi_off ;;
        cava:on)        cava_on ;;
        cava:off)       cava_off ;;
        *) echo "unknown: $comp $action" >&2; return 2 ;;
    esac
}

cmd="${1:-}"
comp="${2:-}"

case "$cmd" in
    status)
        [[ -z "$comp" ]] && {
            for c in animations rofi cava; do printf '%-12s %s\n' "$c" "$(read_state "$c")"; done
            exit 0
        }
        read_state "$comp"
        ;;
    on)
        [[ -z "$comp" ]] && { echo "need component"; exit 2; }
        do_action on "$comp" && write_state "$comp" on
        notify "Blend: $comp" "Enabled"
        ;;
    off)
        [[ -z "$comp" ]] && { echo "need component"; exit 2; }
        do_action off "$comp" && write_state "$comp" off
        notify "Blend: $comp" "Disabled (previous config restored)"
        ;;
    toggle)
        [[ -z "$comp" ]] && { echo "need component"; exit 2; }
        if [[ "$(read_state "$comp")" == "on" ]]; then "$0" off "$comp"
        else "$0" on "$comp"; fi
        ;;
    restore)
        # Login hook: re-apply whatever was last enabled. Components that
        # touch disk are already on disk — only animations needs replaying.
        BLEND_QUIET=1
        [[ "$(read_state animations)" == "on" ]] && ani_on
        ;;
    ""|help|--help|-h)
        sed -n '2,28p' "$0" | sed 's/^# \?//'
        ;;
    *)
        echo "unknown command: $cmd" >&2; exit 2 ;;
esac
