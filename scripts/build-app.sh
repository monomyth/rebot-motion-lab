#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-$PROJECT_ROOT/dist}"
mkdir -p "$DESTINATION"
DESTINATION="$(cd "$DESTINATION" && pwd)"
APP="$DESTINATION/ReBot Motion Lab Codex.app"
cd "$PROJECT_ROOT"

# Compile each architecture independently; this also works with Command Line Tools.
bash scripts/swift-local.sh build --scratch-path .build/intel -c release --triple x86_64-apple-macosx14.0
bash scripts/swift-local.sh build --scratch-path .build/arm -c release --triple arm64-apple-macosx14.0
INTEL_BIN="$(bash scripts/swift-local.sh build --scratch-path .build/intel -c release --triple x86_64-apple-macosx14.0 --show-bin-path)"
ARM_BIN="$(bash scripts/swift-local.sh build --scratch-path .build/arm -c release --triple arm64-apple-macosx14.0 --show-bin-path)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$INTEL_BIN/ReBotMotionLab" "$ARM_BIN/ReBotMotionLab" -output "$APP/Contents/MacOS/ReBotMotionLab"
lipo -create "$INTEL_BIN/ReBotMCP" "$ARM_BIN/ReBotMCP" -output "$APP/Contents/MacOS/ReBotMCP"
chmod +x "$APP/Contents/MacOS/ReBotMotionLab"
chmod +x "$APP/Contents/MacOS/ReBotMCP"
ditto Sources/RobotCore/Resources "$APP/Contents/Resources/RobotResources"
cp LICENSE "$APP/Contents/Resources/APP-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [ ! -f .build/AppIcon.icns ]; then
    swift scripts/make-icon.swift .build/AppIcon.iconset
    iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/MacOS/ReBotMCP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
