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

# Copy app icon if exists
if [ -f "OptTab/Resources/AppIcon.icns" ]; then
    cp "OptTab/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "   → App icon copied"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.rajebdev.opttab</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Make binary executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

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
