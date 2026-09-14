#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# update_notifier — is there a newer BITE-OS than the one you are running?
#
# This used to poll ilyamiro/imperative-dots and read
# ~/.local/state/imperative-dots-version, which does not exist on BITE-OS -- so
# LOCAL_VERSION was always "Unknown", the comparison could never fire, and it
# curled a stranger's repo every 10 minutes forever. It now checks BITE-OS.
#
# Truth for local  : pacman -Q bite-os   (the package carries pkgver-pkgrel)
# Truth for remote : the PKGBUILD on main -- no release process needed, and it
#                    is correct the moment a version bump is pushed.
#
# Writes state the guide reads, so the panel and the notification never
# disagree about what is available.
set -uo pipefail

INTERVAL="${BITE_UPDATE_INTERVAL:-3600}"
RAW_URL="${BITE_UPDATE_URL:-https://raw.githubusercontent.com/GLITCH-BITE-404/BITE-OS/main/pkg/bite-os/PKGBUILD}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bite-os"
STATE="$STATE_DIR/update.json"
NOTIFIED="$STATE_DIR/notified_version"
mkdir -p "$STATE_DIR"

# Single-instance: autostart and dots-switch both launch this. noclobber, not
# flock -- the same fd-inheritance trap that doubled autostart.conf.
LOCK="$STATE_DIR/notifier.pid"
_take() { ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; }
if ! _take; then
    h="$(cat "$LOCK" 2>/dev/null)"
    if [ -n "$h" ] && kill -0 "$h" 2>/dev/null; then exit 0; fi
    rm -f "$LOCK"; _take || exit 0
fi
trap 'rm -f "$LOCK"' EXIT INT TERM HUP

local_version() {
    # Installed package first; the build tree is the fallback so the check is
    # still meaningful on a dev box where bite-os is not installed.
    local v
    v="$(pacman -Q bite-os 2>/dev/null | awk '{print $2}')"
    if [ -n "$v" ]; then printf '%s' "$v"; return; fi
    local pb="$HOME/bite-os-distro/pkg/bite-os/PKGBUILD"
    if [ -f "$pb" ]; then
        printf '%s-%s' "$(awk -F= '/^pkgver=/{print $2;exit}' "$pb")" \
                       "$(awk -F= '/^pkgrel=/{print $2;exit}' "$pb")"
    fi
}

remote_version() {
    local body
    body="$(curl -fsS --max-time 8 "$RAW_URL" 2>/dev/null)" || return 1
    local ver rel
    ver="$(printf '%s' "$body" | awk -F= '/^pkgver=/{print $2;exit}')"
    rel="$(printf '%s' "$body" | awk -F= '/^pkgrel=/{print $2;exit}')"
    [ -n "$ver" ] || return 1
    printf '%s-%s' "$ver" "${rel:-1}"
}

write_state() {
    printf '{"local":"%s","remote":"%s","available":%s,"checked":%s}\n' \
        "$1" "$2" "$3" "$(date +%s)" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
}

while true; do
    LOCAL="$(local_version)"
    REMOTE="$(remote_version || true)"

    if [ -z "$LOCAL" ] || [ -z "$REMOTE" ]; then
        # Offline or not installed: record it rather than silently doing nothing,
        # so the guide can say "couldn't check" instead of "up to date".
        write_state "${LOCAL:-unknown}" "${REMOTE:-unknown}" "false"
    else
        NEWEST="$(printf '%s\n%s\n' "$LOCAL" "$REMOTE" | sort -V | tail -n1)"
        if [ "$NEWEST" = "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
            write_state "$LOCAL" "$REMOTE" "true"
            if [ ! -f "$NOTIFIED" ] || [ "$(cat "$NOTIFIED" 2>/dev/null)" != "$REMOTE" ]; then
                printf '%s' "$REMOTE" > "$NOTIFIED"
                notify-send -a "BITE-OS" -i "system-software-update" \
                    "BITE-OS $REMOTE is out" \
                    "You are on $LOCAL. Super+U to update." 2>/dev/null || true
            fi
        else
            write_state "$LOCAL" "$REMOTE" "false"
        fi
    fi
    sleep "$INTERVAL"
done
