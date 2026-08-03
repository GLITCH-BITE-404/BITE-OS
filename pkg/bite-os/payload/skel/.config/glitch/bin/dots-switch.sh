#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# dots-switch — swap between caelestia and ilyamiro rices end-to-end.
#
#   dots-switch.sh caelestia    swap to your personal rice
#   dots-switch.sh ilyamiro     swap to ilyamiro's rice (with watchdog)
#   dots-switch.sh toggle       flip to whichever isn't active
#   dots-switch.sh status       print current shell + rice
#
# Watchdog: when swapping AWAY from caelestia, a background watcher polls
# the target shell process. If it isn't alive after WATCHDOG_TIMEOUT seconds,
# the watcher auto-runs `dots-switch.sh caelestia` to rescue you from a
# black screen. The watcher exits cleanly once the shell is up.
#
# Emergency revert (also bound to Super+Ctrl+D in BOTH hyprland configs):
#   ~/.config/glitch/bin/dots-switch.sh caelestia

set -uo pipefail
APP="BITE-OS"
STATE_DIR="${HOME}/.local/state/bite-os"
mkdir -p "$STATE_DIR"
ACTIVE_SHELL_FILE="${STATE_DIR}/active-shell"     # caelestia | ilyamiro
WATCHDOG_PID_FILE="${STATE_DIR}/watchdog.pid"
WATCHDOG_TIMEOUT=30
LOG="/tmp/dots-switch.log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }

notify() {
    notify-send -a "$APP" -i "applications-graphics" "$1" "$2" 2>/dev/null || true
}

# ─── shell-specific launchers ──────────────────────────────────────────────
launch_caelestia_shell() {
    # launch_qs.sh is the single source of truth when present — it tears down
    # stray instances before starting exactly one.
    if [[ -x "$HOME/.config/hypr/scripts/launch_qs.sh" ]]; then
        "$HOME/.config/hypr/scripts/launch_qs.sh"
    else
        nohup caelestia shell -d >/tmp/caelestia.log 2>&1 &
        disown
    fi
    # kill_any_shell tears down the cliphist watchers + hypridle, and exec-once
    # won't re-run them until next login — bring them back for this rice too.
    if command -v wl-paste >/dev/null && command -v cliphist >/dev/null; then
        setsid -f bash -c 'wl-paste --type text  --watch cliphist store' </dev/null >/dev/null 2>&1
        setsid -f bash -c 'wl-paste --type image --watch cliphist store' </dev/null >/dev/null 2>&1
    fi
    [[ -f "$HOME/.config/hypr/hypridle.conf" ]] && command -v hypridle >/dev/null && \
        setsid -f hypridle </dev/null >/dev/null 2>&1
}
launch_ilyamiro_shell() {
    # His autostart runs his shell too, but exec-once doesn't re-run on hyprctl
    # reload. Launch it + the autostart helpers explicitly so the swap takes
    # effect immediately and the bar/binds behave like a fresh login.
    # The 2026-06-14 upstream update renamed the entrypoint Shell.qml -> Main.qml
    # and it runs under the `quickshell` binary name (not `qs`) — launch
    # whichever entry the rice actually ships.
    local qml="$HOME/.config/hypr/scripts/quickshell/Main.qml"
    [[ -f "$qml" ]] || qml="$HOME/.config/hypr/scripts/quickshell/Shell.qml"
    nohup quickshell -p "$qml" >/tmp/ilyamiro-qs.log 2>&1 &
    disown
    # Helpers from his hypr autostart.conf — fire-and-forget, fail silent if missing.
    [[ -f "$HOME/.config/hypr/hypridle.conf" ]] && command -v hypridle >/dev/null && \
        setsid -f hypridle </dev/null >/dev/null 2>&1
    command -v playerctld  >/dev/null && { setsid -f playerctld </dev/null >/dev/null 2>&1; }
    command -v awww-daemon >/dev/null && { setsid -f awww-daemon </dev/null >/dev/null 2>&1; }
    if command -v wl-paste >/dev/null && command -v cliphist >/dev/null; then
        setsid -f bash -c 'wl-paste --type text  --watch cliphist store' </dev/null >/dev/null 2>&1
        setsid -f bash -c 'wl-paste --type image --watch cliphist store' </dev/null >/dev/null 2>&1
    fi
    [[ -x "$HOME/.config/hypr/scripts/settings_watcher.sh" ]] && \
        setsid -f "$HOME/.config/hypr/scripts/settings_watcher.sh" </dev/null >/dev/null 2>&1
    [[ -x "$HOME/.config/hypr/scripts/volume_listener.sh"  ]] && \
        setsid -f "$HOME/.config/hypr/scripts/volume_listener.sh"  </dev/null >/dev/null 2>&1
    [[ -x "$HOME/.config/hypr/scripts/update_notifier.sh"  ]] && \
        setsid -f "$HOME/.config/hypr/scripts/update_notifier.sh"  </dev/null >/dev/null 2>&1
    [[ -f "$HOME/.config/hypr/scripts/quickshell/focustime/focus_daemon.py" ]] && command -v python3 >/dev/null && \
        setsid -f python3 "$HOME/.config/hypr/scripts/quickshell/focustime/focus_daemon.py" </dev/null >/dev/null 2>&1
}

# ─── alive checks (proc name, not just any qs) ────────────────────────────
caelestia_alive() {
    pgrep -f "qs -c caelestia" >/dev/null
}
ilyamiro_alive() {
    # Matches both the current layout (quickshell -p .../Main.qml) and the
    # pre-update one (qs -p .../Shell.qml).
    pgrep -f "scripts/quickshell/(Main|Shell)\.qml" >/dev/null
}

# ─── kill the currently-running shell (whichever it is) ───────────────────
# Tear down BOTH rices' helper processes so the new rice starts clean. Without
# this, ilyamiro's focus_daemon/volume_listener/etc. linger when you swap to
# caelestia (and vice-versa), holding sockets and confusing the new bar.
kill_any_shell() {
    pkill -x qs 2>/dev/null
    # ilyamiro's shell runs under the binary name `quickshell` (NOT `qs`) since
    # the 2026-06-14 upstream update — missing it here meant his shell SURVIVED
    # every swap and kept owning org.freedesktop.Notifications, so popups
    # stayed ilyamiro-styled no matter which rice was active.
    pkill -x quickshell 2>/dev/null
    pkill -f "caelestia shell" 2>/dev/null
    # ilyamiro-specific helpers (current Main.qml layout + old Shell.qml one)
    pkill -f "scripts/quickshell/Shell.qml" 2>/dev/null
    pkill -f "scripts/quickshell/Main.qml" 2>/dev/null
    pkill -f "scripts/quickshell/focustime/focus_daemon.py" 2>/dev/null
    pkill -f "scripts/settings_watcher.sh" 2>/dev/null
    pkill -f "scripts/volume_listener.sh"  2>/dev/null
    pkill -f "scripts/update_notifier.sh"  2>/dev/null
    pkill -f "scripts/quickshell/watchers/" 2>/dev/null
    # Orphaned file-watchers the processes above leave behind
    pkill -f "inotifywait.*quickshell" 2>/dev/null
    pkill -x awww-daemon 2>/dev/null
    pkill -x hypridle    2>/dev/null
    pkill -x playerctld  2>/dev/null
    # Shared cliphist watchers (cheap to restart)
    pkill -f "wl-paste --type text --watch cliphist"  2>/dev/null
    pkill -f "wl-paste --type image --watch cliphist" 2>/dev/null
    sleep 0.5
}

restart_wallpaper() {
    # Both rices benefit from your existing wallpaper script (we patched
    # ilyamiro's autostart to call it). But hyprctl reload doesn't re-run
    # exec-once, so invoke it manually here every swap.
    if [[ -x "$HOME/.config/hypr/scripts/wallpaper.sh" ]]; then
        setsid -f "$HOME/.config/hypr/scripts/wallpaper.sh" restore </dev/null >/dev/null 2>&1
    fi
}

# ─── watchdog: poll, auto-revert if shell dies ────────────────────────────
spawn_watchdog() {
    local target="$1"
    # Kill any older watchdog
    if [[ -f "$WATCHDOG_PID_FILE" ]]; then
        kill "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null
        rm -f "$WATCHDOG_PID_FILE"
    fi
    (
        sleep 4    # give the shell a moment to actually start
        local check
        case "$target" in
            ilyamiro)  check=ilyamiro_alive ;;
            caelestia) check=caelestia_alive ;;
            *) exit 0 ;;
        esac
        local elapsed=4
        while (( elapsed < WATCHDOG_TIMEOUT )); do
            if $check; then
                log "watchdog: $target shell is alive after ${elapsed}s, exiting"
                rm -f "$WATCHDOG_PID_FILE"
                exit 0
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        log "watchdog: $target shell NOT alive after ${WATCHDOG_TIMEOUT}s, AUTO-REVERTING"
        notify "Dots swap failed" "$target shell did not start — reverting to caelestia"
        rm -f "$WATCHDOG_PID_FILE"
        # Recursive call: rescue. Important — bypass watchdog for the rescue.
        DOTS_RESCUE=1 "$0" caelestia
    ) &
    disown
    echo $! > "$WATCHDOG_PID_FILE"
    log "watchdog spawned with PID $! for target=$target"
}

# ─── the actual swap ──────────────────────────────────────────────────────
swap_to() {
    local target="$1"
    log "=== swap to $target (rescue=${DOTS_RESCUE:-0}) ==="

    log "step 1: rice load $target"
    if ! ~/.config/glitch/bin/rice load "$target" >>"$LOG" 2>&1; then
        log "FAIL: rice load $target failed"
        notify "Dots swap failed" "Could not load rice '$target'"
        return 1
    fi

    log "step 2: kill current shell + helpers"
    kill_any_shell

    log "step 3: hyprctl reload + submap reset (×2)"
    # Double-reload: first picks up the new config files, second clears any
    # stale state left over from the old rice's keybinds/rules. The submap
    # reset between is critical — ilyamiro's settings popup can leave hypr in
    # `passthru` submap if it was open at swap time, which makes every bind
    # look like it stopped responding.
    hyprctl reload >>"$LOG" 2>&1 || log "hyprctl reload #1 non-zero (continuing)"
    hyprctl dispatch submap reset >>"$LOG" 2>&1 || true
    sleep 0.3
    hyprctl reload >>"$LOG" 2>&1 || log "hyprctl reload #2 non-zero (continuing)"
    hyprctl dispatch submap reset >>"$LOG" 2>&1 || true
    sleep 0.3

    log "step 4: launch ${target} shell"
    case "$target" in
        caelestia) launch_caelestia_shell ;;
        ilyamiro)  launch_ilyamiro_shell  ;;
    esac

    log "step 5: settle + restart wallpaper"
    sleep 0.8
    restart_wallpaper

    echo "$target" > "$ACTIVE_SHELL_FILE"

    # If we're not the rescue, spawn watchdog. Rescue swaps don't watchdog
    # themselves (avoid loops).
    if [[ "${DOTS_RESCUE:-0}" != "1" ]]; then
        spawn_watchdog "$target"
    fi

    if [[ "$target" == "ilyamiro" ]]; then
        notify "Now in ilyamiro rice" "ESCAPE BACK: Super+Escape, Super+Ctrl+D, Super+Shift+C, or Super+Backspace. Or open his launcher and type 'caelestia'."
    else
        notify "Now in caelestia rice" "Your personal rice is restored. Super+Escape to swap again."
    fi
    log "swap_to $target complete"
}

cmd="${1:-status}"
case "$cmd" in
    caelestia|ilyamiro)
        swap_to "$cmd"
        ;;
    toggle)
        cur="$(cat "$ACTIVE_SHELL_FILE" 2>/dev/null || echo caelestia)"
        if [[ "$cur" == "ilyamiro" ]]; then "$0" caelestia
        else "$0" ilyamiro; fi
        ;;
    status)
        printf 'active-shell: %s\n' "$(cat "$ACTIVE_SHELL_FILE" 2>/dev/null || echo '(none)')"
        printf 'active-rice : %s\n' "$(~/.config/glitch/bin/rice current)"
        printf 'caelestia alive: %s\n' "$(caelestia_alive && echo yes || echo no)"
        printf 'ilyamiro  alive: %s\n' "$(ilyamiro_alive  && echo yes || echo no)"
        printf 'watchdog: %s\n' "$([[ -f "$WATCHDOG_PID_FILE" ]] && cat "$WATCHDOG_PID_FILE" || echo '(none)')"
        ;;
    help|--help|-h|"")
        sed -n '2,20p' "$0" | sed 's/^# \?//'
        ;;
    *)
        echo "unknown: $cmd" >&2; exit 2 ;;
esac
