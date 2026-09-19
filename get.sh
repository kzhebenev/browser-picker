#!/bin/bash
# Установка BrowserPicker на любой мак одной командой:
#   curl -fsSL https://raw.githubusercontent.com/kzhebenev/browser-picker/main/get.sh | bash
# curl не ставит карантин, поэтому Gatekeeper не блокирует самоподписанное приложение.
set -euo pipefail

URL="https://github.com/kzhebenev/browser-picker/releases/latest/download/BrowserPicker.dmg"
TMP="$(mktemp -d)"
trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "Скачиваю последний релиз..."
curl -fsSL "$URL" -o "$TMP/BrowserPicker.dmg"
mkdir -p "$TMP/mnt"
hdiutil attach -nobrowse -quiet -mountpoint "$TMP/mnt" "$TMP/BrowserPicker.dmg"

pkill -x BrowserPicker 2>/dev/null || true
sleep 0.3
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/BrowserPicker.app"
cp -R "$TMP/mnt/BrowserPicker.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/BrowserPicker.app" 2>/dev/null || true
open "$DEST/BrowserPicker.app"
echo "Готово: BrowserPicker установлен в $DEST и запущен."
echo "Разрешите его в «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ»."
