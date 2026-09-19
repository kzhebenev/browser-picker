#!/bin/bash
# Собирает BrowserPicker.app и упаковывает в build/BrowserPicker.dmg для других маков и релизов.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/build.sh"
"$DIR/build/BrowserPicker.app/Contents/MacOS/BrowserPicker" --selftest

DMG="$DIR/build/BrowserPicker.dmg"
STAGE="$DIR/build/dmg-root"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$DIR/build/BrowserPicker.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname BrowserPicker -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "Готово: $DMG"
