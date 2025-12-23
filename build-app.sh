#!/bin/bash

# Build OptTab as .app bundle for Homebrew cask

set -e

APP_NAME="OptTab"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME for release..."

# Clean previous build
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Build release binary
swift build -c release

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy app icon
ICON_PATH="OptTab/Resources/AppIcon.icns"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "✅ App icon copied"
else
    echo "⚠️  Warning: AppIcon.icns not found at $ICON_PATH"
    echo "   Run: iconutil -c icns OptTab/Resources/AppIcon.iconset"
fi

# Copy PNG icons for menu bar
if [ -f "OptTab/Resources/MenuBarIcon.png" ]; then
    cp "OptTab/Resources/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png"
    echo "✅ Menu bar icon copied"
fi

if [ -f "OptTab/Resources/AppIcon.png" ]; then
    cp "OptTab/Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
    echo "✅ App icon PNG copied"
fi

# Copy Info.plist
INFO_PLIST_PATH="OptTab/Resources/Info.plist"
if [ -f "$INFO_PLIST_PATH" ]; then
    cp "$INFO_PLIST_PATH" "$APP_BUNDLE/Contents/Info.plist"
    echo "✅ Info.plist copied"
else
    echo "❌ Error: Info.plist not found at $INFO_PLIST_PATH"
    exit 1
fi

# Make binary executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Code sign the app with entitlements
echo "🔏 Signing app..."
ENTITLEMENTS_PATH="OptTab/Resources/OptTab.entitlements"
if [ -f "$ENTITLEMENTS_PATH" ]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_BUNDLE"
    echo "✅ App signed with entitlements"
else
    # Sign without entitlements as fallback
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "✅ App signed (no entitlements)"
fi

# Verify signature
echo "🔍 Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE"
if [ $? -eq 0 ]; then
    echo "✅ Signature verified"
else
    echo "⚠️  Warning: Signature verification failed"
fi

# Create DMG
echo "📦 Creating DMG..."
DMG_NAME="$APP_NAME-1.0.0.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$RELEASE_DIR/$DMG_NAME"

echo "✅ Build complete!"
echo "   App: $APP_BUNDLE"
echo "   DMG: $RELEASE_DIR/$DMG_NAME"
echo ""
echo "To install manually:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "To create Homebrew cask:"
echo "  shasum -a 256 $RELEASE_DIR/$DMG_NAME"
