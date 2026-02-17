#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# The `sips` tool can be unreliable with SVG input. It's more robust to use a
# high-resolution PNG (e.g., 1024x1024) as the source.
if [ "$#" -ne 2 ]; then
    echo "Generates the required PNG icon set from a single high-resolution source image."
    echo "Usage: $0 <path_to_source_icon.png> <output_directory>"
    exit 1
fi

SOURCE_FILE="$1"
OUTPUT_DIR="$2"
ICON_NAME="icon"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "Generating icons from $SOURCE_FILE..."

# Generate all the required icon sizes using the built-in `sips` tool.
sips -z 16 16   "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_16x16.png"
sips -z 32 32   "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_16x16@2x.png"
sips -z 32 32   "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_32x32.png"
sips -z 64 64   "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_32x32@2x.png"
sips -z 128 128 "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_128x128.png"
sips -z 256 256 "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_128x128@2x.png"
sips -z 256 256 "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_256x256.png"
sips -z 512 512 "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_256x256@2x.png"
sips -z 512 512 "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_512x512.png"
sips -z 1024 1024 "$SOURCE_FILE" --out "$OUTPUT_DIR/${ICON_NAME}_512x512@2x.png"

echo "✅ Icons generated successfully in $OUTPUT_DIR"