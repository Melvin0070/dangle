#!/bin/bash
# Render Assets/AppIcon.icns from the 3D charm. Run once per charm change;
# the result is committed so release builds never need a GPU.
set -euo pipefail

cd "$(dirname "$0")/.."
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# PACK=path/to/pack.json renders the icon from that pack's charm.
swift run -c release DangleSnapshot --icon "$STAGE/icon-1024.png" ${PACK:+"$PACK"}

ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$STAGE/icon-1024.png" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$STAGE/icon-1024.png" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Assets
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
echo "Built Assets/AppIcon.icns"
