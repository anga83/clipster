#!/bin/bash

# Clipster Release Build Script
# Version 1.5 - 13.07.2025

set -e

echo "🚀 Building Clipster Release v1.5..."

# Clean any previous builds
echo "🧹 Cleaning previous builds..."
swift package clean

# Build for release
echo "🔨 Building release version..."
swift build -c release

# Create Release directory
RELEASE_DIR="Release"
APP_NAME="Clipster.app"
DMG_NAME="Clipster-v1.6.dmg"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$RELEASE_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$RELEASE_DIR/$APP_NAME/Contents/Resources"

# Copy executable
cp .build/release/Clipster "$RELEASE_DIR/$APP_NAME/Contents/MacOS/"

# Copy Info.plist
cp Sources/Clipster/Resources/Info.plist "$RELEASE_DIR/$APP_NAME/Contents/"

# Copy app icons
echo "🎨 Copying app icons..."
mkdir -p "$RELEASE_DIR/$APP_NAME/Contents/Resources/AppIcon.xcassets"
cp -r Sources/Clipster/Resources/AppIcon.xcassets/* "$RELEASE_DIR/$APP_NAME/Contents/Resources/AppIcon.xcassets/"

# Copy the known-good icon directly
echo "🖼️ Copying AppIcon.icns..."
if [ ! -f "AppIcon.icns" ]; then
    echo "❌ AppIcon.icns not found in project root"
    exit 1
fi
cp "AppIcon.icns" "$RELEASE_DIR/$APP_NAME/Contents/Resources/AppIcon.icns"

# Make executable... executable
chmod +x "$RELEASE_DIR/$APP_NAME/Contents/MacOS/Clipster"

echo "✅ App bundle created at: $RELEASE_DIR/$APP_NAME"

# Create DMG
echo "💾 Creating DMG..."
rm -f "$RELEASE_DIR/$DMG_NAME"

# Create temporary DMG directory
DMG_DIR="$RELEASE_DIR/dmg_temp"
mkdir -p "$DMG_DIR"

# Copy app to DMG directory
cp -r "$RELEASE_DIR/$APP_NAME" "$DMG_DIR/"

# Create a link to Applications folder
ln -s /Applications "$DMG_DIR/Applications"

# Create the DMG
hdiutil create -volname "Clipster v1.4.1" -srcfolder "$DMG_DIR" -ov -format UDZO "$RELEASE_DIR/$DMG_NAME"

# Clean up temporary directory
rm -rf "$DMG_DIR"

echo "🎉 Release build complete!"
echo "📱 App: $RELEASE_DIR/$APP_NAME"
echo "💿 DMG: $RELEASE_DIR/$DMG_NAME"

# Show file sizes
echo ""
echo "📊 File sizes:"
du -h "$RELEASE_DIR/$APP_NAME"
du -h "$RELEASE_DIR/$DMG_NAME"

echo ""
echo "✨ Clipster v1.4.1 is ready for distribution!"
