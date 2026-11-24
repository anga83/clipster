
#!/bin/bash
set -euo pipefail

ICON_FILE="${1:?Usage: $0 AppIcon.icon [AppIcon.icns]}"
OUTPUT_FILE="${2:-AppIcon.icns}"

ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$ICTOOL" ]]; then
    ICTOOL="$TOOL_DIR/icontool"
fi

if [[ ! -x "$ICTOOL" ]]; then
    echo "Error: ictool/icontool not found." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ICONSET="$TMP/AppIcon.iconset"
ART="$TMP/art.png"
MASTER="$TMP/master.png"

mkdir -p "$ICONSET" "$(dirname "$OUTPUT_FILE")"

# Render macOS Default appearance
"$ICTOOL" "$ICON_FILE" \
    --export-preview macOS Default 824 824 1 -45 "$ART"

# Restore transparent margins of the macOS icon
sips --padToHeightWidth 1024 1024 "$ART" \
    --out "$MASTER" >/dev/null

# Generate all required ICNS representations
make_icon() {
    sips -z "$2" "$2" "$MASTER" \
        --out "$ICONSET/$1" >/dev/null
}

make_icon icon_16x16.png          16
make_icon icon_16x16@2x.png       32
make_icon icon_32x32.png          32
make_icon icon_32x32@2x.png       64
make_icon icon_128x128.png       128
make_icon icon_128x128@2x.png    256
make_icon icon_256x256.png       256
make_icon icon_256x256@2x.png    512
make_icon icon_512x512.png       512
make_icon icon_512x512@2x.png   1024

# Compile ICNS
iconutil -c icns "$ICONSET" -o "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
