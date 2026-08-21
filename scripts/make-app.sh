#!/bin/bash
# Assemble Dangle.app from the SwiftPM build product. No Xcode required.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
PACK="${DANGLE_BUNDLE_PACK:-Packs/default/pack.json}"
VERSION="$(cat VERSION)"

# Release builds are universal so one download serves Intel and Apple
# silicon; debug builds stay host-only for speed. Per-triple builds + lipo
# rather than `--arch a --arch b`, which needs full Xcode's xcbuild.
APP="dist/Dangle.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$CONFIG" = "release" ]; then
    swift build -c release --triple arm64-apple-macosx14.0
    swift build -c release --triple x86_64-apple-macosx14.0
    lipo -create ".build/arm64-apple-macosx/release/DangleApp" \
                 ".build/x86_64-apple-macosx/release/DangleApp" \
         -output "$APP/Contents/MacOS/Dangle"
else
    swift build -c debug
    cp ".build/debug/DangleApp" "$APP/Contents/MacOS/Dangle"
fi
cp "$PACK" "$APP/Contents/Resources/pack.json"
# Copy any sounds or images that sit next to the pack; a failed copy fails
# the build rather than shipping a silently incomplete pack.
PACK_DIR="$(dirname "$PACK")"
shopt -s nullglob
for asset in "$PACK_DIR"/*; do
    base="$(basename "$asset")"
    [[ "$asset" == *.json || "$base" == .* || ! -f "$asset" ]] && continue
    cp "$asset" "$APP/Contents/Resources/"
done
shopt -u nullglob

# Bundle the default charm catalog so it's available offline at first
# launch — no "Get New Charms…" fetch needed for what ships with the app.
mkdir -p "$APP/Contents/Resources/Charms"
for charm in charms/*.json; do
    [ "$(basename "$charm")" = "index.json" ] && continue
    cp "$charm" "$APP/Contents/Resources/Charms/"
done

# A pack can carry charms of its own in a charms/ folder next to pack.json.
# They install alongside the catalog ones and show up in the Charm menu, so a
# private build can ship charms that were never published anywhere.
shopt -s nullglob
for charm in "$PACK_DIR"/charms/*.json; do
    [ "$(basename "$charm")" = "index.json" ] && continue
    cp "$charm" "$APP/Contents/Resources/Charms/"
done
shopt -u nullglob

if [ -f Assets/AppIcon.icns ]; then
    cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Dangle</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.melvin0070.Dangle</string>
    <key>CFBundleName</key>
    <string>Dangle</string>
    <key>CFBundleDisplayName</key>
    <string>Dangle</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>io.github.melvin0070.Dangle</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>dangle</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP (v$VERSION, pack: $PACK)"
