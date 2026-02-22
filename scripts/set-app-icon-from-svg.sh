#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input.svg> [output.icns]"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_SVG="$1"
OUTPUT_ICNS="${2:-$ROOT_DIR/Sources/VoiceWidget/Resources/AppIcon.icns}"

if [[ ! -f "$INPUT_SVG" ]]; then
  echo "Input file not found: $INPUT_SVG"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
BASE_PNG="$TMP_DIR/base.png"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"

sips -s format png "$INPUT_SVG" --out "$BASE_PNG" >/dev/null

sips -z 16 16   "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64   "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "Generated app icon: $OUTPUT_ICNS"
