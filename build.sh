#!/bin/bash
# Собирает build/BrowserPicker.app (нужны только Command Line Tools).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/build/BrowserPicker.app"
SOURCES=("$DIR/Config.swift" "$DIR/Browsers.swift" "$DIR/Picker.swift" "$DIR/SettingsView.swift" "$DIR/main.swift")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Компилирую..."
swiftc -O -target arm64-apple-macosx13.0 -framework Cocoa -framework SwiftUI -framework ServiceManagement \
    "${SOURCES[@]}" -o "$DIR/build/BrowserPicker-arm64"
swiftc -O -target x86_64-apple-macosx13.0 -framework Cocoa -framework SwiftUI -framework ServiceManagement \
    "${SOURCES[@]}" -o "$DIR/build/BrowserPicker-x86_64"
lipo -create "$DIR/build/BrowserPicker-arm64" "$DIR/build/BrowserPicker-x86_64" -output "$APP/Contents/MacOS/BrowserPicker"
rm -f "$DIR/build/BrowserPicker-arm64" "$DIR/build/BrowserPicker-x86_64"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
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

codesign --force -s - "$APP"
echo "Готово: $APP"
