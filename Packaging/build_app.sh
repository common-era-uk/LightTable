#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LightTable"
APP_BUNDLE="$APP_NAME.app"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "Packaging/Resources/LightTable.icns" "$APP_BUNDLE/Contents/Resources/LightTable.icns"
cp "CHANGELOG.md" "$APP_BUNDLE/Contents/Resources/CHANGELOG.md"

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
