#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# bite-lock — lock the screen, shell or no shell.
#
# serpantinum's lock.sh is `quickshell ipc call lock activate`: if the shell is
# frozen or dead, Super+L silently does NOTHING and the machine cannot be
# locked. A locker that only works when everything else works is not a locker.
#
# Order: the styled shell lock when it is genuinely alive, otherwise fall
# through to whatever will actually put a lock on the screen.

set -u
QS_BIN="quickshell"

shell_alive() {
    pgrep -x "$QS_BIN" >/dev/null 2>&1 || return 1
    # Alive is not the same as responsive: ask the lock target to answer.
    local qml="${MAIN_QML:-$HOME/.local/share/serpantinum/src/quickshell/Shell.qml}"
    timeout 2 "$QS_BIN" -p "$qml" ipc show >/dev/null 2>&1
}

lock_via_shell()   { timeout 3 serpantinum lock >/dev/null 2>&1; }
lock_via_hyprlock() { command -v hyprlock >/dev/null 2>&1 || return 1
                      [ -f "$HOME/.config/hypr/hyprlock.conf" ] || return 1
                      hyprlock >/dev/null 2>&1 & sleep 0.5; pgrep -x hyprlock >/dev/null; }
lock_via_swaylock() { command -v swaylock >/dev/null 2>&1 || return 1
                      swaylock -f -c 0b0b0fee >/dev/null 2>&1; sleep 0.5
                      pgrep -x swaylock >/dev/null; }
lock_via_loginctl() { command -v loginctl >/dev/null 2>&1 && loginctl lock-session; }

if shell_alive && lock_via_shell; then
    exit 0
fi

hyprctl notify -1 3000 "rgb(ffaa00)" "◈ shell lock unavailable — fallback locker" >/dev/null 2>&1

lock_via_hyprlock && exit 0
lock_via_swaylock && exit 0
lock_via_loginctl && exit 0

hyprctl notify -1 6000 "rgb(ff5555)" "◈ LOCK FAILED — no locker available" >/dev/null 2>&1
exit 1
