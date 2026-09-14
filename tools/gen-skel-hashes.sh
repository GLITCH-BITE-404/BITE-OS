#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE-404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# gen-skel-hashes — fingerprint every version of every /etc/skel file BITE-OS
# has ever shipped, so bite-os-rice-update can tell "the user never touched
# this" (their copy matches a shipped version -> safe to update) from "the user
# edited this" (keep it).
#
# Sources: every git commit that touched the skel payload, plus every old
# bite-os package we still have. Output (git blob hashes, so the user side can
# use `git hash-object`):
#   pkg/bite-os/payload/branding/skel-hashes-past.tsv   <blobsha>\t<path>
# Run it before every package build:  tools/gen-skel-hashes.sh [extra pkg dirs]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKEL_REL="pkg/bite-os/payload/skel"
OUT="$ROOT/pkg/bite-os/payload/branding/skel-hashes-past.tsv"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

: > "$TMP/all"

# 1) git history (regular files only; mode 120000 = symlink)
git -C "$ROOT" log --format=%H -- "$SKEL_REL" | while read -r c; do
    git -C "$ROOT" -c core.quotePath=false ls-tree -r "$c" -- "$SKEL_REL"
done | awk -F'\t' -v pre="$SKEL_REL/" '{
        split($1, m, " ");
        if (m[1] == "120000" || m[2] != "blob") next;
        path = $2; if (index(path, pre) == 1) path = substr(path, length(pre) + 1);
        print m[3] "\t" path
    }' >> "$TMP/all"
echo "git history: $(wc -l < "$TMP/all") entries"

# 2) old packages
pkgs=()
for d in "$ROOT/repo/x86_64" "$ROOT/pkg/bite-os" "$@"; do
    [ -d "$d" ] || continue
    while IFS= read -r p; do pkgs+=("$p"); done < <(find "$d" -maxdepth 1 -name 'bite-os-*.pkg.tar.zst' 2>/dev/null)
done
for p in "${pkgs[@]}"; do
    x="$TMP/x"; rm -rf "$x"; mkdir -p "$x"
    bsdtar -xf "$p" -C "$x" etc/skel 2>/dev/null || continue
    ( cd "$x/etc/skel" && find . -type f -printf '%P\n' > "$TMP/list" \
      && sed "s|^|$x/etc/skel/|" "$TMP/list" | git hash-object --no-filters --stdin-paths > "$TMP/h" \
      && paste "$TMP/h" "$TMP/list" ) >> "$TMP/all"
    echo "package $(basename "$p"): $(wc -l < "$TMP/list") files"
done

sort -u "$TMP/all" > "$OUT"
echo "wrote $OUT: $(wc -l < "$OUT") distinct (hash, path) entries"
