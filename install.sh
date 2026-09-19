#!/bin/bash
# Собирает BrowserPicker, ставит в /Applications и запускает.
# Затем в окне настроек: «Назначить» браузером по умолчанию и включить автозапуск.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/build.sh"
"$DIR/build/BrowserPicker.app/Contents/MacOS/BrowserPicker" --selftest

pkill -x BrowserPicker 2>/dev/null || true
sleep 0.3

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/BrowserPicker.app"
cp -R "$DIR/build/BrowserPicker.app" "$DEST/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/BrowserPicker.app"
open "$DEST/BrowserPicker.app"
echo "Готово: BrowserPicker установлен в $DEST и запущен."
