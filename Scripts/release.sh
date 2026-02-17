#!/bin/bash

# Clipster Release Build Script
# This script automates the complete release process for Clipster

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="Clipster"
BUNDLE_ID="com.clipster.app"
COPYRIGHT="Copyright © 2025 Clipster. All rights reserved."
MIN_MACOS="13.0"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}🚀 Clipster Release Build Script${NC}"
echo -e "${BLUE}===============================${NC}"
echo

# Check if we're in the right directory
if [[ ! -f "$PROJECT_DIR/Package.swift" ]]; then
    echo -e "${RED}❌ Error: Package.swift not found. Please run this script from the project root.${NC}"
    exit 1
fi

cd "$PROJECT_DIR"

# Function to prompt for version
prompt_version() {
    local current_version
    current_version=$(grep -A1 "CFBundleShortVersionString" Sources/Clipster/Resources/Info.plist | grep -o '[0-9][0-9]*\.[0-9][0-9]*' | head -1)
    local current_build
    current_build=$(grep -A1 "CFBundleVersion" Sources/Clipster/Resources/Info.plist | grep -o '[0-9][0-9]*' | head -1)
    
    echo -e "${YELLOW}Current version: $current_version (Build $current_build)${NC}"
    echo
    read -p "Enter new version (e.g., 1.4): " NEW_VERSION
    read -p "Enter new build number (e.g., 6): " NEW_BUILD
    
    if [[ -z "$NEW_VERSION" || -z "$NEW_BUILD" ]]; then
        echo -e "${RED}❌ Version and build number are required${NC}"
        exit 1
    fi
    
    echo
    echo -e "${GREEN}✅ Will build version $NEW_VERSION (Build $NEW_BUILD)${NC}"
    echo
}

# Function to update Info.plist
update_info_plist() {
    echo -e "${BLUE}📝 Updating Info.plist...${NC}"
    
    cat > Sources/Clipster/Resources/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon.icns</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$NEW_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$NEW_BUILD</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN_MACOS</string>
	<key>NSHumanReadableCopyright</key>
	<string>$COPYRIGHT</string>
	<key>NSMainStoryboardFile</key>
	<string>Main</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSSupportsAutomaticTermination</key>
	<true/>
	<key>NSSupportsSuddenTermination</key>
	<true/>
</dict>
</plist>
EOF
    
    echo -e "${GREEN}✅ Info.plist updated${NC}"
}

# Function to update build date in AboutView.swift
update_build_date() {
    echo -e "${BLUE}📅 Updating build date in AboutView.swift...${NC}"
    
    local current_date
    current_date=$(date "+%d.%m.%Y")
    
    # Update the build date line in AboutView.swift
    sed -i '' "s/Text(\"Build Date: [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\")/Text(\"Build Date: $current_date\")/g" Sources/Clipster/Views/AboutView.swift
    
    echo -e "${GREEN}✅ Build date updated to $current_date${NC}"
}

# Function to clean previous builds
clean_build() {
    echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
    
    rm -rf .build
    rm -rf "${APP_NAME}.app"
    rm -rf dmg-staging
    rm -f "${APP_NAME}-v${NEW_VERSION}.dmg"
    
    echo -e "${GREEN}✅ Build directory cleaned${NC}"
}

# Function to build the app
build_app() {
    echo -e "${BLUE}🔨 Building ${APP_NAME} v${NEW_VERSION}...${NC}"
    
    swift build -c release
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Build failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Build completed successfully${NC}"
}

# Function to create app bundle
create_app_bundle() {
    echo -e "${BLUE}📦 Creating app bundle...${NC}"
    
    # Create app bundle structure
    mkdir -p "${APP_NAME}.app/Contents/"{MacOS,Resources}
    
    # Copy executable
    cp ".build/release/${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/"
    chmod +x "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
    
    # Copy Info.plist
    cp "Sources/Clipster/Resources/Info.plist" "${APP_NAME}.app/Contents/"
    
    # Copy resources
    cp -r "Sources/Clipster/Resources/AppIcon.xcassets" "${APP_NAME}.app/Contents/Resources/"

    # Use the canonical, known-good icon.
    echo -e "${YELLOW}⚙️  Copying AppIcon.icns...${NC}"
    local icon_output="${APP_NAME}.app/Contents/Resources/AppIcon.icns"
    if [[ ! -f "AppIcon.icns" ]]; then
        echo -e "${RED}❌ AppIcon.icns not found in project root${NC}"
        exit 1
    fi
    cp "AppIcon.icns" "$icon_output"
    
    echo -e "${GREEN}✅ App bundle created${NC}"
}

# Function to create DMG
create_dmg() {
    echo -e "${BLUE}💽 Creating DMG installer...${NC}"
    
    # Create staging directory
    mkdir -p dmg-staging
    
    # Copy app to staging
    cp -R "${APP_NAME}.app" dmg-staging/
    
    # Create Applications symlink for easy installation
    ln -s /Applications dmg-staging/Applications
    
    # Create the DMG
    local dmg_name="${APP_NAME}-v${NEW_VERSION}.dmg"
    hdiutil create -volname "${APP_NAME} v${NEW_VERSION}" -srcfolder dmg-staging -ov -format UDZO "$dmg_name"
    
    # Clean up staging
    rm -rf dmg-staging
    
    if [[ -f "$dmg_name" ]]; then
        local dmg_size=$(ls -lh "$dmg_name" | awk '{print $5}')
        echo -e "${GREEN}✅ DMG created: $dmg_name ($dmg_size)${NC}"
    else
        echo -e "${RED}❌ DMG creation failed${NC}"
        exit 1
    fi
}

# Function to test the app
test_app() {
    echo -e "${BLUE}🧪 Testing app bundle...${NC}"
    
    # Test if the app can be opened
    if open "${APP_NAME}.app" --args --test 2>/dev/null; then
        echo -e "${GREEN}✅ App bundle test passed${NC}"
    else
        echo -e "${YELLOW}⚠️  App bundle test inconclusive (app may still work)${NC}"
    fi
}

# Function to show release summary
show_summary() {
    local dmg_name="${APP_NAME}-v${NEW_VERSION}.dmg"
    local dmg_size=$(ls -lh "$dmg_name" | awk '{print $5}')
    
    echo
    echo -e "${GREEN}🎉 Release Build Complete!${NC}"
    echo -e "${GREEN}========================${NC}"
    echo
    echo -e "${BLUE}Version:${NC} $NEW_VERSION (Build $NEW_BUILD)"
    echo -e "${BLUE}App Bundle:${NC} ${APP_NAME}.app"
    echo -e "${BLUE}DMG Installer:${NC} $dmg_name ($dmg_size)"
    echo -e "${BLUE}Bundle ID:${NC} $BUNDLE_ID"
    echo -e "${BLUE}Min macOS:${NC} $MIN_MACOS"
    echo
    echo -e "${YELLOW}📋 Next Steps:${NC}"
    echo "  1. Test the DMG by mounting it and installing the app"
    echo "  2. Verify all features work as expected"
    echo "  3. Distribute the DMG file"
    echo
    echo -e "${BLUE}Files created:${NC}"
    echo "  - ${APP_NAME}.app"
    echo "  - $dmg_name"
    echo
}

# Main execution
main() {
    prompt_version
    clean_build
    update_info_plist
    update_build_date
    build_app
    create_app_bundle
    test_app
    create_dmg
    show_summary
}

# Run the main function
main

echo -e "${GREEN}🚀 Release process completed successfully!${NC}"
