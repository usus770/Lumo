#!/usr/bin/env bash
set -euo pipefail

# scripts/build_app.sh
# Builds Lumo in release mode, assembles a proper standalone Lumo.app bundle,
# copies resources and AppIcon.icns, and signs it ad-hoc.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> [1/5] Building Lumo in Release mode..."
swift build -c release

BIN_PATH="$REPO_ROOT/.build/release/Lumo"
if [ ! -f "$BIN_PATH" ]; then
    echo "ERROR: Release binary not found at $BIN_PATH" >&2
    exit 1
fi

APP_DIR="$REPO_ROOT/build/Lumo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> [2/5] Creating .app bundle structure at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> [3/5] Installing binary and Info.plist..."
cp "$BIN_PATH" "$MACOS_DIR/Lumo"
chmod +x "$MACOS_DIR/Lumo"

if [ -f "$REPO_ROOT/Info.plist" ]; then
    cp "$REPO_ROOT/Info.plist" "$CONTENTS_DIR/Info.plist"
else
    echo "ERROR: Info.plist not found" >&2
    exit 1
fi

echo "==> [4/5] Copying Brand AppIcon & Resources..."
# AppIcon
if [ -f "$REPO_ROOT/Sources/Resources/AppIcon.icns" ]; then
    cp "$REPO_ROOT/Sources/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$REPO_ROOT/Brand/AppIcon.icns" ]; then
    cp "$REPO_ROOT/Brand/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# SPM Resource Bundles (shaders, brand assets, etc.)
for bundle in "$REPO_ROOT/.build/release/"*.bundle; do
    if [ -d "$bundle" ]; then
        echo "    Copying resource bundle $(basename "$bundle")..."
        cp -R "$bundle" "$RESOURCES_DIR/"
    fi
done

# Copy Raw Brand Assets for in-bundle reference
if [ -d "$REPO_ROOT/Brand" ]; then
    mkdir -p "$RESOURCES_DIR/Brand"
    cp -R "$REPO_ROOT/Brand/"* "$RESOURCES_DIR/Brand/"
fi

# Optional ffmpeg / yt-dlp check
echo "==> Checking for local helper binaries (ffmpeg / yt-dlp)..."
if command -v ffmpeg >/dev/null 2>&1; then
    echo "    Notice: System ffmpeg detected at $(command -v ffmpeg)."
else
    echo "    Note: ffmpeg is not in PATH. Audio format conversions may require Homebrew: 'brew install ffmpeg'."
fi

echo "==> [5/5] Ad-hoc code signing Lumo.app..."
codesign --force --deep -s - "$APP_DIR"

echo "==> Verifying signature..."
codesign -vvv --deep --strict "$APP_DIR"

echo "✅ Successfully built and assembled Lumo.app at $APP_DIR"
