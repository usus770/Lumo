#!/usr/bin/env bash
set -euo pipefail

# scripts/make_dmg.sh
# Creates an installable Lumo-1.0.0.dmg with Lumo.app and an /Applications symlink.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_PATH="$REPO_ROOT/build/Lumo.app"
DMG_PATH="$REPO_ROOT/build/Lumo-1.0.0.dmg"
STAGING_DIR="$REPO_ROOT/build/dmg_staging"

# 1. Ensure Lumo.app is built
if [ ! -d "$APP_PATH" ]; then
    echo "==> Lumo.app not found. Running build_app.sh..."
    bash "$REPO_ROOT/scripts/build_app.sh"
fi

echo "==> [1/3] Preparing DMG staging folder at $STAGING_DIR..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "==> [2/3] Copying Lumo.app and creating Applications shortcut..."
cp -R "$APP_PATH" "$STAGING_DIR/Lumo.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> [3/3] Creating DMG via hdiutil..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Lumo" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "✅ DMG created successfully at: $DMG_PATH"
ls -lh "$DMG_PATH"
