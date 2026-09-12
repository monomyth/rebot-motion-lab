#!/bin/bash
# Pack the current Debug binaries into a .app so macOS shows the real Dock icon.
# Does not do a universal release build. Re-run after `swift-local.sh build`.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEBUG="${PROJECT_ROOT}/.build/out/Products/Debug"
APP="${1:-$PROJECT_ROOT/dist/ReBot Motion Lab Grok.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
test -x "$DEBUG/ReBotMotionLab" && test -x "$DEBUG/ReBotMCP"

cp "$DEBUG/ReBotMotionLab" "$DEBUG/ReBotMCP" "$APP/Contents/MacOS/"
chmod +x "$APP/Contents/MacOS/ReBotMotionLab" "$APP/Contents/MacOS/ReBotMCP"
ditto "$PROJECT_ROOT/Sources/RobotCore/Resources" "$APP/Contents/Resources/RobotResources"
cp "$PROJECT_ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.rebot.motionlab.grok" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleName ReBot Motion Lab Grok" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ReBot Motion Lab Grok" "$APP/Contents/Info.plist" >/dev/null

if [ ! -f "$PROJECT_ROOT/.build/AppIcon.icns" ]; then
    mkdir -p "$PROJECT_ROOT/.build"
    xcrun swift "$PROJECT_ROOT/scripts/make-icon.swift" "$PROJECT_ROOT/.build/AppIcon.iconset"
    iconutil -c icns "$PROJECT_ROOT/.build/AppIcon.iconset" -o "$PROJECT_ROOT/.build/AppIcon.icns"
fi
cp "$PROJECT_ROOT/.build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/MacOS/ReBotMCP" >/dev/null
codesign --force --sign - "$APP" >/dev/null
printf 'Wrapped %s\n' "$APP"
printf 'Open with:  open "%s"\n' "$APP"
