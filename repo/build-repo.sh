#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS — build the local [bite-os] pacman repo
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# mkarchiso can only install packages that live in a repo. This collects the
# `bite-os` package + the foreign (AUR) packages the rice needs into a local
# repo at repo/x86_64/.
#
# For each foreign package it: checks the pacman cache → checks paru's cache →
# builds it with paru if still missing. Failures are per-package (one bad one
# doesn't abort the rest), so you see exactly what needs hand-attention.
#
# Run as your normal user (NOT root):  bash build-repo.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/x86_64"
DISTRO="$(cd "$HERE/.." && pwd)"
CACHES=(/var/cache/pacman/pkg "$HOME/.cache/paru/clone")
mkdir -p "$REPO"

# PORTABLE BUILDS (critical): every package here ships to OTHER machines. The
# host /etc/makepkg.conf uses -march=native (+ rust target-cpu=native), which
# bakes THIS CPU's instruction set into the binaries → illegal-instruction
# crashes on any older CPU and in VMs that mask host features. That is what
# made quickshell/caelestia "crash in the live VM". MAKEPKG_CONF is honoured
# by makepkg AND by paru's makepkg calls.
export MAKEPKG_CONF="$HERE/makepkg-portable.conf"
[ -f "$MAKEPKG_CONF" ] || { echo "!! $MAKEPKG_CONF missing — refusing to build native-tainted packages" >&2; exit 1; }
echo "==> using portable makepkg config: $MAKEPKG_CONF (-march=x86-64, no native)"

# One-shot cache bypass: `bash build-repo.sh --rebuild-foreign` ignores every
# cached foreign package and rebuilds them all with the portable flags. Needed
# once after the 2026-07-14 native-taint fix (old cached pkgs are poisoned),
# and any time you change makepkg-portable.conf.
REBUILD_FOREIGN=0
[ "${1:-}" = "--rebuild-foreign" ] && REBUILD_FOREIGN=1

# newest .pkg.tar.* for a package name, searched across all caches.
# HARD-EXCLUDES x86_64_v3/_v4 arch builds: those need AVX2(+) and would crash
# the ISO on older CPUs and in VMs — the repo must only ever ship generic
# x86_64 (or any-arch) packages.
find_pkg() {
    local name="$1" hit=""
    for c in "${CACHES[@]}"; do
        hit="$(find "$c" -maxdepth 2 -name "${name}-*.pkg.tar.*" ! -name '*.sig' \
               ! -name '*-x86_64_v3.pkg.tar.*' ! -name '*-x86_64_v4.pkg.tar.*' 2>/dev/null \
               | sort -V | tail -1)"
        [ -n "$hit" ] && { echo "$hit"; return 0; }
    done
    return 1
}

echo "==> 1/4  Building the bite-os package (fresh)"
# Purge stale build artifacts FIRST. pkg/bite-os/ used to accumulate every old
# version (1.1-1 .. 1.1-N); the old `cp bite-os-*.pkg.tar.*` then copied ALL of
# them into the repo, `cp` reset their mtimes to "now", and the later
# `ls -t | keep-newest` heuristic could no longer tell which was current — so a
# STALE package (e.g. 1.1-7) won and shipped in the ISO (missing the latest skel,
# rice, plymouth theme, etc.). Clean slate avoids the whole ambiguity.
rm -f "$DISTRO/pkg/bite-os/"bite-os-*.pkg.tar.*
( cd "$DISTRO/pkg/bite-os" && makepkg -f --noconfirm ) || {
    echo "!! makepkg failed — fix PKGBUILD/payload, then re-run." >&2; exit 1; }
# Copy ONLY the package makepkg just built (resolved exactly, not globbed), and
# drop any older bite-os already sitting in the repo so repo-add can't pick it.
BITE_PKG="$(cd "$DISTRO/pkg/bite-os" && makepkg --packagelist 2>/dev/null | grep -E '/bite-os-[^/]*\.pkg\.tar' | head -1)"
if [ -z "$BITE_PKG" ] || [ ! -f "$BITE_PKG" ]; then
    echo "!! could not locate the freshly-built bite-os package (makepkg --packagelist)." >&2; exit 1; fi
rm -f "$REPO/"bite-os-*.pkg.tar.*
cp "$BITE_PKG" "$REPO/"
echo "   -> repo gets $(basename "$BITE_PKG")"

echo "==> 2/4  Building yaml-cpp-0.8 compat (calamares needs libyaml-cpp.so.0.8)"
# Reuse existing build if PKGBUILD hasn't changed (saves ~30s per ISO rebuild).
# --rebuild-foreign also forces this one (it's compiled C++, so a cached copy
# may carry the old -march=native taint).
EXISTING_YAML="$(find "$REPO" -maxdepth 1 -name 'yaml-cpp-0.8-*.pkg.tar.*' ! -name '*.sig' | head -1)"
[ "$REBUILD_FOREIGN" -eq 1 ] && EXISTING_YAML=""
if [ -n "$EXISTING_YAML" ] && [ "$EXISTING_YAML" -nt "$DISTRO/pkg/yaml-cpp-0.8/PKGBUILD" ]; then
    echo "   cached  yaml-cpp-0.8"
else
    ( cd "$DISTRO/pkg/yaml-cpp-0.8" && makepkg -f --noconfirm ) || {
        echo "!! yaml-cpp-0.8 makepkg failed — calamares won't start without it." >&2; exit 1; }
    cp "$DISTRO/pkg/yaml-cpp-0.8/"yaml-cpp-0.8-*.pkg.tar.* "$REPO/" 2>/dev/null
fi

echo "==> 3/4  Collecting foreign packages"
missing=()
while read -r p; do
    [ -z "$p" ] && continue
    # -bin packages ship prebuilt upstream binaries (generic), so the cache is
    # always safe for them; everything else is compiled here and must be
    # rebuilt with the portable flags when --rebuild-foreign is given.
    if [ "$REBUILD_FOREIGN" -eq 0 ] || [[ "$p" == *-bin ]]; then
        if f="$(find_pkg "$p")"; then
            cp "$f" "$REPO/"; echo "   ok    $p"
            continue
        fi
        echo "   build $p  (not cached — building with paru)"
    else
        echo "   build $p  (--rebuild-foreign — rebuilding with portable flags)"
    fi
    paru -S --rebuild --noconfirm --skipreview "$p" >/dev/null 2>&1
    if f="$(find_pkg "$p")"; then
        cp "$f" "$REPO/"; echo "   ok    $p  (built)"
    else
        missing+=("$p"); echo "   FAIL  $p"
    fi
done < "$HERE/foreign-packages.txt"

echo "==> 4/4  Indexing the repo"
# Keep only the newest bite-os package — older versions left in the dir make the
# (Rust) repo-add panic on the duplicate entry.
ls -t "$REPO"/bite-os-*.pkg.tar.* 2>/dev/null | tail -n +2 | xargs -r rm -f
# Rebuild the db from scratch so a stale/partial db from a crashed run can't
# crash repo-add again.
rm -f "$REPO"/bite-os.db* "$REPO"/bite-os.files*
repo-add "$REPO/bite-os.db.tar.gz" "$REPO/"*.pkg.tar.*
# GitHub Releases can't serve repo-add's symlink — ship a real file named
# bite-os.db so `pacman -Sy` can fetch the db over HTTPS.
rm -f "$REPO/bite-os.db" && cp "$REPO/bite-os.db.tar.gz" "$REPO/bite-os.db"

echo
echo "Local repo: $REPO  ($(find "$REPO" -name '*.pkg.tar.*' ! -name '*.sig' | wc -l) packages)"
if [ ${#missing[@]} -gt 0 ]; then
    echo "!! Could not get: ${missing[*]}"
    echo "   These aren't on the AUR. Get their source and 'makepkg' them, or"
    echo "   drop them from iso/packages.x86_64. Then re-run."
    exit 1
fi
echo "✓ All packages collected. Next: sudo bash build-iso.sh"
