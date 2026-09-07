#!/usr/bin/env bash
# ━━━ BITE-OS — wallpaper restore ━━━
# hypr autostart launches `awww-daemon`, but a bare daemon paints nothing —
# the screen stays black until something runs `awww img`. This re-applies the
# last wallpaper you picked, or the shipped BITE-OS default on a fresh user
# (the live ISO, or a freshly installed system on its first login).
#
# Videos: the picker caches a still THUMBNAIL as current_wallpaper.png, so
# restoring that alone gave you a frozen frame of your video wallpaper that
# only came alive when you re-picked it. current_source holds the REAL path,
# so a video is restored as a video via mpvpaper.
set -uo pipefail

CACHE_DIR="$HOME/.cache/quickshell/wallpaper_picker"
CACHE="$CACHE_DIR/current_wallpaper.png"
SOURCE="$CACHE_DIR/current_source"
DEFAULT="$HOME/.config/glitch/wallpapers/bite-os-default.png"
MPV_OPTS='loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample'

# Wait for the wallpaper daemon to accept connections (~6s max).
for _ in $(seq 1 30); do
    awww query >/dev/null 2>&1 && break
    sleep 0.2
done

# Prefer the recorded source (knows video vs image); fall back to the cached
# still, then to the shipped default.
WALL=""
[[ -s "$SOURCE" ]] && WALL="$(< "$SOURCE")"
[[ -n "$WALL" && -f "$WALL" ]] || WALL=""
if [[ -z "$WALL" ]]; then
    [[ -f "$CACHE" ]] && WALL="$CACHE" || WALL="$DEFAULT"
fi
[[ -f "$WALL" ]] || exit 0

# Never leave a second video wallpaper behind. CONT first — a SIGSTOPped
# mpvpaper (fullscreen autopause) holds SIGTERM pending forever.
kill_mpvpaper() {
    pkill -CONT -x mpvpaper 2>/dev/null || true
    pkill -TERM -x mpvpaper 2>/dev/null || true
    for _ in $(seq 1 10); do pgrep -x mpvpaper >/dev/null 2>&1 || break; sleep 0.1; done
    pkill -KILL -x mpvpaper 2>/dev/null || true
}

ext="${WALL##*.}"; ext="${ext,,}"
case "$ext" in
    mp4|webm|mkv|mov|avi)
        kill_mpvpaper
        # 8>&- : don't hand our caller's lock fd to a daemon that outlives us.
        setsid -f mpvpaper -o "$MPV_OPTS" '*' "$WALL" >/dev/null 2>&1 8>&- </dev/null
        # Still frame underneath, so nothing flashes black before mpvpaper paints.
        [[ -f "$CACHE" ]] && awww img "$CACHE" --transition-type none >/dev/null 2>&1 || true
        ;;
    *)
        kill_mpvpaper
        awww img "$WALL" \
            --transition-type fade --transition-fps 144 --transition-duration 1 \
            >/dev/null 2>&1 || true
        ;;
esac
exit 0
