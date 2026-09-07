#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# dots-switch — swap between caelestia and serpantinum rices end-to-end.
#
#   dots-switch.sh caelestia    swap to your personal rice
#   dots-switch.sh serpantinum  swap to the serpantinum rice (with watchdog)
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
ACTIVE_SHELL_FILE="${STATE_DIR}/active-shell"     # caelestia | serpantinum
WATCHDOG_PID_FILE="${STATE_DIR}/watchdog.pid"
WATCHDOG_TIMEOUT=30
LOG="/tmp/dots-switch.log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }

# ─── single-instance guard ────────────────────────────────────────────────
# Super+Ctrl+D is the panic bind, so it WILL get spammed. Without a lock each
# press ran a full concurrent swap: N x (rice load + kill_any_shell + launch),
# all interleaving. The kills raced the launches, so shells spawned faster than
# they were reaped -> a stack of bars, two rices alive at once, and windows
# sized against whichever shell won. Non-blocking: a swap already in flight
# means extra presses are dropped, not queued (queueing would just replay the
# same stampede a second later).
# NOT flock: this script spawns 17 detached daemons, and every one of them
# would inherit the lock fd and pin it for the whole session (the same trap
# wallpaper.sh works around with `9>&-`). A pidfile written with noclobber
# uses O_EXCL, so it's just as atomic and there is no fd to leak.
notify() {
    notify-send -a "$APP" -i "applications-graphics" "$1" "$2" 2>/dev/null || true
}

SWAP_LOCK="${STATE_DIR}/dots-switch.lock"
take_lock() { ( set -o noclobber; echo $$ > "$SWAP_LOCK" ) 2>/dev/null; }
# A re-exec of this script from inside an already-locked run (the watchdog
# rescue) carries the owner's pid so it doesn't block on the lock it is under.
if [[ -n "${DOTS_LOCK_OWNER:-}" ]] && [[ "${DOTS_LOCK_OWNER}" == "$(cat "$SWAP_LOCK" 2>/dev/null)" ]]; then
    log "re-entering under lock owned by $DOTS_LOCK_OWNER"
elif ! take_lock; then
    holder="$(cat "$SWAP_LOCK" 2>/dev/null)"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
        log "swap already in progress (pid $holder) — press ignored"
        notify "Swap in progress" "Hold up — already switching rices."
        exit 0
    fi
    # Holder is dead: a previous swap crashed mid-flight. Reclaim it.
    log "stale swap lock from dead pid ${holder:-?} — reclaiming"
    rm -f "$SWAP_LOCK"
    take_lock || exit 0
fi
trap 'rm -f "$SWAP_LOCK"' EXIT


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
    # kill_any_shell now reaps these too, and they're exec-once in execs.conf,
    # which hyprctl reload does NOT re-run — so bring them back on every swap.
    # (Both are single-instance internally, so a double-start is harmless.)
    for _h in mpvpaper-autopause.sh wallpaper-guard.sh; do
        [[ -x "$HOME/.config/hypr/scripts/$_h" ]] && \
            setsid -f "$HOME/.config/hypr/scripts/$_h" </dev/null >/dev/null 2>&1
    done
}
launch_serpantinum_shell() {
    # serpantinum ships its own daemon (serpantinumd) which owns the quickshell
    # process; it lives in the rice-managed tree, so call it by absolute path
    # rather than relying on ~/.local/bin being on PATH at swap time.
    local sbin="$HOME/.local/share/serpantinum/bin/serpantinumd"
    if [[ -x "$sbin" ]]; then
        nohup "$sbin" start >/tmp/serpantinum.log 2>&1 &
        disown
    fi
    # Shared helpers from autostart. NOTE: no volume_listener and no focustime
    # daemon here — serpantinum draws its own OSD and has no focustime widget,
    # so both were dropped from this rice's settings.json startup list.
    [[ -f "$HOME/.config/hypr/hypridle.conf" ]] && command -v hypridle >/dev/null && \
        setsid -f hypridle </dev/null >/dev/null 2>&1
    command -v playerctld  >/dev/null && { setsid -f playerctld </dev/null >/dev/null 2>&1; }
    # NO awww-daemon here: serpantinum draws its own wallpaper layer
    # (wallpaper-bg) and handles video natively via MediaPlayer/VideoOutput.
    # Running awww + mpvpaper underneath it meant decoding a video that
    # serpantinum's layer completely covered -- pure wasted CPU.
    if command -v wl-paste >/dev/null && command -v cliphist >/dev/null; then
        setsid -f bash -c 'wl-paste --type text  --watch cliphist store' </dev/null >/dev/null 2>&1
        setsid -f bash -c 'wl-paste --type image --watch cliphist store' </dev/null >/dev/null 2>&1
    fi
    [[ -x "$HOME/.config/hypr/scripts/settings_watcher.sh" ]] && \
        setsid -f "$HOME/.config/hypr/scripts/settings_watcher.sh" </dev/null >/dev/null 2>&1
    [[ -x "$HOME/.config/hypr/scripts/update_notifier.sh"  ]] && \
        setsid -f "$HOME/.config/hypr/scripts/update_notifier.sh"  </dev/null >/dev/null 2>&1
    [[ -x "$HOME/.config/hypr/scripts/serp-settings-sync.sh" ]] && \
        setsid -f "$HOME/.config/hypr/scripts/serp-settings-sync.sh" </dev/null >/dev/null 2>&1
}

# ─── alive checks (proc name, not just any qs) ────────────────────────────
caelestia_alive() {
    pgrep -f "qs -c caelestia" >/dev/null
}
serpantinum_alive() {
    # Its quickshell runs out of the rice-managed share tree, which is a
    # different path from ilyamiro's scripts/quickshell -- so these two alive
    # checks can never match each other's process.
    pgrep -f "share/serpantinum/src/quickshell" >/dev/null || pgrep -f "serpantinumd" >/dev/null
}

# ─── readiness: has the shell actually PAINTED? ───────────────────────────
# `nohup quickshell &` returns a live pid immediately, so an *_alive check
# passes long before the bar exists. Spamming the swap bind then chained swap
# after swap onto half-initialised shells — the session goes blurry and stops
# taking input because an overlay layer is mapped but its shell isn't up yet.
# A mapped layer surface is the real "it's on screen" signal.
# hyprctl prints "namespace: <name>, pid: <n>" — anchor on the comma so
# "quickshell" can't also match "quickshell-something".
caelestia_ready() { hyprctl layers 2>/dev/null | grep -q "namespace: caelestia-"; }
serpantinum_ready() { hyprctl layers 2>/dev/null | grep -q "namespace: quickshell,"; }
shell_ready() {
    case "$1" in
        caelestia) caelestia_ready ;;
        serpantinum) serpantinum_ready ;;
        *) return 0 ;;
    esac
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
    # serpantinum: ask its own CLI to stop first (it reaps its focus daemon and
    # pidfile cleanly), then belt-and-braces on the daemon + its quickshell.
    [[ -x "$HOME/.local/share/serpantinum/bin/serpantinum" ]] && \
        "$HOME/.local/share/serpantinum/bin/serpantinum" kill >/dev/null 2>&1
    pkill -f "serpantinumd" 2>/dev/null
    pkill -f "share/serpantinum/src/quickshell" 2>/dev/null
    # Every helper serpantinum spawns out of its script dir (focus_daemon.py,
    # current_focus.sh, brightness.sh watch, the watchers/*.sh). Matching the
    # directory catches them all, including ones added by future versions.
    pkill -f "share/serpantinum/src/scripts/" 2>/dev/null
    pkill -f "share/serpantinum/src/quickshell/watchers/" 2>/dev/null
    # serpantinum leaks watcher children that outlive the daemon: one
    # inotifywait on .../serpantinum/brightness per `serpantinum reload`, plus
    # ones on .cache/serpantinum/recording. Upstream 2.1.1 claims to have fixed
    # orphaned inotifywaits; it did not. Reap them by their watch paths.
    pkill -f "inotifywait.*serpantinum" 2>/dev/null
    pkill -f "run/user/.*/serpantinum" 2>/dev/null
    # BITE-OS settings mirror -- rice-specific, must not outlive the swap.
    pkill -f "serp-settings-sync.sh" 2>/dev/null
    # A pending "update available" notify-send blocks waiting for a click and
    # would survive into another rice.
    pkill -f "notify-send.*[Uu]pdate available" 2>/dev/null
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
    # Wallpaper daemons + their helpers. Missing these meant caelestia's
    # wallpaper-guard/mpvpaper-autopause SURVIVED every swap into ilyamiro:
    # autopause would SIGSTOP mpvpaper on fullscreen, and a STOPped process
    # holds SIGTERM pending forever, so ilyamiro's picker could never kill it
    # -> frozen video wallpaper + a stack of duplicate mpvpapers.
    # CONT first so a frozen mpvpaper can actually receive TERM.
    pkill -f "mpvpaper-autopause" 2>/dev/null
    pkill -f "wallpaper-guard"    2>/dev/null
    pkill -CONT -x mpvpaper 2>/dev/null
    pkill -TERM -x mpvpaper 2>/dev/null
    for _i in $(seq 1 10); do pgrep -x mpvpaper >/dev/null 2>&1 || break; sleep 0.1; done
    pkill -KILL -x mpvpaper  2>/dev/null
    pkill -TERM -x hyprpaper 2>/dev/null
    sleep 0.5
}

restart_wallpaper() {
    # serpantinum paints its own wallpaper layer (wallpaper-bg) and handles
    # video itself, so running the BITE-OS wallpaper scripts for it re-spawns
    # mpvpaper underneath a surface that already covers it -- a hidden video
    # decode burning CPU for nothing. Only caelestia needs this.
    # Takes the TARGET as $1 -- ACTIVE_SHELL_FILE isn't written until later in
    # swap_to, so reading it here would test the rice we're leaving.
    if [[ "${1:-}" == "serpantinum" ]]; then
        return 0
    fi
    # Both rices benefit from your existing wallpaper script (we patched
    # ilyamiro's autostart to call it). But hyprctl reload doesn't re-run
    # exec-once, so invoke it manually here every swap.
    if [[ -x "$HOME/.config/hypr/scripts/wallpaper.sh" ]]; then
        setsid -f "$HOME/.config/hypr/scripts/wallpaper.sh" restore </dev/null >/dev/null 2>&1
    elif [[ -x "$HOME/.config/hypr/scripts/wallpaper-restore.sh" ]]; then
        # ilyamiro ships no wallpaper.sh — its equivalent is wallpaper-restore.sh
        # (awww-daemon paints nothing until something runs `awww img`). Without
        # this branch a swap into ilyamiro left the desktop on whatever the old
        # rice had painted.
        setsid -f "$HOME/.config/hypr/scripts/wallpaper-restore.sh" </dev/null >/dev/null 2>&1
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
        trap - EXIT   # inherited from the parent; must not delete a newer run's lock
        sleep 4    # give the shell a moment to actually start
        local check
        case "$target" in
            caelestia) check=caelestia_alive ;;
            serpantinum) check=serpantinum_alive ;;
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
        serpantinum) launch_serpantinum_shell ;;
    esac

    log "step 5: settle + restart wallpaper"
    sleep 0.8
    restart_wallpaper "$target"

    # Keep the lock until the target shell is genuinely alive. Releasing at
    # script exit let a press land while the new rice was still coming up,
    # which is when a second swap does the most damage.
    local waited=0
    while (( waited < 150 )); do
        shell_ready "$target" && break
        sleep 0.1; waited=$((waited + 1))
    done
    if (( waited >= 150 )); then
        log "step 6: ${target} shell did NOT paint within 15s (watchdog will decide)"
    else
        log "step 6: ${target} shell painted after $((waited / 10))s"
    fi
    # Settle window: the bar can be mapped while popups/binds are still wiring
    # up, and releasing the lock the instant it appears let the next press
    # chain a fresh swap onto a barely-live shell. Two seconds of quiet is the
    # difference between "spam is ignored" and "spam melts the session".
    sleep 2

    # Swallow the swap chord's own trailing Super release.
    # caelestia opens its launcher on Super RELEASE unless launcherInterrupted
    # is set — but that flag lives in the shell process, so killing the shell
    # mid-chord resets it to false. Releasing Super after the swap then looked
    # like a bare Super tap and opened the launcher: a full-screen blurred
    # drawer with an input grab, i.e. a frozen-looking session. Re-arm the flag
    # on the fresh shell; the next real Super press clears it again.
    if [[ "$target" == "caelestia" ]]; then
        hyprctl dispatch global caelestia:launcherInterrupt >/dev/null 2>&1 || true
    fi

    echo "$target" > "$ACTIVE_SHELL_FILE"

    # If we're not the rescue, spawn watchdog. Rescue swaps don't watchdog
    # themselves (avoid loops).
    if [[ "${DOTS_RESCUE:-0}" != "1" ]]; then
        spawn_watchdog "$target"
    fi

    if [[ "$target" == "serpantinum" ]]; then
        notify "Now in serpantinum rice" "ESCAPE BACK: Super+Escape or Super+Ctrl+D for caelestia."
    else
        notify "Now in caelestia rice" "Your personal rice is restored. Super+Escape to swap again."
    fi
    log "swap_to $target complete"
}

cmd="${1:-status}"
case "$cmd" in
    caelestia|serpantinum)
        swap_to "$cmd"
        ;;
    toggle)
        # Call swap_to DIRECTLY. Re-execing "$0" here deadlocked against the
        # lock this process already holds: the child saw a live holder (its own
        # parent) and refused, so all four toggle binds silently did nothing.
        cur="$(cat "$ACTIVE_SHELL_FILE" 2>/dev/null || echo caelestia)"
        # Two rices: caelestia (stable) <-> serpantinum. ilyamiro was removed
        # 2026-09-07; anything unexpected lands on caelestia.
        case "$cur" in
            serpantinum) swap_to caelestia   ;;
            *)           swap_to serpantinum ;;
        esac
        ;;
    status)
        printf 'active-shell: %s\n' "$(cat "$ACTIVE_SHELL_FILE" 2>/dev/null || echo '(none)')"
        printf 'active-rice : %s\n' "$(~/.config/glitch/bin/rice current)"
        printf 'caelestia alive: %s\n' "$(caelestia_alive && echo yes || echo no)"
        printf 'serpantinum alive: %s\n' "$(serpantinum_alive && echo yes || echo no)"
        printf 'watchdog: %s\n' "$([[ -f "$WATCHDOG_PID_FILE" ]] && cat "$WATCHDOG_PID_FILE" || echo '(none)')"
        ;;
    help|--help|-h|"")
        sed -n '2,20p' "$0" | sed 's/^# \?//'
        ;;
    *)
        echo "unknown: $cmd" >&2; exit 2 ;;
esac
