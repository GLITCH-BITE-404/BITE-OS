#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ─────────────────────────────────────────────────────────────────────────────
#  GLITCH-FETCH  ::  Pure-Bash Gacha Engine for GLITCH-BITE404
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
# The BITE-OS ASCII logo. Used as the ONLY fallback whenever the sixel/kitty
# image path is unavailable — we never want to leak the upstream distro art.
readonly ASCII_LOGO="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/bite-os.txt"

# ---- Does this terminal actually render images? ----------------------------
# Returns 0 if kitty-graphics or sixel is available. The Linux VT, dumb
# terminals, and piped output never qualify, so they get the ASCII logo.
images_supported() {
    [[ -t 1 ]] || return 1
    case "${TERM:-}" in
        linux|dumb|'') return 1 ;;
    esac
    # Terminals known to speak kitty-graphics or sixel (foot is the default).
    [[ -n ${KITTY_WINDOW_ID:-} || -n ${GHOSTTY_BIN_DIR:-} ]] && return 0
    case "${TERM:-}|${TERM_PROGRAM:-}" in
        *kitty*|*ghostty*|*wezterm*|*WezTerm*|*foot*|*konsole*|*iTerm*|*mlterm*)
            return 0 ;;
    esac
    # Unknown terminal: ask it via Primary Device Attributes and look for
    # sixel support (attribute "4"). Bails out fast if there's no reply.
    [[ -t 0 ]] || return 1
    local old resp=''
    old=$(stty -g 2>/dev/null) || return 1
    stty raw -echo min 0 time 3 2>/dev/null
    printf '\033[c' > /dev/tty 2>/dev/null
    IFS= read -r -t 1 -d c resp < /dev/tty 2>/dev/null || true
    stty "$old" 2>/dev/null
    [[ $resp =~ (^|[?\;])4([\;]|$) ]]
}

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
        return
    done
    # NVIDIA check (for your RTX 4060)
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits \
            2>/dev/null | { read -r pct; printf '%d%%' "${pct:-0}"; }
        return
    fi
    printf 'N/A'
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

# Is there room for a logo BESIDE the fixed-width info box?
logo_fits() {
    local cols; cols=$(tput cols 2>/dev/null || echo 80)
    (( cols - 5 - 58 >= 8 ))
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

    # The info box is a fixed 58 columns and cannot shrink — its widest value is
    # the literal icons path. Below roughly 71 columns there is no room for a
    # logo BESIDE it, and the old code clamped the logo to 8 anyway: the box
    # then ran past the terminal, wrapped, and the right border ended up on the
    # following line. A missing logo looks deliberate; a shredded box does not.
    if (( avail_w < 8 )); then
        local c=$(( cols - 1 ))
        (( c > box + 1 )) && c=$(( box + 1 ))
        (( c < 20 )) && c=20
        # 1, not 0: fastfetch refuses a zero logo width outright and prints
        # a JsonConfig error instead of rendering anything. The logo is removed
        # with --logo none on the command line, where it belongs.
        printf '1 1 %d %d' "$c" "$(( c - 2 ))"
        return
    fi

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

    # Anywhere images can't render (Linux VT, non-sixel terminals, piped
    # output) show the BITE-OS ASCII logo — never the upstream distro art.
    if ! images_supported; then
        if [[ -r $ASCII_LOGO ]]; then
            exec fastfetch --logo-type file --logo "$ASCII_LOGO"
        fi
        exec fastfetch --logo none
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
        if [[ -r $ASCII_LOGO ]]; then
            exec fastfetch --logo-type file --logo "$ASCII_LOGO"
        fi
        exec fastfetch --logo none
    fi

    template="$(classify_icon "$icon")"
    cfg="$(mktemp --tmpdir glitch-fetch.XXXX.jsonc)"
    trap 'rm -f "$cfg"' EXIT

    build_config "$icon" "$template" > "$cfg"

    # Too narrow to carry a logo next to the box? Keep the styling, drop the
    # image — a box that fits beats a picture that shreds it.
    if ! logo_fits; then
        exec fastfetch --config "$cfg" --logo none
    fi
    exec fastfetch --config "$cfg"
}

main "$@"
