#!/usr/bin/env bash
# Builds DeskPet.app from the Swift package. Works with only the Xcode
# Command Line Tools installed (no Xcode.app / xcodebuild required).
#
#   scripts/build-app.sh            # release build -> build/DeskPet.app
#   scripts/build-app.sh debug      # debug build
#
# Licensing (Dodo Payments):
#   DESKPET_DODO_ENV   test_mode (default) or live_mode — which keys the app accepts
#   DESKPET_BUY_URL    where "Buy DeskPet" goes (default https://deskpet.app)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DeskPet.app"
VERSION="2.3.0"
DODO_ENV="${DESKPET_DODO_ENV:-test_mode}"
BUY_URL="${DESKPET_BUY_URL:-https://deskpet.app}"
[[ "$DODO_ENV" == "test_mode" || "$DODO_ENV" == "live_mode" ]] || { echo "DESKPET_DODO_ENV must be test_mode or live_mode" >&2; exit 1; }
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
    <key>DPDodoEnvironment</key>            <string>$DODO_ENV</string>
    <key>DPBuyURL</key>                     <string>$BUY_URL</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>DeskPet uses the microphone only while you hold or tap the talk button (or the push-to-talk shortcut), so you can talk to your pet instead of typing. It never listens in the background, and DeskPet doesn’t save recordings.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>DeskPet turns what you say into text so your pet can understand it and reply. By default this happens entirely on your Mac. Only if you turn off “Keep speech recognition on this Mac” in Settings › Voice may Apple’s speech service process it instead.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP  (licenses: $DODO_ENV)"
echo "    Run it with:  open \"$APP\""
