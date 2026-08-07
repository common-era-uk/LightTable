#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -9 -f "LightTable.app/Contents/MacOS/LightTable" 2>&1 || true
./Packaging/build_app.sh
rm -rf /Applications/LightTable.app
cp -R LightTable.app /Applications/LightTable.app
xattr -dr com.apple.quarantine /Applications/LightTable.app 2>&1 || true
open /Applications/LightTable.app
