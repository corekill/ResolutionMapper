#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Resolution Mapper"
PRODUCT="ResolutionMapper"
CONFIG="${CONFIG:-debug}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG_NAME="$PRODUCT-v1.0-macos-universal"
DMG_STAGING="$DIST/dmg-staging"
DMG_BACKGROUND="$ROOT/Resources/DmgBackground.png"
RW_DMG="$DIST/$DMG_NAME-rw.dmg"
FINAL_DMG="$DIST/$DMG_NAME.dmg"

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

rm -rf "$DMG_STAGING" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$DMG_STAGING/.background"
ditto --noextattr "$APP" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp "$DMG_BACKGROUND" "$DMG_STAGING/.background/background.png"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDRW \
  "$RW_DMG"

MOUNT_DIR="$(hdiutil attach "$RW_DMG" -nobrowse -noverify -noautoopen | sed -n 's#^.*\(/Volumes/.*\)$#\1#p' | tail -n 1)"
if [[ -z "$MOUNT_DIR" ]]; then
  echo "Could not find mounted DMG path." >&2
  exit 1
fi
/usr/bin/SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {180, 120, 900, 560}
    set opts to icon view options of container window
    set icon size of opts to 96
    set arrangement of opts to not arranged
    set background picture of opts to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {180, 218}
    set position of item "Applications" of container window to {570, 218}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

xattr -cr "$MOUNT_DIR/$APP_NAME.app"
xattr -d com.apple.FinderInfo "$MOUNT_DIR/$APP_NAME.app" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$MOUNT_DIR/$APP_NAME.app" 2>/dev/null || true
codesign --verify --deep --strict "$MOUNT_DIR/$APP_NAME.app"

sync
for attempt in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT_DIR"; then
    break
  fi
  sleep "$attempt"
done
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
hdiutil verify "$FINAL_DMG"
rm -f "$RW_DMG"

echo "$APP"
echo "$FINAL_DMG"
