#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_BUNDLE="LightTable.app"
SUBMISSION_ZIP="LightTable-notarize.zip"
KEYCHAIN_PROFILE="LightTable-Notary"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "error: $APP_BUNDLE not found — run Packaging/build_app.sh first" >&2
    exit 1
fi

rm -f "$SUBMISSION_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$SUBMISSION_ZIP"

echo "Submitting $APP_BUNDLE for notarization — this can take a few minutes..."
xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

xcrun stapler staple "$APP_BUNDLE"

rm -f "$SUBMISSION_ZIP"

echo "Notarized and stapled $APP_BUNDLE"
