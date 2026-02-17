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
cp AppIcon.icns "$TARGET_ICNS"
echo "Copied AppIcon.icns to $TARGET_ICNS"
