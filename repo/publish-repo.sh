#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS — publish a rice update to the [bite-os] repo (GitHub Releases)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Run this whenever you change the rice and want installed users to get it via
# `bite-os-update`. It builds + SIGNS the bite-os package, builds the signed
# repo database, and uploads everything to the GitHub release tagged "repo".
#
#  ⚠  BUMP the version first! Edit pkg/bite-os/PKGBUILD and increase pkgrel
#     (e.g. pkgrel=1 -> 2) or pkgver, or pacman won't see it as an update.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISTRO="$(cd "$HERE/.." && pwd)"
REPO="$HERE/x86_64"
NAME="BITE-OS Repo Signing Key"
RELEASE_TAG="repo"
GH_REPO="GLITCH-BITE-404/BITE-OS"

KEYID="$(gpg --list-keys --with-colons "$NAME" 2>/dev/null | awk -F: '/^pub/{print $5; exit}')"
[ -n "${KEYID:-}" ] || { echo "No signing key. Run first:  bash repo/setup-signing.sh" >&2; exit 1; }
command -v gh >/dev/null || { echo "Need GitHub CLI:  sudo pacman -S github-cli  then  gh auth login" >&2; exit 1; }

mkdir -p "$REPO"
echo "==> Building + signing the bite-os package (version $(grep -E '^pkgver|^pkgrel' "$DISTRO/pkg/bite-os/PKGBUILD" | tr '\n' ' '))"
( cd "$DISTRO/pkg/bite-os" && GPGKEY="$KEYID" makepkg -f --sign --noconfirm )
cp -f "$DISTRO/pkg/bite-os/"bite-os-*.pkg.tar.zst     "$REPO/"
cp -f "$DISTRO/pkg/bite-os/"bite-os-*.pkg.tar.zst.sig "$REPO/"

echo "==> Building + signing the repo database..."
repo-add --sign --key "$KEYID" "$REPO/bite-os.db.tar.gz" "$REPO/"bite-os-*.pkg.tar.zst

# GitHub release assets can't be symlinks, so upload real files named bite-os.db/.files
# (that's exactly the names pacman asks for).
cp -f --remove-destination "$REPO/bite-os.db.tar.gz"        "$REPO/bite-os.db"
cp -f --remove-destination "$REPO/bite-os.db.tar.gz.sig"    "$REPO/bite-os.db.sig"
cp -f --remove-destination "$REPO/bite-os.files.tar.gz"     "$REPO/bite-os.files"
cp -f --remove-destination "$REPO/bite-os.files.tar.gz.sig" "$REPO/bite-os.files.sig"

echo "==> Uploading to GitHub release '$RELEASE_TAG'..."
gh release view "$RELEASE_TAG" --repo "$GH_REPO" >/dev/null 2>&1 || \
    gh release create "$RELEASE_TAG" --repo "$GH_REPO" \
        --title "BITE-OS package repo" \
        --notes "pacman repository for BITE-OS rice updates — do not delete."
gh release upload "$RELEASE_TAG" --repo "$GH_REPO" --clobber \
    "$REPO/"bite-os-*.pkg.tar.zst "$REPO/"bite-os-*.pkg.tar.zst.sig \
    "$REPO/bite-os.db" "$REPO/bite-os.db.sig" \
    "$REPO/bite-os.files" "$REPO/bite-os.files.sig"

echo
echo "✓ Published. Verify it's reachable:"
echo "    curl -sI https://github.com/$GH_REPO/releases/download/$RELEASE_TAG/bite-os.db | head -1"
echo "  Then installed BITE-OS systems get this rice on their next 'bite-os-update'."
