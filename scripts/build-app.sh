#!/usr/bin/env bash
# Builds DeskPet.app from the Swift package. Works with only the Xcode
# Command Line Tools installed (no Xcode.app / xcodebuild required).
#
#   scripts/build-app.sh            # release build -> build/DeskPet.app
#   scripts/build-app.sh debug      # debug build
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DeskPet.app"
VERSION="1.0.0"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

cd "$ROOT"
echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG" --product DeskPet
BIN="$(swift build -c "$CONFIG" --show-bin-path)/DeskPet"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeskPet"

echo "==> Rendering app icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>DeskPet</string>
    <key>CFBundleDisplayName</key>          <string>DeskPet</string>
    <key>CFBundleIdentifier</key>           <string>app.deskpet.DeskPet</string>
    <key>CFBundleExecutable</key>           <string>DeskPet</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$BUILD_NUMBER</string>
    <key>CFBundleDevelopmentRegion</key>    <string>en</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.entertainment</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>DeskPet</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
echo "    Run it with:  open \"$APP\""
