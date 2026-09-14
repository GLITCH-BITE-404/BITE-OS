#!/usr/bin/env bash
# Migrate a caelestia-shell 1.6.x shell.json to 2.4.0 (BITE-OS):
#   notifs.fullscreen "on"/"off"  -> "On"/"Off"   (now an enum, case-sensitive)
#   bar.status.show*              -> removed      (2.4.0's statusIcons defaults
#                                                  = lockStatus on, audio off,
#                                                  kbLayout off: the same choices)
#   general.logo /home/<user>/... -> ~/...        (portable across installs;
#                                                  2.4.0 Paths.absolutePath expands ~)
# Keeps a .pre-2.4.0 backup next to each file. Usage: migrate-shell-json.sh FILE...
set -euo pipefail
for f in "$@"; do
    [ -f "$f" ] || { echo "skip (missing): $f"; continue; }
    jq -e . "$f" >/dev/null || { echo "skip (not JSON): $f"; continue; }
    cp -a "$f" "$f.pre-2.4.0"
    jq '
      (if (.notifs.fullscreen? | type) == "string"
         then .notifs.fullscreen |= (ascii_downcase | if . == "off" then "Off" else "On" end)
         else . end)
      | (if (.bar? | type) == "object" then .bar |= del(.status) else . end)
      | (if (.general.logo? | type) == "string"
         then .general.logo |= sub("^/home/[^/]+/"; "~/")
         else . end)
    ' "$f.pre-2.4.0" > "$f.tmp" && mv -f "$f.tmp" "$f"
    echo "migrated: $f"
done
