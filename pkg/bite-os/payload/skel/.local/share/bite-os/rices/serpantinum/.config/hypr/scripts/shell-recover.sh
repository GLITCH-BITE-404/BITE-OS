#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# shell-recover — restart the shell WITHOUT talking to the shell.
#
# `serpantinum reload` is `quickshell ipc call main forceReload`: it needs a live
# shell, so it is useless in exactly the case you need it. Everything here is
# process-level (pkill/pidfile) and reports through `hyprctl notify`, because
# Hyprland survives a shell crash but the notification daemon does not — it IS
# the shell.
#
# Bound statically in keybinds.conf.template, never from settings.json, so it
# still exists when a bad settings.json makes jq emit zero dynamic binds.

set -u

QS_BIN="quickshell"
PIDFILE="/tmp/serpantinumd.pid"
LOCKFILE="/tmp/serpantinumd.lock"

note() { hyprctl notify -1 4000 "rgb(88ccff)" "◈ shell-recover: $*" >/dev/null 2>&1; }
fail() { hyprctl notify -1 6000 "rgb(ff5555)" "◈ shell-recover: $*" >/dev/null 2>&1; }

# Resolve the shell entrypoint without sourcing serpantinum's helpers — those
# live in the tree we may be recovering from.
resolve_qml() {
    local d
    for d in "$HOME/.local/share/serpantinum/src" "${SERPANTINUM_DIR:-}"; do
        [ -n "$d" ] && [ -f "$d/quickshell/Shell.qml" ] && { echo "$d/quickshell/Shell.qml"; return 0; }
    done
    # Last resort: ask the running process what it was started with.
    local p; p="$(pgrep -x "$QS_BIN" | head -1)"
    if [ -n "$p" ]; then
        tr '\0' '\n' < "/proc/$p/cmdline" 2>/dev/null | grep -m1 'Shell\.qml$' && return 0
    fi
    return 1
}

stop_shell() {
    local qml="$1" pid=""
    [ -f "$PIDFILE" ] && pid="$(cat "$PIDFILE" 2>/dev/null)"

    pkill -TERM -f "focus_daemon.py"           2>/dev/null
    [ -n "$qml" ] && pkill -TERM -f "${QS_BIN}.*${qml}" 2>/dev/null
    [ -n "$pid" ] && kill -TERM "$pid"         2>/dev/null

    # Give it a moment to go down cleanly, then stop being polite.
    local n=0
    while [ "$n" -lt 20 ]; do
        pgrep -x "$QS_BIN" >/dev/null 2>&1 || break
        sleep 0.1; n=$((n+1))
    done

    pkill -KILL -f "focus_daemon.py"           2>/dev/null
    [ -n "$qml" ] && pkill -KILL -f "${QS_BIN}.*${qml}" 2>/dev/null
    pkill -KILL -f "serpantinumd"              2>/dev/null

    # Reap the watcher children too. Killing only the daemon + quickshell left
    # brightness.sh/kb_wait.sh/watchers orphaned, and every restart stacked
    # another set (12+ kb_wait after a handful of restarts). Matching the
    # directories catches them all, including ones future versions add --
    # same approach dots-switch.sh's kill_any_shell uses.
    # NOTE the literal path shape: helpers are spawned as
    # .../src/quickshell/../scripts/brightness.sh -- NOT .../src/scripts/ --
    # so a pattern on "src/scripts/" matches nothing. Verified against real
    # cmdlines; getting this wrong silently leaks a set per restart.
    pkill -KILL -f "serpantinum/src/quickshell/\.\./scripts/"     2>/dev/null
    pkill -KILL -f "serpantinum/src/quickshell/watchers/"        2>/dev/null
    pkill -KILL -f "inotifywait.*serpantinum"                    2>/dev/null
    # A stray Runner.qml from `serpantinum launch` is not the shell but does
    # hold ~140MB and confuses any pgrep -x quickshell.
    pkill -KILL -f "${QS_BIN} -p .*Runner\.qml"                 2>/dev/null

    # Stale pid/lock are why a crashed shell refuses to come back up.
    rm -f "$PIDFILE" "$LOCKFILE" 2>/dev/null
}

start_shell() {
    if [ -x "$HOME/.local/bin/serpantinumd" ]; then
        setsid "$HOME/.local/bin/serpantinumd" start >/dev/null 2>&1 < /dev/null &
        return 0
    fi
    local qml="$1"
    [ -n "$qml" ] || return 1
    setsid "$QS_BIN" -p "$qml" >/dev/null 2>&1 < /dev/null &
}

QML="$(resolve_qml || true)"

case "${1:-restart}" in
    stop)
        stop_shell "$QML"; note "stopped"
        ;;
    start)
        start_shell "$QML" && note "started" || fail "could not start"
        ;;
    restart|*)
        note "restarting…"
        stop_shell "$QML"
        sleep 0.3
        if start_shell "$QML"; then
            # Confirm it actually came back; a silent no-op is the failure mode
            # this whole script exists to avoid.
            n=0
            while [ "$n" -lt 50 ]; do
                pgrep -x "$QS_BIN" >/dev/null 2>&1 && { note "back up"; exit 0; }
                sleep 0.1; n=$((n+1))
            done
            fail "did not come back — run 'serpantinumd -v start' in a terminal"
            exit 1
        else
            fail "could not start"; exit 1
        fi
        ;;
esac
