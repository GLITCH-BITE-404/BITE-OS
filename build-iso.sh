#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS — build the installable ISO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Takes the stock archiso `releng` profile, overlays the BITE-OS customisations
# from iso/, merges the package lists, and runs mkarchiso.
#
# Prereqs:  sudo pacman -S archiso          (build tool)
#           bash repo/build-repo.sh         (local [bite-os] repo must exist)
#
# Run:  sudo bash build-iso.sh
# Output: out/bite-os-1.0-x86_64.iso
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail
DISTRO="$(cd "$(dirname "$0")" && pwd)"
# Build on real disk, NOT /tmp — /tmp is RAM-backed (tmpfs) and the ~10 GB
# airootfs overflows it, causing "Write failed" extraction errors.
PROFILE="$DISTRO/.build-profile"
WORK="$DISTRO/.build-work"
OUT="$DISTRO/out"

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash build-iso.sh" >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "missing archiso: pacman -S archiso" >&2; exit 1; }
[ -f "$DISTRO/repo/x86_64/bite-os.db.tar.gz" ] || {
    echo "local repo not built — run: bash repo/build-repo.sh" >&2; exit 1; }

echo "==> Preparing profile from stock releng"
rm -rf "$PROFILE" "$WORK"
cp -r /usr/share/archiso/configs/releng "$PROFILE"

# Merge package lists: releng's live-boot essentials + the BITE-OS set.
cat "$PROFILE/packages.x86_64" "$DISTRO/iso/packages.x86_64" \
    | grep -vE '^\s*#|^\s*$' | sort -u > /tmp/bite-pkgs.txt

# Drop releng-inherited packages that no longer resolve in our enabled repos.
# Without this, a package Arch removes upstream aborts the whole build at
# "target not found" with no way to override it from iso/packages.x86_64.
if [ -f "$DISTRO/iso/packages.exclude" ]; then
    grep -vE '^\s*#|^\s*$' "$DISTRO/iso/packages.exclude" | sort -u > /tmp/bite-excl.txt
    if [ -s /tmp/bite-excl.txt ]; then
        echo "==> Excluding: $(tr '\n' ' ' < /tmp/bite-excl.txt)"
        comm -23 /tmp/bite-pkgs.txt /tmp/bite-excl.txt > /tmp/bite-pkgs.filtered
        mv /tmp/bite-pkgs.filtered /tmp/bite-pkgs.txt
    fi
    rm -f /tmp/bite-excl.txt
fi

echo "==> Overlaying BITE-OS customisations"
cp -rf "$DISTRO/iso/." "$PROFILE/"
mv /tmp/bite-pkgs.txt "$PROFILE/packages.x86_64"
chmod +x "$PROFILE/airootfs/usr/local/bin/bite-os-live-setup" 2>/dev/null || true

echo "==> Building ISO (this takes a while)"
mkdir -p "$OUT"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

echo
echo "✓ Done. ISO is in: $OUT"
echo "  Test it: boot the .iso in a VM (GNOME Boxes / virt-manager) before publishing."
