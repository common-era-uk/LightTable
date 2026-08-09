#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

APP_BUNDLE="LightTable.app"
GH_REPO="common-era-uk/LightTable"
RELEASES_DIR="releases"
GENERATE_APPCAST="Packaging/sparkle-tools/generate_appcast"

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)
TAG="v$SHORT_VERSION"
ZIP_NAME="LightTable-$SHORT_VERSION.zip"

echo "Releasing $TAG..."

if [ ! -x "$GENERATE_APPCAST" ]; then
    echo "Sparkle tools missing, fetching..."
    SPARKLE_VERSION=$(gh release list --repo sparkle-project/Sparkle --limit 1 | cut -f3)
    TMP_DIR=$(mktemp -d)
    gh release download "$SPARKLE_VERSION" --repo sparkle-project/Sparkle --pattern "Sparkle-*.tar.xz" --dir "$TMP_DIR"
    tar -xJf "$TMP_DIR"/Sparkle-*.tar.xz -C "$TMP_DIR"
    mkdir -p Packaging/sparkle-tools
    cp "$TMP_DIR/bin/generate_keys" "$TMP_DIR/bin/generate_appcast" "$TMP_DIR/bin/sign_update" Packaging/sparkle-tools/
    rm -rf "$TMP_DIR"
fi

./Packaging/build_app.sh
./Packaging/notarize.sh

rm -rf "$RELEASES_DIR"
mkdir -p "$RELEASES_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASES_DIR/$ZIP_NAME"

# Pull this version's bullets out of CHANGELOG.md (everything between its
# "## x.y.z" heading and the next one) to use as the GitHub release notes.
NOTES_FILE=$(mktemp)
awk "/^## $SHORT_VERSION /{flag=1; next} /^## /{flag=0} flag" CHANGELOG.md > "$NOTES_FILE"

"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/$GH_REPO/releases/download/$TAG/" \
    -o appcast.xml \
    "$RELEASES_DIR"

if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$RELEASES_DIR/$ZIP_NAME" --repo "$GH_REPO" --clobber
else
    gh release create "$TAG" "$RELEASES_DIR/$ZIP_NAME" \
        --repo "$GH_REPO" \
        --title "$TAG" \
        --notes-file "$NOTES_FILE"
fi
rm -f "$NOTES_FILE"

git add appcast.xml
git commit -m "Publish $TAG appcast"
git push

echo "Released $TAG — appcast published, GitHub release created."
