#!/usr/bin/env bash
# The same procedural renderer supplies Finder icons for both channels.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
binary=$1
channel=$2
destination=$3
case "$channel" in production|development) ;; *) echo 'Unknown icon channel' >&2; exit 1 ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$binary" --render-icon "$work/icon.png" --icon-channel "$channel" >&2
mkdir "$work/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon.png" --out "$work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$work/icon.png" \
    --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$work/AppIcon.iconset" -o "$destination"
[ -s "$destination" ] || { echo 'Icon export was empty' >&2; exit 1; }
