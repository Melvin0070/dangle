#!/bin/bash
# Wrap dist/Dangle.app in a drag-to-Applications DMG.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Dangle.app"
DMG="${1:-dist/Dangle.dmg}"
VERSION="$(cat VERSION)"

[ -d "$APP" ] || { echo "Build the app first: make app" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# hdiutil create intermittently fails on busy CI runners ("resource busy");
# a couple of retries make the release job reliable.
for attempt in 1 2 3; do
    if hdiutil create -volname "Dangle $VERSION" -srcfolder "$STAGE" \
        -fs HFS+ -format UDZO -quiet "$DMG"; then
        echo "Built $DMG"
        exit 0
    fi
    echo "hdiutil attempt $attempt failed; retrying..." >&2
    sleep 3
done
echo "hdiutil failed after 3 attempts" >&2
exit 1
