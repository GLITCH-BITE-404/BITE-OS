#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ─────────────────────────────────────────────────────────────────────────────
#  GLITCH-FETCH  ::  Pure-Bash Gacha Engine for GLITCH-BITE-404
#  Target : BITE-OS / Arch  ::  Fastfetch >= 2.10
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ---- Paths ------------------------------------------------------------------
readonly GLITCH_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/glitch"
readonly ICON_DIR="$GLITCH_ROOT/icons"
readonly TEMPLATE_DIR="$GLITCH_ROOT/templates"
readonly STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
# Per-parent-shell cache so concurrent fish sessions don't clobber each
# other's pick. PPID is the shell that invoked us (fish), so every redraw
# inside the same session reads back the same file.
readonly STATE_FILE="$STATE_DIR/glitch-fetch-${PPID}.icon"

# ---- Aspect classification (by filename prefix) -----------------------------
classify_icon() {
    local base; base="${1##*/}"
    case "$base" in
        sq_*) printf 'centered'     ;;
        wd_*) printf 'side-by-side' ;;
        tl_*) printf 'vertical'     ;;
        *)    printf 'centered'     ;;  
    esac
}

# ---- Pick a random icon (pure bash) ---------------------------------------
# Globs every common image extension. Prefixed files (sq_/wd_/tl_) get the
# matched layout; un-prefixed files fall back to 'centered' via classify_icon.
pick_icon() {
    local -a pool=()
    shopt -s nullglob nocaseglob
    pool=( "$ICON_DIR"/*.png  "$ICON_DIR"/*.jpg  "$ICON_DIR"/*.jpeg \
           "$ICON_DIR"/*.gif  "$ICON_DIR"/*.webp "$ICON_DIR"/*.bmp )
    shopt -u nullglob nocaseglob
    (( ${#pool[@]} == 0 )) && { printf ''; return; }
    printf '%s' "${pool[RANDOM % ${#pool[@]}]}"
}

# ---- Hardware probes (direct /sys reads) -----------------------------------
cpu_temp_c() {
    local f t
    for f in /sys/class/hwmon/hwmon*/temp1_input; do
        [[ -r $f ]] || continue
        read -r t < "$f"
        printf '%d°C' $(( t / 1000 ))
        return
    done
    printf 'N/A'
}

gpu_usage() {
    local f
    # AMD check
    for f in /sys/class/drm/card*/device/gpu_busy_percent; do
        [[ -r $f ]] || continue
        local pct; read -r pct < "$f"
        printf '%d%%' "$pct"
        return 0
    done
    # NVIDIA check (for your RTX 4060). nvidia-smi prints its "couldn't
    # communicate with the NVIDIA driver" error to STDOUT (a VM has the tool
    # but no driver), so only trust the output if it's actually a number —
    # feeding the error text to printf %d errexits the whole fetch.
    if command -v nvidia-smi >/dev/null 2>&1; then
        local pct
        pct="$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -cd '0-9')" || pct=""
        if [[ -n $pct ]]; then
            printf '%d%%' "$pct"
            return 0
        fi
    fi
    printf 'N/A'
    return 0
}

# ---- Branding banner (printed BEFORE fastfetch, every launch) --------------
# Small "cursed character" GLITCH BYTE [ 404 ] — bold red, glitch-style
# block-element font. Same vibe as the original fish_greeting.
print_banner() {
    printf '\033[1;31m%s\033[0m\n' ' ▟▛▜▙ █    █ ▛▀▜ ▟▛▀ █  █    █▀▀▖ █ ▀▀█▀▀ █▀▀'
    printf '\033[1;31m%s\033[0m\n' ' █ ▄▄ █    █  █  █    █▀▀█    █▀▀▖ █   █   █▀▀'
    printf '\033[1;31m%s\033[0m\n' ' ▜▄▄▛ █▄▄▖ █  █  ▜▄▄ █  █    █▄▄▖ █   █   █▄▄'
    printf '\033[1;37m%s\033[0m\n' '             [ 404 ]'
}

# ---- Read /proc/cpuinfo and trim verbose vendor strings -------------------
cpu_name_short() {
    local name
    name=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)
    # Strip Intel/AMD marketing fluff: "13th Gen Intel(R) Core(TM) i5-1335U"
    # → "i5-1335U". Same idea for Ryzen names.
    name="${name//(R)/}"
    name="${name//(TM)/}"
    name="${name//Intel /}"
    name="${name//AMD /}"
    name="${name// CPU/}"
    name="${name// Processor/}"
    name="${name//Core /}"
    name="${name//Ryzen /R}"
    # Drop "13th Gen" and similar generation prefixes.
    name="${name#*Gen }"
    # Collapse repeated spaces and trim.
    name="$(echo "$name" | tr -s ' ' | sed 's/^ //;s/ $//')"
    printf '%s' "$name"
}

# ---- Strip distro suffix from kernel version ------------------------------
kernel_clean() {
    # Strip any "-cachyos" suffix from `uname -r` so the displayed kernel
    # version doesn't leak the upstream distro name. Pure cosmetic.
    local k; k=$(uname -r)
    printf '%s' "${k%-cachyos}"
}

# ---- Per-layout default (max) logo dimensions in fastfetch cells -----------
layout_dims() {
    case "$1" in
        side-by-side) printf '50 18' ;;
        vertical)     printf '25 26' ;;
        *)            printf '35 18' ;;  # centered + fallback
    esac
}

# ---- Compute resize-aware sizes from current terminal ---------------------
# Echoes: LOGO_W LOGO_H COL BAR_LEN
# The template's default dims encode the desired aspect ratio; we scale
# uniformly so the sixel image isn't squished on short / narrow terminals.
compute_sizes() {
    local def_w="$1" def_h="$2"
    local cols lines
    cols=$(tput cols 2>/dev/null || echo 80)
    lines=$(tput lines 2>/dev/null || echo 24)

    # Info box is a fixed 58-char block (2 corners + 56 dashes) plus 5 cells
    # of logo padding (left 2 + right 3). 58 was chosen so the full literal
    # icon-folder path ($HOME/.config/glitch/icons) fits inside the value
    # column without overflow.
    local pad=5 box=58
    local avail_w=$(( cols - pad - box ))
    local avail_h=$(( lines - 14 ))
    (( avail_w < 8 )) && avail_w=8
    (( avail_h < 4 )) && avail_h=4

    # Pick the tighter constraint and scale the *other* axis to match,
    # preserving def_w:def_h so the image keeps its aspect ratio.
    local lw lh
    if (( avail_w * def_h <= avail_h * def_w )); then
        lw=$avail_w
        lh=$(( avail_w * def_h / def_w ))
    else
        lh=$avail_h
        lw=$(( avail_h * def_w / def_h ))
    fi
    # Never scale past the template's intended max.
    if (( lw > def_w )); then
        lw=$def_w
        lh=$def_h
    fi
    (( lw < 8 )) && lw=8
    (( lh < 4 )) && lh=4

    # Right-border column follows the chosen logo width.
    local col=$(( lw + pad + box ))
    (( col >= cols )) && col=$(( cols - 1 ))
    (( col < 40 )) && col=40

    local bar=$(( col - lw - 7 ))
    (( bar < 10 )) && bar=10

    printf '%d %d %d %d' "$lw" "$lh" "$col" "$bar"
}

# ---- Build the Fastfetch config -------------------------------------------
build_config() {
    local icon="$1" template_name="$2"
    local template="$TEMPLATE_DIR/${template_name}.jsonc"
    [[ -r $template ]] || { echo "Missing template: $template" >&2; exit 1; }

    local temp gpu kernel cpu
    kernel="$(kernel_clean)"
    temp="$(cpu_temp_c)"
    gpu="$(gpu_usage)"
    cpu="$(cpu_name_short)"

    local def_w def_h logo_w logo_h col bar_len bar
    read -r def_w def_h <<<"$(layout_dims "$template_name")"
    read -r logo_w logo_h col bar_len <<<"$(compute_sizes "$def_w" "$def_h")"
    bar=$(printf '─%.0s' $(seq 1 "$bar_len"))

    # Full literal icon-folder path so the user can see exactly where to
    # drop new images.
    local icon_dir_disp="$ICON_DIR"

    sed \
        -e "s|@@ICON@@|${icon}|g" \
        -e "s|@@OS@@|BITE-OS|g" \
        -e "s|@@KERNEL@@|${kernel}|g" \
        -e "s|@@CPU_NAME@@|${cpu}|g" \
        -e "s|@@CPU_TEMP@@|${temp}|g" \
        -e "s|@@GPU_USAGE@@|${gpu}|g" \
        -e "s|@@LOGO_W@@|${logo_w}|g" \
        -e "s|@@LOGO_H@@|${logo_h}|g" \
        -e "s|@@COL@@|${col}|g" \
        -e "s|@@BAR@@|${bar}|g" \
        -e "s|@@ICON_DIR@@|${icon_dir_disp}|g" \
        "$template"
}

# ---- Main -------------------------------------------------------------------
main() {
    local icon template cfg
    print_banner

    # TTY (Linux console) can't render sixel/kitty images — fall back to the
    # custom BITE-OS ASCII logo with the default fastfetch config.
    if [[ ${TERM:-} == linux ]]; then
        local ascii="$HOME/.config/fastfetch/bite-os.txt"
        if [[ -r $ascii ]]; then
            exec fastfetch --logo-type file --logo "$ascii"
        fi
        exec fastfetch --logo-type builtin --logo arch
    fi

    # Default: reuse the cached icon so terminal resizes don't reroll the gacha.
    # The fish greeter sets GLITCH_FRESH_ROLL=1 once per session to force a new
    # pick; everything else (resize redraws) falls through to the cache.
    icon=""
    if [[ ${GLITCH_FRESH_ROLL:-0} != 1 && -r $STATE_FILE ]]; then
        local cached
        cached="$(<"$STATE_FILE")"
        [[ -n $cached && -r $cached ]] && icon="$cached"
    fi
    if [[ -z $icon ]]; then
        icon="$(pick_icon)"
        [[ -n $icon ]] && printf '%s' "$icon" > "$STATE_FILE" 2>/dev/null || true
    fi
    if [[ -z $icon ]]; then
        exec fastfetch --logo-type builtin --logo arch
    fi

    template="$(classify_icon "$icon")"
    cfg="$(mktemp --tmpdir glitch-fetch.XXXX.jsonc)"
    trap 'rm -f "$cfg"' EXIT

    build_config "$icon" "$template" > "$cfg"
    exec fastfetch --config "$cfg"
}

main "$@"
