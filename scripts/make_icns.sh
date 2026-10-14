#!/usr/bin/env bash
set -euo pipefail

# scripts/make_icns.sh
# Generates AppIcon.icns from Brand/lumo-app-icon-1024.png using sips and iconutil

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_PNG="${ROOT_DIR}/Brand/lumo-app-icon-1024.png"

if [[ ! -f "$SOURCE_PNG" ]]; then
    SOURCE_PNG="${ROOT_DIR}/Sources/Resources/Brand/lumo-app-icon-1024.png"
fi

if [[ ! -f "$SOURCE_PNG" ]]; then
    echo "Error: Source image not found at ${SOURCE_PNG}"
    exit 1
fi

echo "Building AppIcon from ${SOURCE_PNG}..."

WORK_DIR="$(mktemp -d)"
ICONSET_DIR="${WORK_DIR}/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

sips -z 16 16     "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

mkdir -p "${ROOT_DIR}/Sources/Resources"
mkdir -p "${ROOT_DIR}/Brand"

iconutil -c icns "$ICONSET_DIR" -o "${ROOT_DIR}/Sources/Resources/AppIcon.icns"
cp "${ROOT_DIR}/Sources/Resources/AppIcon.icns" "${ROOT_DIR}/Brand/AppIcon.icns"

rm -rf "$WORK_DIR"
echo "Successfully generated AppIcon.icns at ${ROOT_DIR}/Sources/Resources/AppIcon.icns and ${ROOT_DIR}/Brand/AppIcon.icns"
