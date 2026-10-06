#!/bin/bash
# Renders a scene at 1920x1080 with Godot's Movie Maker and keeps one frame.
#   tools/render_frame.sh res://fighter/turntable.tscn 150 out.png
# GODOT can point at the editor executable (defaults to the path used on this machine).
set -e
GODOT="${GODOT:-/c/Users/kestanol/Desktop/Godot_v4.7.2-stable_win64.exe}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FRAME="$2"
if [ -e "$ROOT/override.cfg" ]; then echo "override.cfg already exists; refusing to overwrite it" >&2; exit 1; fi
# Movie Maker records at the project's base viewport size, so raise it temporarily.
printf '[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > "$ROOT/override.cfg"
trap 'rm -f "$ROOT/override.cfg"; rm -rf "$TMP"' EXIT
"$GODOT" --path "$ROOT" --write-movie "$TMP/f.png" --fixed-fps 60 --quit-after $((FRAME + 1)) "$1" > "$TMP/log.txt" 2>&1 || true
grep -E 'ERROR|SHADER ERROR' "$TMP/log.txt" >&2 || true
cp "$TMP/f$(printf '%08d' "$FRAME").png" "$3"
echo "saved $3"
