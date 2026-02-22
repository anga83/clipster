# Clipster Build Scripts

This directory contains automated build scripts for the Clipster project.

## Scripts

### 🚀 `release.sh` - Release Build Script

Creates a complete release build with DMG installer.

**Usage:**
```bash
./Scripts/release.sh
```

**What it does:**
1. Prompts for new version and build number
2. Updates Info.plist with new version info
3. Cleans previous builds
4. Builds the app in release mode
5. Creates proper app bundle structure
6. Generates app icon (if possible)
7. Creates a DMG installer with Applications symlink
8. Shows summary of created files

**Output:**
- `Clipster.app` - Ready-to-use app bundle
- `Clipster-vX.X.dmg` - DMG installer for distribution

### 🔧 `dev.sh` - Development Build Script

Quick build script for development and testing.

**Usage:**
```bash
# Build only
./Scripts/dev.sh build

# Build and run
./Scripts/dev.sh run

# Clean build directory
./Scripts/dev.sh clean
```

**Options:**
- `build` - Build the app for development (default)
- `run` - Build and run the app immediately
- `clean` - Clean all build artifacts

## Requirements

- macOS 13.0 or later
- Xcode Command Line Tools
- Swift 5.9 or later

## Release Process

For creating a new release:

1. Make sure all changes are committed
2. Run the release script: `./Scripts/release.sh`
3. Enter the new version number and build number
4. Wait for the build to complete
5. Test the generated DMG
6. Distribute the DMG file

## Development Workflow

For daily development:

1. Use `./Scripts/dev.sh run` to quickly test changes
2. Use `./Scripts/dev.sh clean` if you encounter build issues
3. Use the release script only when creating official releases

## Notes

- The release script automatically handles all Info.plist updates
- Icons are generated automatically if `iconutil` is available
- The DMG includes an Applications symlink for easy installation
- All scripts include error checking and colored output for better UX
