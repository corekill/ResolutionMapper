#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Resolution Mapper"
PRODUCT="ResolutionMapper"
CONFIG="${CONFIG:-debug}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

/Library/Developer/CommandLineTools/usr/bin/swift-build \
  --disable-sandbox \
  --build-system native \
  --configuration "$CONFIG" \
  --triple arm64-apple-macosx14.0 \
  --product "$PRODUCT"

/Library/Developer/CommandLineTools/usr/bin/swift-build \
  --disable-sandbox \
  --build-system native \
  --configuration "$CONFIG" \
  --triple x86_64-apple-macosx14.0 \
  --product "$PRODUCT"

lipo -create \
  ".build/arm64-apple-macosx/$CONFIG/$PRODUCT" \
  ".build/x86_64-apple-macosx/$CONFIG/$PRODUCT" \
  -output "$APP/Contents/MacOS/$PRODUCT"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
codesign --force --sign - "$APP"
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"

ditto -c -k --noextattr --keepParent "$APP" "$DIST/$PRODUCT-v1.0-macos-universal.zip"

echo "$APP"
echo "$DIST/$PRODUCT-v1.0-macos-universal.zip"
