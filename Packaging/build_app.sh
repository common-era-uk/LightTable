#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LightTable"
APP_BUNDLE="$APP_NAME.app"
DEVELOPER_ID="Developer ID Application: KEVIN CLARK MOORE (98XWW6P8Q4)"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "Packaging/Resources/LightTable.icns" "$APP_BUNDLE/Contents/Resources/LightTable.icns"
cp "CHANGELOG.md" "$APP_BUNDLE/Contents/Resources/CHANGELOG.md"
cp -R ".build/release/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Sparkle's prebuilt framework only ships an ad-hoc placeholder signature —
# sign it (and everything nested inside it: Autoupdate, Updater.app, the XPC
# services) with our real identity before signing the outer app, since a
# nested component signed after its container would invalidate the seal.
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Hardened runtime + a secure timestamp are both required for notarization.
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_BUNDLE"

echo "Built and signed $APP_BUNDLE"
