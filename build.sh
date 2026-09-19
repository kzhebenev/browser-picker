#!/bin/bash
# Собирает build/BrowserPicker.app (нужны только Command Line Tools).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/build/BrowserPicker.app"
VERSION="$(tr -d '[:space:]' < "$DIR/VERSION")"
BUILD_NUMBER="$(git -C "$DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
SOURCES=("$DIR/Log.swift" "$DIR/Config.swift" "$DIR/Browsers.swift" "$DIR/Picker.swift" "$DIR/Updater.swift" "$DIR/LinkCatcher.swift" "$DIR/SettingsView.swift" "$DIR/main.swift")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Компилирую..."
swiftc -O -target arm64-apple-macosx13.0 -framework Cocoa -framework SwiftUI -framework ServiceManagement \
    "${SOURCES[@]}" -o "$DIR/build/BrowserPicker-arm64"
swiftc -O -target x86_64-apple-macosx13.0 -framework Cocoa -framework SwiftUI -framework ServiceManagement \
    "${SOURCES[@]}" -o "$DIR/build/BrowserPicker-x86_64"
lipo -create "$DIR/build/BrowserPicker-arm64" "$DIR/build/BrowserPicker-x86_64" -output "$APP/Contents/MacOS/BrowserPicker"
rm -f "$DIR/build/BrowserPicker-arm64" "$DIR/build/BrowserPicker-x86_64"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>ru.devkz.browserpicker</string>
    <key>CFBundleName</key><string>BrowserPicker</string>
    <key>CFBundleDisplayName</key><string>BrowserPicker</string>
    <key>CFBundleExecutable</key><string>BrowserPicker</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Константин Жебенев. Лицензия MIT.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>Web site URL</string>
            <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
            <key>LSHandlerRank</key><string>Default</string>
        </dict>
        <dict>
            <key>CFBundleURLName</key><string>BrowserPicker command</string>
            <key>CFBundleURLSchemes</key><array><string>browserpicker</string></array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>HTML document</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Default</string>
            <key>LSItemContentTypes</key>
            <array><string>public.html</string><string>public.xhtml</string><string>public.url</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ ! -f "$DIR/icon/AppIcon.icns" ] || [ "$DIR/icon/make-icon.swift" -nt "$DIR/icon/AppIcon.icns" ]; then
    (cd "$DIR" && swift icon/make-icon.swift >/dev/null && iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns)
fi
cp "$DIR/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$DIR/LICENSE" "$APP/Contents/Resources/LICENSE"

# Разрешение «Универсальный доступ» macOS привязывает к подписи. Ad-hoc подпись меняется
# с каждой сборкой, поэтому подписываем постоянным самоподписанным сертификатом.
KEYCHAIN="$HOME/Library/Keychains/browserpicker.keychain-db"
CN="BrowserPicker Self-Signed"
PASSFILE="$HOME/Library/Application Support/BrowserPicker/signing.pass"
if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASSFILE" ]; then
    "$DIR/setup-signing.sh"
fi
PASS="$(cat "$PASSFILE" 2>/dev/null || true)"
if [ -n "$PASS" ] && security unlock-keychain -p "$PASS" "$KEYCHAIN" 2>/dev/null \
    && security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CN"; then
    codesign --force --keychain "$KEYCHAIN" -s "$CN" "$APP"
else
    echo "Внимание: подпись ad-hoc — после каждой пересборки доступ к кликам придётся выдавать заново."
    codesign --force -s - "$APP"
fi
echo "Готово: $APP (версия $VERSION)"
