#!/bin/bash
set -e

# Uses the known-good canonical app icon file.
# This mirrors the command used in the successful bundle build.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <target_icns_path>"
    echo "Example: $0 Release/Clipster-2.2/Clipster.app/Contents/Resources/AppIcon.icns"
    exit 1
fi

TARGET_ICNS="$1"
mkdir -p "$(dirname "$TARGET_ICNS")"
SOURCE_ICNS="Sources/Clipster/Resources/AppIcon.icns"
if [ ! -f "$SOURCE_ICNS" ]; then
    echo "Missing canonical icon at $SOURCE_ICNS"
    exit 1
fi
cp "$SOURCE_ICNS" "$TARGET_ICNS"

# Validate that the copied .icns can be parsed by iconutil.
VALIDATE_DIR="$(mktemp -d)"
if ! iconutil --convert iconset --output "$VALIDATE_DIR/validate.iconset" "$TARGET_ICNS" >/dev/null 2>&1; then
    echo "Validation failed: $TARGET_ICNS is not a readable .icns"
    rm -rf "$VALIDATE_DIR"
    exit 1
fi
rm -rf "$VALIDATE_DIR"

echo "Copied $SOURCE_ICNS to $TARGET_ICNS"
