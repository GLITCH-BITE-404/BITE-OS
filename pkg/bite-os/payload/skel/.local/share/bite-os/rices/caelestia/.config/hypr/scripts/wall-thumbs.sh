#!/usr/bin/env bash
set -u

WALL_DIR="${CAELESTIA_WALLPAPERS_DIR:-$HOME/Pictures/Wallpapers}"
# This is the exact path Caelestia expects
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia/wallpapers"
mkdir -p "$CACHE_DIR"

shopt -s nullglob nocaseglob
for f in "$WALL_DIR"/*.{mp4,webm,mkv,mov,avi,gif,jpg,png,jpeg}; do
    [[ -f "$f" ]] || continue
    
    # Generate the SHA256 hash of the absolute path (Caelestia's naming convention)
    hash_name=$(echo -n "$f" | sha256sum | cut -d' ' -f1)
    thumb="$CACHE_DIR/$hash_name"

    # Only generate if the thumb is missing or the file is newer
    if [[ ! -f "$thumb" ]] || [[ "$f" -nt "$thumb" ]]; then
        # For videos: grab frame. For images: just copy/resize
        if [[ "$f" =~ \.(mp4|webm|mkv|mov|avi|gif)$ ]]; then
            ffmpeg -y -loglevel error -ss 0 -i "$f" -frames:v 1 -vf "scale=640:-2" "$thumb" 2>/dev/null
        else
            magick "$f" -resize 640x "$thumb" 2>/dev/null || cp "$f" "$thumb"
        fi
    fi
done
