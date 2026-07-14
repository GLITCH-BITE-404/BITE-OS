#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Unified wallpaper setter:
#   - images  -> hyprpaper, color scheme via `caelestia wallpaper -f`
#   - videos  -> mpvpaper underneath, first-frame fed to matugen for colors,
#                video path written to caelestia state for picker checkmark
# Usage:
#   wallpaper.sh <path>         set wallpaper (image or video)
#   wallpaper.sh restore        restore last wallpaper from state
#   wallpaper.sh <path> <mon>   optional monitor (default: first detected)

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE_FILE="$STATE_DIR/wallpaper"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia/wall-thumbs"
SHELL_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper"
SHELL_STATE_FILE="$SHELL_STATE_DIR/path.txt"
DEFAULT_WALL="$HOME/.config/hypr/wallpapers/default.png"
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/bite-wallpaper.lock"
mkdir -p "$STATE_DIR" "$SHELL_STATE_DIR" "$THUMB_DIR"

# --- Serialize invocations -------------------------------------------------
# The picker fires execDetached() on every click, so rapid dot-switching used
# to run several copies of this script at once. Each killed the same old
# mpvpaper, then spawned a new one -> a stack of up to 5 ghosts. A blocking
# flock makes invocations run one-at-a-time; the last click wins, none stack.
# fd 9 is closed (9>&-) on every daemon we spawn so the detached mpvpaper does
# NOT inherit and pin the lock for its entire lifetime.
exec 9>"$LOCKFILE"
flock 9

# Cleanly nuke every wallpaper daemon and CONFIRM it's gone before spawning.
# Order matters:
#   1. SIGCONT first — autopause may have SIGSTOP-frozen mpvpaper, and a frozen
#      process holds SIGTERM pending forever. Continue it so TERM can land.
#   2. SIGTERM for a clean exit, then poll up to ~1s.
#   3. SIGKILL any straggler — KILL can't be blocked or held by SIGSTOP.
kill_wallpaper_daemons() {
    pkill -CONT -x mpvpaper  2>/dev/null || true
    pkill -TERM -x mpvpaper  2>/dev/null || true
    pkill -TERM -x hyprpaper 2>/dev/null || true
    local i
    for i in $(seq 1 10); do
        pgrep -x mpvpaper >/dev/null 2>&1 || break
        sleep 0.1
    done
    pkill -KILL -x mpvpaper  2>/dev/null || true
    pkill -KILL -x hyprpaper 2>/dev/null || true
}

mode="${1:-restore}"
target=""

if [[ "$mode" == "restore" ]]; then
    if [[ -f "$STATE_FILE" ]] && [[ -s "$STATE_FILE" ]]; then
        target="$(cat "$STATE_FILE")"
    fi
    [[ -z "$target" || ! -f "$target" ]] && target="$DEFAULT_WALL"
else
    target="$mode"
fi

if [[ ! -f "$target" ]]; then
    echo "wallpaper: file not found: $target" >&2
    exit 1
fi

monitor="${2:-}"
if [[ -z "$monitor" ]]; then
    monitor="$(hyprctl -j monitors 2>/dev/null | grep -oP '"name":\s*"\K[^"]+' | head -n1)"
    [[ -z "$monitor" ]] && monitor="eDP-1"
fi

kill_wallpaper_daemons

ext="${target##*.}"
ext="${ext,,}"

is_video=0
case "$ext" in
    mp4|webm|mkv|mov|avi|gif) is_video=1 ;;
esac

if (( is_video )); then
    base="${target##*/}"
    base="${base%.*}"
    thumb="$THUMB_DIR/$base.png"
    if [[ ! -f "$thumb" ]] || [[ "$target" -nt "$thumb" ]]; then
        ffmpeg -y -loglevel error -ss 0 -i "$target" -frames:v 1 -vf "scale=640:-2" "$thumb" 2>/dev/null
    fi

    # Videos play via mpvpaper at the Background layer. The QML background
    # detects the video source and goes transparent so mpvpaper shows through.
    # dmabuf-wayland is zero-copy + uses VAAPI hw decode → near-zero CPU.
    setsid -f mpvpaper \
        -o "--hwdec=vaapi --vo=dmabuf-wayland --no-audio --loop --no-osc --no-osd-bar --no-input-default-bindings --no-input-cursor --profile=fast --vd-lavc-threads=1 --cache=no --demuxer-readahead-secs=2" \
        "$monitor" "$target" >/dev/null 2>&1 9>&- &
    disown

    # Update colour scheme from still frame + point state at the actual video
    if [[ -f "$thumb" ]] && command -v caelestia >/dev/null; then
        caelestia wallpaper -f "$thumb" -n -N >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$target" > "$SHELL_STATE_FILE"
else
    # Images: caelestia wallpaper -f updates state + colour scheme; QML displays.
    if command -v caelestia >/dev/null; then
        caelestia wallpaper -f "$target" -n >/dev/null 2>&1 || true
    fi
fi

if [[ "$mode" != "restore" ]]; then
    printf '%s\n' "$target" > "$STATE_FILE"
fi
