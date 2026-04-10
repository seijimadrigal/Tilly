#!/bin/bash
set -e

APP_NAME="Tilly"
SCHEME="Tilly"
PROJECT="Tilly.xcodeproj"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
DMG_PATH="build/${APP_NAME}.dmg"
TEAM_ID="YZFVX59ZM2"

echo "🔨 Step 1: Clean"
rm -rf build/
mkdir -p build

echo "📦 Step 2: Archive"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE="Automatic" \
  -allowProvisioningUpdates \
  2>&1 | tail -5

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "❌ Archive failed"
  exit 1
fi
echo "✅ Archive created"

echo "📤 Step 3: Export with Developer ID (Xcode manages signing)"
cat > build/ExportOptions.plist << EXPORTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EXPORTEOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  2>&1 | tail -5

APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
  echo "⚠️  Developer ID export failed. Trying direct copy from archive..."
  APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
  if [ ! -d "$APP_PATH" ]; then
    APP_PATH="${ARCHIVE_PATH}/Products/usr/local/bin/${APP_NAME}.app"
  fi
  if [ ! -d "$APP_PATH" ]; then
    echo "❌ Cannot find app in archive. Use Xcode: Product → Archive → Distribute App → Copy App"
    exit 1
  fi
  mkdir -p "$EXPORT_PATH"
  cp -R "$APP_PATH" "$EXPORT_PATH/"
  APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
  # Ad-hoc sign as fallback
  codesign --force --deep --sign - "$APP_PATH"
  echo "⚠️  App signed ad-hoc (not Developer ID). Users need: xattr -cr /Applications/Tilly.app"
fi

echo "✅ App ready: $APP_PATH"

echo "💿 Step 4: Create DMG"
mkdir -p "build/dmg_staging"
cp -R "$APP_PATH" "build/dmg_staging/"
ln -s /Applications "build/dmg_staging/Applications"

hdiutil create -volname "$APP_NAME" \
  -srcfolder "build/dmg_staging" \
  -ov -format UDZO \
  "$DMG_PATH" 2>&1 | tail -1

rm -rf "build/dmg_staging"

echo ""
echo "✅ Done!"
echo "   DMG: $DMG_PATH"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "📋 To share:"
echo "   Send build/Tilly.dmg to the other Mac"
echo "   If Gatekeeper blocks it, run on the other Mac:"
echo "   xattr -cr /Applications/Tilly.app"
