#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# fetch-bundled-toys — the toys live in their own repo (BITE-OS-toys), not here.
# The bite-os package bundles a few of them (pkg/bite-os/payload/toys/) so they
# work offline on a fresh install. This fills that folder from the toys repo's
# catalog: latest version of each bundled toy, sha256-checked, unpacked.
#
# Only runs when the folder is missing (a fresh clone) — a local dev copy is
# never overwritten. --force refetches anyway.
#   tools/fetch-bundled-toys.sh [--force]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${BITE_TOYS_DEST:-$HERE/../pkg/bite-os/payload/toys}"
REPO="https://raw.githubusercontent.com/GLITCH-BITE-404/BITE-OS-toys/main"
BUNDLED=(bitebeat bitecam bitedig biteglyph bitemask bitemuseum bitewrite)

if [ -d "$DEST" ] && [ "${1:-}" != "--force" ]; then
    echo "==> bundled toys: using the existing $DEST"
    exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==> bundled toys: fetching the catalog from BITE-OS-toys"
curl -fsSL --connect-timeout 15 "$REPO/catalog.tsv" -o "$tmp/catalog.tsv"
mkdir -p "$tmp/out"
for name in "${BUNDLED[@]}"; do
    line="$(awk -F'\t' -v n="$name" '$1 == n' "$tmp/catalog.tsv" | tail -1)"
    [ -n "$line" ] || { echo "!! $name is not in the toys catalog" >&2; exit 1; }
    ver="$(cut -f2 <<<"$line")"; sha="$(cut -f3 <<<"$line")"
    curl -fsSL --connect-timeout 15 "$REPO/toys/$name-$ver.tar.gz" -o "$tmp/$name.tar.gz"
    echo "$sha  $tmp/$name.tar.gz" | sha256sum -c --quiet - \
        || { echo "!! $name-$ver.tar.gz does not match the catalog's sha256" >&2; exit 1; }
    tar -xzf "$tmp/$name.tar.gz" -C "$tmp/out"
    [ -d "$tmp/out/$name" ] || { echo "!! $name-$ver.tar.gz did not unpack to $name/" >&2; exit 1; }
    echo "   $name $ver"
done
rm -rf "$DEST"; mkdir -p "$(dirname "$DEST")"; mv "$tmp/out" "$DEST"
echo "==> bundled toys ready in $DEST"
