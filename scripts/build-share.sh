#!/bin/bash
set -e

# Quick build for sharing — no Developer ID needed
# Uses ad-hoc signing + disables library validation

APP_NAME="Tilly"
SCHEME="Tilly"
PROJECT="Tilly.xcodeproj"
BUILD_DIR="build/release"
DMG_PATH="build/${APP_NAME}.dmg"

echo "🔨 Step 1: Clean"
rm -rf build/
mkdir -p "$BUILD_DIR"

echo "📦 Step 2: Build Release"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "build/derived" \
  DEVELOPMENT_TEAM="YZFVX59ZM2" \
  CODE_SIGN_STYLE="Automatic" \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | tail -5

# Find the built app
APP_PATH=$(find build/derived -name "${APP_NAME}.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
  echo "❌ Build failed — app not found"
  exit 1
fi

echo "✅ Built: $APP_PATH"

# Copy to staging
cp -R "$APP_PATH" "$BUILD_DIR/"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"

echo "🔏 Step 3: Re-sign with ad-hoc signature"
# Strip existing signature and re-sign everything
codesign --force --deep --sign - "$APP_PATH"

# Also disable library validation so unsigned frameworks work
defaults write "$APP_PATH/Contents/Info.plist" CSAllowsUnsignedExecutableMemory -bool YES 2>/dev/null || true

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
echo "📋 On the other Mac:"
echo "   1. Open the DMG"
echo "   2. Drag Tilly to Applications"
echo "   3. In Terminal: xattr -cr /Applications/Tilly.app"
echo "   4. Double-click to open"
echo ""
echo "   The xattr command removes the quarantine flag so macOS"
echo "   doesn't block it. This is needed because the app isn't"
echo "   notarized (no Developer ID certificate)."
