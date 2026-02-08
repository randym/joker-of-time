#!/usr/bin/env bash
# Rebuild JokerOfTime.icns from assets/JokerOfTime_1024.png
# Uses sips (macOS) to generate iconset sizes, then iconutil to create .icns
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS="$REPO_ROOT/assets"
SRC="$ASSETS/JokerOfTime_1024.png"
ICONSET="$ASSETS/JokerOfTime.iconset"
ICNS="$ASSETS/JokerOfTime.icns"

if [[ ! -f "$SRC" ]]; then
  echo "Source image not found: $SRC"
  exit 1
fi

echo "Creating iconset from $SRC"
mkdir -p "$ICONSET"

# Required sizes for macOS app icons (name -> pixel size)
# @2x means the file is 2x that logical size
sips -z 16 16   "$SRC" --out "$ICONSET/icon_16x16.png"
sips -z 32 32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32 32   "$SRC" --out "$ICONSET/icon_32x32.png"
sips -z 64 64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128 128 "$SRC" --out "$ICONSET/icon_128x128.png"
sips -z 256 256 "$SRC" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256 256 "$SRC" --out "$ICONSET/icon_256x256.png"
sips -z 512 512 "$SRC" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512 512 "$SRC" --out "$ICONSET/icon_512x512.png"
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

echo "Building $ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Done: $ICNS"
