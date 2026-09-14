#!/usr/bin/env bash

# File paths
SETTINGS_FILE="$HOME/.config/hypr/settings.json"
WEATHER_SCRIPT="$HOME/.config/hypr/scripts/quickshell/calendar/weather.sh"
ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

# Target configuration files
CONF_DIR="$HOME/.config/hypr/config"
TMPL_DIR="$HOME/.config/hypr/templates"
SETTINGS_CONF="$CONF_DIR/settings.conf"
AUTOSTART_CONF="$CONF_DIR/autostart.conf"
ENV_CONF="$CONF_DIR/env.conf"
KEYBINDS_CONF="$CONF_DIR/keybindings.conf"
MONITORS_CONF="$CONF_DIR/monitors.conf"
ZSH_RC="$HOME/.zshrc"

# ─── widget-bind contract ─────────────────────────────────────────────────
# settings.json binds name shell widgets, but nothing ever checked those names
# existed. getLayout() returns undefined for an unknown target and Main.qml's
# handleCommand then silently returns -- exit 0, no error, dead key. That is
# how Super+B stayed broken. Two layers: rewrite known renames, then warn on
# whatever is still unresolved.

# Legacy target -> current widget. Keeps BITE-OS binds working across
# serpantinum renames without hand-editing settings.json.
declare -A WIDGET_ALIASES=(
    [battery]=system      # battery UI folded into syspanel/SystemPanel.qml
    [movies]=music        # no movies component exists (dead name upstream in
                          # serpantinum's _allWidgetNames); media/MusicPopup.qml
                          # is the only real media widget, so Super+P opens that
)

# Handled in handleCommand BEFORE the getLayout() gate, so they are valid
# despite having no WindowRegistry entry. Not orphans.
WIDGET_SPECIAL="launcher clipboard clip airplane flight hidden"

# The authoritative list of openable widgets, read from the live shell.
serp_widget_targets() {
    local reg="${SERPANTINUM_DIR:-$HOME/.local/share/serpantinum/src}/quickshell/WindowRegistry.js"
    [ -f "$reg" ] || return 1
    sed -n '/let base = {/,/^    };/p' "$reg" \
        | grep -oE '^[[:space:]]{8}"[a-z]+"' | tr -d ' "'
}

apply_widget_aliases() {
    local f="$1" legacy current
    for legacy in "${!WIDGET_ALIASES[@]}"; do
        current="${WIDGET_ALIASES[$legacy]}"
        sed -i -E "s/(msg (toggle|open)) ${legacy}\b/\1 ${current}/g" "$f"
    done
}

# Warn loudly instead of shipping a key that does nothing.
validate_widget_binds() {
    local f="$1" valid orphans=""
    valid="$(serp_widget_targets 2>/dev/null) $WIDGET_SPECIAL"
    [ -n "${valid// /}" ] || return 0   # shell tree missing; nothing to check against

    local t
    for t in $(grep -oE 'msg (toggle|open) [a-z]+' "$f" | awk '{print $3}' | sort -u); do
        printf '%s\n' $valid | grep -qx "$t" || orphans="$orphans $t"
    done

    [ -z "$orphans" ] && return 0
    echo "WARNING: keybind targets not present in the shell:$orphans"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -u critical "BITE-OS keybinds" "Dead widget target(s):$orphans" 2>/dev/null
    hyprctl notify -1 6000 "rgb(ffaa00)" "◈ dead keybind target(s):$orphans" >/dev/null 2>&1
    return 1
}

# Ensure the required files and directories exist
mkdir -p "$CONF_DIR" "$TMPL_DIR" "$(dirname "$SETTINGS_FILE")" "$(dirname "$ENV_FILE")"
[ ! -f "$SETTINGS_FILE" ] && echo "{}" > "$SETTINGS_FILE"

CACHE_DIR="$HOME/.cache/settings_watcher"
mkdir -p "$CACHE_DIR"

compile_settings() {
    # Own lock, separate from the watcher lock: prevents two regenerations from
    # interleaving `cp template` + append, which is what doubled autostart.conf.
    local _clock="$CACHE_DIR/compile.pid"
    if ! ( set -o noclobber; echo $$ > "$_clock" ) 2>/dev/null; then
        local _h; _h="$(cat "$_clock" 2>/dev/null)"
        if [ -n "$_h" ] && kill -0 "$_h" 2>/dev/null; then
            echo "compile already in progress (pid $_h) — skipping"
            return 0
        fi
        rm -f "$_clock"
        ( set -o noclobber; echo $$ > "$_clock" ) 2>/dev/null || return 0
    fi
    trap 'rm -f "$_clock"' RETURN

    echo "Regenerating configurations from templates..."

    # Hash existing configs before any changes, split by monitor vs non-monitor.
    # This means a pure uiScale/wallpaperDir/weatherApiKey write never triggers a reload.
    OLD_NONMON_HASH=$(md5sum "$SETTINGS_CONF" "$KEYBINDS_CONF" "$AUTOSTART_CONF" "$ENV_CONF" 2>/dev/null | md5sum)
    OLD_MON_HASH=$(md5sum "$MONITORS_CONF" 2>/dev/null | md5sum)

    # Read state from JSON (Using 'has' to safely parse booleans)
    LANG=$(jq -r '.language // "us"' "$SETTINGS_FILE")
    # Whitespace around a layout code ("us, ru,il") produces an invalid xkb entry
    # and duplicates break group switching — normalise before templating.
    LANG=$(printf '%s' "$LANG" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
           | awk 'NF && !seen[$0]++' | paste -sd, -)
    [ -z "$LANG" ] && LANG="us"
    KB_OPT=$(jq -r '.kbOptions // "grp:alt_shift_toggle"' "$SETTINGS_FILE")
    WP_DIR=$(jq -r '.wallpaperDir // empty' "$SETTINGS_FILE")

    # Safely parse booleans so "false" doesn't trigger a fallback
    GUIDE_STARTUP=$(jq -r 'if has("openGuideAtStartup") then .openGuideAtStartup else true end' "$SETTINGS_FILE")

    PIC_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
    VID_DIR="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"

    # Read the hardware variables injected by install.sh directly out of the JSON
    HW_ENV=$(jq -r '.hardwareEnvs[]? // empty' "$SETTINGS_FILE")

    # 1. Regenerate env.conf using the template
    echo "Regenerating env.conf..."
    sed -e "s|{{XDG_PICTURES_DIR}}|$PIC_DIR|g" \
        -e "s|{{XDG_VIDEOS_DIR}}|$VID_DIR|g" \
        -e "s|{{WALLPAPER_DIR}}|$WP_DIR|g" \
        -e "s|{{SCRIPT_DIR}}|$HOME/.config/hypr/scripts|g" \
        "$TMPL_DIR/env.conf.template" > "${ENV_CONF}.tmp"

    # Use awk to safely substitute the multi-line HW_ENV array without breaking escapes
    awk -v hw="$HW_ENV" '{
        if (index($0, "{{HARDWARE_ENV}}")) {
            print hw
        } else {
            print $0
        }
    }' "${ENV_CONF}.tmp" > "$ENV_CONF"
    rm -f "${ENV_CONF}.tmp"

    # Sync ZSH_RC if Wallpaper Dir changed
    if [ -n "$WP_DIR" ] && [ -f "$ZSH_RC" ]; then
        sed -i "s|^export WALLPAPER_DIR=.*|export WALLPAPER_DIR=\"$WP_DIR\"|" "$ZSH_RC"
    fi

    # 2. Regenerate settings.conf using template
    echo "Regenerating settings.conf..."
    sed -e "s|{{KB_LAYOUT}}|$LANG|g" \
        -e "s|{{KB_OPTIONS}}|$KB_OPT|g" \
        "$TMPL_DIR/settings.conf.template" > "$SETTINGS_CONF"

    # 3. Regenerate autostart.conf
    echo "Regenerating autostart.conf..."
    # Built in a temp file and moved into place: an append-in-place build is
    # what let two writers interleave into a doubled autostart.conf.
    _AS_TMP="$(mktemp "${AUTOSTART_CONF}.XXXXXX")"
    cp "$TMPL_DIR/autostart.conf.template" "$_AS_TMP"

    # Dump normal startup entries
    jq -r '.startup[]? | "exec-once = \(.command)"' "$SETTINGS_FILE" >> "$_AS_TMP"

    # Evaluate the guide boolean natively in jq and output the line ONLY if it resolves to true
    if [[ $(jq -r 'if (if type == "object" and has("openGuideAtStartup") then .openGuideAtStartup else true end) then "yes" else "no" end' "$SETTINGS_FILE") == "yes" ]]; then
        echo "exec-once = bash -c 'sleep 1 && serpantinum msg toggle guide'" >> "$_AS_TMP"
    fi
    mv -f "$_AS_TMP" "$AUTOSTART_CONF"

    # 4. Regenerate keybindings.conf
    echo "Regenerating keybindings.conf..."
    cp "$TMPL_DIR/keybinds.conf.template" "$KEYBINDS_CONF"
    # Built via temp file so aliases are applied before the binds land, and so a
    # jq failure cannot leave a half-written keybindings.conf in place.
    _KB_TMP="$(mktemp "${KEYBINDS_CONF}.XXXXXX")"
    jq -r '.keybinds[]? | "\(.type // "bind") = \(.mods // ""), \(.key // ""), \(.dispatcher // "exec")\(if .command and .command != "" then ", \(.command)" else "" end)"' "$SETTINGS_FILE" > "$_KB_TMP"
    apply_widget_aliases "$_KB_TMP"
    cat "$_KB_TMP" >> "$KEYBINDS_CONF"
    rm -f "$_KB_TMP"
    validate_widget_binds "$KEYBINDS_CONF" || true

    # 5. Regenerate monitors.conf
    echo "Regenerating monitors.conf..."
    cp "$TMPL_DIR/monitors.conf.template" "$MONITORS_CONF"
    MONITOR_COUNT=$(jq '.monitors | length' "$SETTINGS_FILE" 2>/dev/null)
    if [[ "$MONITOR_COUNT" -gt 0 ]]; then
        jq -r '.monitors[]? | "monitor = \(.name), \(.resW)x\(.resH)@\(.rate), \(.x)x\(.y), \(.scale)\(if .transform and .transform != 0 then ", transform, \(.transform)" else "" end)"' "$SETTINGS_FILE" >> "$MONITORS_CONF"
    else
        echo "monitor = , preferred, auto, 1" >> "$MONITORS_CONF"
    fi

    # Hash after changes
    NEW_NONMON_HASH=$(md5sum "$SETTINGS_CONF" "$KEYBINDS_CONF" "$AUTOSTART_CONF" "$ENV_CONF" 2>/dev/null | md5sum)
    NEW_MON_HASH=$(md5sum "$MONITORS_CONF" 2>/dev/null | md5sum)

    if [ "$OLD_MON_HASH" != "$NEW_MON_HASH" ]; then
        # Monitor layout actually changed — full reload needed
        echo "Monitor config changed, reloading Hyprland..."
        hyprctl reload
    elif [ "$OLD_NONMON_HASH" != "$NEW_NONMON_HASH" ]; then
        # Non-monitor settings changed (keybinds, autostart, input, env) — reload safe, no display flicker
        echo "Non-monitor config changed, reloading Hyprland..."
        hyprctl reload
    else
        # Nothing that affects Hyprland changed (e.g. uiScale, weatherApiKey) — skip reload entirely
        echo "No Hyprland config changes detected, skipping reload."
    fi
}

# --compile is a one-shot regeneration (install.sh, dots-switch, manual repair).
# It must NOT take the watcher's single-instance lock: that lock means "only one
# inotify loop", not "only one regeneration", and conflating them made
# `--compile` a silent no-op whenever a watcher was already up. compile_settings
# takes its own short-lived lock instead, so two regenerations still cannot
# interleave -- which was the actual doom-loop defect.
if [[ "${1:-}" == "--compile" ]]; then
    compile_settings
    exit $?
fi

# ─── single-instance guard ────────────────────────────────────────────────
# This is launched from BOTH autostart.conf and dots-switch.sh, so copies
# accumulated. Concurrent copies then regenerated autostart.conf at the same
# time — `cp template` + `jq >>` from two writers interleaves into a file with
# every exec-once listed TWICE, including `quickshell` and this watcher itself.
# Next login therefore started two shells and two watchers, which doubled the
# file again: a compounding loop that ends in a stack of bars. Not flock — the
# inotifywait children would inherit and pin the fd if this script died first.
WATCH_LOCK="$CACHE_DIR/watcher.pid"
_take_lock() { ( set -o noclobber; echo $$ > "$WATCH_LOCK" ) 2>/dev/null; }
if ! _take_lock; then
    _holder="$(cat "$WATCH_LOCK" 2>/dev/null)"
    if [ -n "$_holder" ] && kill -0 "$_holder" 2>/dev/null; then
        echo "settings_watcher already running (pid $_holder) — exiting"
        exit 0
    fi
    rm -f "$WATCH_LOCK"
    _take_lock || exit 0
fi
trap 'rm -f "$WATCH_LOCK"' EXIT INT TERM HUP

echo "Started watching settings directories for changes..."

inotifywait -m -q -e close_write,moved_to --format '%w%f' "$(dirname "$SETTINGS_FILE")" "$(dirname "$ENV_FILE")" | while read -r filepath; do

    # ---------------------------------------------------------
    # SETTINGS JSON TRIGGER
    # ---------------------------------------------------------
    if [[ "$filepath" == "$SETTINGS_FILE" ]]; then
        compile_settings
    fi

    # ---------------------------------------------------------
    # .ENV WEATHER TRIGGER
    # ---------------------------------------------------------
    if [[ "$filepath" == "$ENV_FILE" ]]; then
        echo ".env updated! Forcing weather cache refresh..."
        if [ -x "$WEATHER_SCRIPT" ]; then
            "$WEATHER_SCRIPT" --getdata &
        else
            bash "$WEATHER_SCRIPT" --getdata &
        fi
    fi
done
