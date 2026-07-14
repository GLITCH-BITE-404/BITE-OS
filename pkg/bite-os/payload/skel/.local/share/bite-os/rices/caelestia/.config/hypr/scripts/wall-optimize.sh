#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# bite-wall-optimize — down-rate wallpaper videos for lower idle CPU.
#
# A live video wallpaper costs CPU/GPU proportional to its frame rate: every
# frame is decoded AND re-composited by mpvpaper. Most wallpapers are shipped
# at 30/60fps but look identical at 24 as a loop. This re-encodes them to a
# target fps with VAAPI-friendly H.264, cutting idle usage ~20-50%.
#
# Usage:
#   wall-optimize.sh <file>            optimize one video        (default 24fps)
#   wall-optimize.sh <dir>             optimize every video in a folder
#   wall-optimize.sh <file|dir> <fps>  pick the target fps (e.g. 20, 30)
#   wall-optimize.sh <...> --keep      write *-opt.mp4 instead of replacing
#
# Safety:
#   - Originals are moved to <dir>/.orig/ before replacing — never deleted.
#   - Files already at/below the target fps are skipped.
#   - Non-video files are skipped. Filenames with spaces are handled.

set -u

TARGET_FPS=24
KEEP=0
ARGS=()
for a in "$@"; do
    case "$a" in
        --keep) KEEP=1 ;;
        [0-9]*) TARGET_FPS="$a" ;;
        *)      ARGS+=("$a") ;;
    esac
done

[[ ${#ARGS[@]} -eq 0 ]] && { echo "usage: wall-optimize.sh <file|dir> [fps] [--keep]" >&2; exit 2; }
command -v ffmpeg  >/dev/null || { echo "ffmpeg not installed" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not installed" >&2; exit 1; }

VIDEO_EXT_RE='\.(mp4|mkv|mov|webm|avi)$'

# Current fps of a file as a plain integer (rounds 30000/1001 -> 30).
fps_of() {
    local fr; fr="$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)"
    [[ -z "$fr" || "$fr" == "0/0" ]] && { echo 0; return; }
    awk -F/ '{ printf "%d", ($2 ? $1/$2 : $1) + 0.5 }' <<<"$fr"
}

optimize_one() {
    local src="$1"
    [[ -f "$src" ]] || return 0
    if ! [[ "${src,,}" =~ $VIDEO_EXT_RE ]]; then
        return 0  # not a video, skip silently
    fi

    local cur; cur="$(fps_of "$src")"
    if (( cur == 0 )); then
        printf '  ?  %s  (no video stream, skipped)\n' "${src##*/}"; return 0
    fi
    if (( cur <= TARGET_FPS )); then
        printf '  ✓  %s  (already %dfps, skipped)\n' "${src##*/}" "$cur"; return 0
    fi

    local dir base tmp
    dir="$(dirname "$src")"; base="$(basename "$src")"
    tmp="$(mktemp "${dir}/.${base}.optXXXX.mp4")"

    printf '  →  %s  (%dfps → %dfps) … ' "$base" "$cur" "$TARGET_FPS"
    if ! ffmpeg -y -loglevel error -i "$src" \
            -r "$TARGET_FPS" -c:v libx264 -crf 20 -preset medium \
            -pix_fmt yuv420p -movflags +faststart -an "$tmp" 2>/dev/null; then
        rm -f "$tmp"; printf 'FAILED (left original untouched)\n'; return 1
    fi

    local osz nsz; osz=$(stat -c%s "$src"); nsz=$(stat -c%s "$tmp")
    if (( KEEP )); then
        local out="${dir}/${base%.*}-opt.mp4"
        mv -f "$tmp" "$out"
        printf 'done → %s  (%s → %s)\n' "${out##*/}" "$(numfmt --to=iec $osz)" "$(numfmt --to=iec $nsz)"
    else
        mkdir -p "${dir}/.orig"
        mv -n "$src" "${dir}/.orig/${base}"      # back up original (no clobber)
        mv -f "$tmp" "$src"                        # replace in place, same name/path
        printf 'done  (%s → %s, original in .orig/)\n' "$(numfmt --to=iec $osz)" "$(numfmt --to=iec $nsz)"
    fi
}

echo "bite-wall-optimize  →  target ${TARGET_FPS}fps$([[ $KEEP -eq 1 ]] && echo '  (keep originals alongside)')"
for path in "${ARGS[@]}"; do
    if [[ -d "$path" ]]; then
        echo "Folder: $path"
        shopt -s nullglob nocaseglob
        for f in "$path"/*.{mp4,mkv,mov,webm,avi}; do
            optimize_one "$f"
        done
        shopt -u nullglob nocaseglob
    elif [[ -f "$path" ]]; then
        optimize_one "$path"
    else
        echo "  !  not found: $path" >&2
    fi
done
echo "Done."
