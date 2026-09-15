#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS — publish the [bite-os] update repo (GitHub Releases)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Installed BITE-OS systems pull updates from the GitHub release tagged "repo"
# (customize_airootfs.sh / bite-os.install wire it into /etc/pacman.conf with
# SigLevel = Required). So the release must hold a SIGNED database and a SIGNED
# copy of EVERY package that database lists -- a missing file or signature makes
# `pacman -Syu` fail on every install, not just skip the BITE-OS packages.
#
# This builds + signs a fresh bite-os package, takes every other package the ISO
# shipped from repo/x86_64 (so run build-all.sh / repo/build-repo.sh first),
# signs them, builds a signed database in repo/publish/ and checks it. Then it
# uploads packages first and the database last, removes assets the new database
# no longer lists, and checks the public copy.
#
#   bash repo/publish-repo.sh --dry-run   # build + sign + check, upload nothing
#   bash repo/publish-repo.sh             # ... and publish
#
#  ⚠  BUMP the version first! Edit pkg/bite-os/PKGBUILD and increase pkgrel
#     (e.g. pkgrel=1 -> 2) or pkgver, or pacman won't see it as an update.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISTRO="$(cd "$HERE/.." && pwd)"
REPO="$HERE/x86_64"
STAGE="$HERE/publish"
NAME="BITE-OS Repo Signing Key"
RELEASE_TAG="repo"
GH_REPO="GLITCH-BITE-404/BITE-OS"
URL="https://github.com/$GH_REPO/releases/download/$RELEASE_TAG"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

KEYID="$(gpg --list-keys --with-colons "$NAME" 2>/dev/null | awk -F: '/^pub/{print $5; exit}')"
[ -n "${KEYID:-}" ] || { echo "No signing key. Run first:  bash repo/setup-signing.sh" >&2; exit 1; }
[ "$DRY" = 1 ] || command -v gh >/dev/null || { echo "Need GitHub CLI:  sudo pacman -S github-cli  then  gh auth login" >&2; exit 1; }
[ -f "$REPO/bite-os.db.tar.gz" ] || { echo "No local repo in $REPO. Run build-all.sh (or repo/build-repo.sh) first." >&2; exit 1; }
export MAKEPKG_CONF="$HERE/makepkg-portable.conf"

echo "==> 1/5  Building + signing the bite-os package ($(grep -E '^pkgver|^pkgrel' "$DISTRO/pkg/bite-os/PKGBUILD" | tr '\n' ' '))"
# fingerprints first (it also reads the old packages we're about to clear)
bash "$DISTRO/tools/gen-skel-hashes.sh"
rm -f "$DISTRO/pkg/bite-os/"bite-os-*.pkg.tar.*
( cd "$DISTRO/pkg/bite-os" && GPGKEY="$KEYID" makepkg -f --sign --noconfirm )
BITE_PKG="$(cd "$DISTRO/pkg/bite-os" && makepkg --packagelist 2>/dev/null | grep -E '/bite-os-[^/]*\.pkg\.tar' | head -1)"
[ -f "$BITE_PKG" ] && [ -f "$BITE_PKG.sig" ] || { echo "!! could not find the signed bite-os package makepkg just built" >&2; exit 1; }

echo "==> 2/5  Collecting the packages the ISO shipped + the new bite-os"
rm -rf "$STAGE"; mkdir -p "$STAGE"
PKGS=()
while IFS= read -r f; do
    case "$f" in bite-os-[0-9]*) continue ;; esac   # replaced by the fresh build
    [ -f "$REPO/$f" ] || { echo "!! the local database lists $f but repo/x86_64 doesn't have it -- re-run repo/build-repo.sh" >&2; exit 1; }
    cp "$REPO/$f" "$STAGE/"; PKGS+=("$STAGE/$f")
done < <(bsdtar -xOf "$REPO/bite-os.db.tar.gz" '*/desc' | awk '/^%FILENAME%$/{getline; print}')
cp "$BITE_PKG" "$BITE_PKG.sig" "$STAGE/"; PKGS+=("$STAGE/${BITE_PKG##*/}")
echo "   ${#PKGS[@]} packages (bite-os: ${BITE_PKG##*/})"

echo "==> 3/5  Signing every package"
for p in "${PKGS[@]}"; do
    [ -f "$p.sig" ] || gpg --batch --yes --quiet -u "$KEYID" --detach-sign -o "$p.sig" "$p"
done

echo "==> 4/5  Building + signing the database"
repo-add --sign --key "$KEYID" "$STAGE/bite-os.db.tar.gz" "${PKGS[@]}"
# GitHub release assets can't be symlinks, so ship real files named bite-os.db /
# .files (exactly the names pacman asks for)
for x in db files; do
    cp -f --remove-destination "$STAGE/bite-os.$x.tar.gz"     "$STAGE/bite-os.$x"
    cp -f --remove-destination "$STAGE/bite-os.$x.tar.gz.sig" "$STAGE/bite-os.$x.sig"
done
DBFILES=("$STAGE/bite-os.db" "$STAGE/bite-os.db.sig" "$STAGE/bite-os.files" "$STAGE/bite-os.files.sig")

echo "==> 5/5  Checking"
bad=0
for f in "${PKGS[@]}" "$STAGE/bite-os.db" "$STAGE/bite-os.files"; do
    gpg --batch --quiet --verify "$f.sig" "$f" 2>/dev/null || { echo "!! bad or missing signature: ${f##*/}"; bad=1; }
done
listed="$(bsdtar -tf "$STAGE/bite-os.db" | grep -c '/desc$')"
[ "$listed" -eq "${#PKGS[@]}" ] || { echo "!! the database lists $listed packages but ${#PKGS[@]} are staged"; bad=1; }
[ "$bad" -eq 0 ] || exit 1
echo "   ok: ${#PKGS[@]} packages + the database, all signed by $KEYID"

if [ "$DRY" = 1 ]; then
    echo; echo "Dry run: nothing uploaded. Staged in $STAGE ($(du -sh "$STAGE" | cut -f1))."
    exit 0
fi

echo "==> Uploading to GitHub release '$RELEASE_TAG'..."
gh release view "$RELEASE_TAG" --repo "$GH_REPO" >/dev/null 2>&1 || \
    gh release create "$RELEASE_TAG" --repo "$GH_REPO" --latest=false \
        --title "BITE-OS package repo" \
        --notes "pacman repository for BITE-OS updates — do not delete."
# packages first, database last: a system syncing mid-upload must never see a
# database that points at packages that aren't there yet
UPLOAD=()
for p in "${PKGS[@]}"; do UPLOAD+=("$p" "$p.sig"); done
gh release upload "$RELEASE_TAG" --repo "$GH_REPO" --clobber "${UPLOAD[@]}"
gh release upload "$RELEASE_TAG" --repo "$GH_REPO" --clobber "${DBFILES[@]}"

# drop assets the new database no longer lists (old package versions)
keep="$(printf '%s\n' "${UPLOAD[@]##*/}" "${DBFILES[@]##*/}")"
gh release view "$RELEASE_TAG" --repo "$GH_REPO" --json assets -q '.assets[].name' | while read -r a; do
    grep -qxF "$a" <<<"$keep" || { gh release delete-asset "$RELEASE_TAG" "$a" --repo "$GH_REPO" -y && echo "   removed old $a"; }
done

echo "==> Checking the public copy..."
curl -sfL "$URL/bite-os.db" -o "$STAGE/.public.db" && cmp -s "$STAGE/.public.db" "$STAGE/bite-os.db" \
    || { echo "!! $URL/bite-os.db doesn't match what was just uploaded" >&2; exit 1; }
echo
echo "✓ Published ${#PKGS[@]} packages. Installed BITE-OS systems get them on their next 'bite-os-update'."
