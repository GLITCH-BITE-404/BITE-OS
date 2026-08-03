#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Finalizes the BITE-OS rebrand on the system side.
# Replaces upstream brand images with the BITE-OS icon, installs the
# BITE-OS plymouth theme, and activates it.
#
# Run with: sudo bash ~/.config/glitch/bin/install-glitch-os-system.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Re-run with sudo." >&2
    exit 1
fi

USER_HOME="/home/glitchbite404"
BRAND="$USER_HOME/.config/glitch/icons/icon.png"
SRC="$USER_HOME/.config/glitch/plymouth/glitch-os"
DST="/usr/share/plymouth/themes/glitch-os"

[[ -r $BRAND ]] || { echo "Brand icon not found: $BRAND" >&2; exit 1; }

# ── 1. Install BITE-OS plymouth theme ───────────────────────────────────────
echo ">> Installing BITE-OS plymouth theme to $DST"
rm -rf "$DST"
cp -r "$SRC" "$DST"
chown -R root:root "$DST"
chmod -R a+r "$DST"

# ── 2. Replace upstream branded images with BITE-OS icon ──────────────────────────
# Only brand/logo images. Leaves GTK widget assets (checkboxes, radios) alone —
# they aren't logos, replacing them breaks the GTK theme. Leaves plymouth UI
# widgets (bullet, throbber, capslock, lock, etc.) alone. Leaves wallpapers
# alone.
echo ">> Replacing upstream brand images with BITE-OS icon"

replace_with_icon() {
    local target="$1"
    [[ -e $target ]] || return 0
    cp -f "$BRAND" "$target"
    echo "   replaced: $target"
}

# Distro logo
replace_with_icon /usr/share/icons/cachyos.svg

# Application icons (hicolor)
for f in /usr/share/icons/hicolor/*/apps/org.cachyos.KernelManager.png \
         /usr/share/icons/hicolor/scalable/apps/org.cachyos.scx-manager.png \
         /usr/share/icons/hicolor/scalable/apps/cachyos-pi.png \
         /usr/share/icons/hicolor/scalable/apps/org.cachyos.hello.svg; do
    replace_with_icon "$f"
done

# Plymouth boot animation frames (animation-00..animation-87)
for f in /usr/share/plymouth/themes/cachyos-bootanimation/animation-*.png; do
    replace_with_icon "$f"
done

# Refresh GTK icon cache so new app icons take effect
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    echo ">> Refreshing icon cache"
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# ── 3. Switch active plymouth theme + rebuild initramfs ───────────────────────
echo ">> Activating BITE-OS theme + rebuilding initramfs"
plymouth-set-default-theme -R glitch-os

# ── 4. Disable upstream welcome autostart in skel ─────────────────────────────
rm -f /etc/skel/.config/autostart/cachyos-hello.desktop || true

# ── 5. Rewrite /etc/os-release and /etc/lsb-release so OS identity is BITE-OS
# Every distro-detection tool (fastfetch, neofetch, settings panels, login
# greeters, scripts that read /etc/os-release) will report BITE-OS after this.
# /etc/issue uses \S{PRETTY_NAME}, so it picks up the new value automatically.
echo ">> Rewriting /etc/os-release and /etc/lsb-release"

# Back up originals once (don't overwrite an existing backup on re-runs)
[[ -f /etc/os-release.preglitch ]]  || cp -a /etc/os-release  /etc/os-release.preglitch  2>/dev/null || true
[[ -f /etc/lsb-release.preglitch ]] || cp -a /etc/lsb-release /etc/lsb-release.preglitch 2>/dev/null || true

cat > /etc/os-release <<'EOF'
NAME="BITE-OS"
PRETTY_NAME="BITE-OS"
ID=glitch-os
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;180;80;255"
LOGO=glitch-os
EOF

cat > /etc/lsb-release <<'EOF'
DISTRIB_ID=glitch-os
DISTRIB_RELEASE="rolling"
DISTRIB_DESCRIPTION="BITE-OS"
EOF

# Place a BITE-OS-named distro logo where LOGO= points apps to look it up.
# /usr/share/pixmaps/<LOGO>.{png,svg} and the hicolor scalable apps dir are the
# two conventions tools like fastfetch / GNOME-About / KInfoCenter check.
install -Dm644 "$BRAND" /usr/share/pixmaps/glitch-os.png
install -Dm644 "$BRAND" /usr/share/icons/hicolor/scalable/apps/glitch-os.png

# Refresh icon cache again now that we added glitch-os.png
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

echo
echo "Done. Reboot to see the BITE-OS splash."
echo
echo "Notes:"
echo " - Wallpapers were not touched."
echo " - GTK widget SVGs were not touched (they aren't logos,"
echo "   replacing them would break checkbox/radio rendering)."
echo " - On the next 'pacman -Syu', any upstream brand files we overwrote"
echo "   will be restored by their owning packages. Re-run this script,"
echo "   or remove the upstream brand packages:"
echo "   pacman -Rns cachyos-plymouth-bootanimation cachyos-hello cachyos-kernel-manager"
