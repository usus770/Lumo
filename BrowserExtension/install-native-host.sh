#!/bin/bash
# install-native-host.sh - Install the native messaging host for Lumo browser extension

set -e

echo "🔧 Installing Lumo Native Messaging Host"

# Build the native host
echo "📦 Building LumoNativeHost..."
swift build --product LumoNativeHost -c release

NATIVE_HOST_PATH=".build/release/LumoNativeHost"
if [ ! -f "$NATIVE_HOST_PATH" ]; then
    echo "❌ Failed to build native host"
    exit 1
fi

echo "✅ Native host built at $NATIVE_HOST_PATH"

# Determine installation directory
if [ "$1" == "--user" ]; then
    INSTALL_DIR="$HOME/Applications"
    MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    mkdir -p "$MANIFEST_DIR"
else
    INSTALL_DIR="/Applications"
    MANIFEST_DIR="/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    # May need sudo for system-wide install
    SUDO="sudo"
fi

echo "📁 Installing to $INSTALL_DIR..."
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO cp ".build/release/LumoNativeHost" "$INSTALL_DIR/LumoNativeHost"
$SUDO chmod +x "$INSTALL_DIR/LumoNativeHost"

# Update manifest with correct path
MANIFEST_FILE="$MANIFEST_DIR/com.lumo.native.json"
echo "📝 Installing manifest to $MANIFEST_FILE..."
$SUDO mkdir -p "$(dirname "$MANIFEST_FILE")"

# Read template and replace path
cat > /tmp/com.lumo.native.json << EOF
{
  "name": "com.lumo.native",
  "description": "Lumo Native Messaging Host",
  "path": "$INSTALL_DIR/LumoNativeHost",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://YOUR_EXTENSION_ID/",
    "moz-extension://YOUR_EXTENSION_ID/"
  ]
}
EOF

$SUDO cp /tmp/com.lumo.native.json "$MANIFEST_FILE"

echo "✅ Native messaging host installed!"
echo ""
echo "📋 Next steps:"
echo "1. Build the browser extension: cd BrowserExtension && zip -r ../lumo-extension.zip ."
echo "2. Load the extension in Chrome (chrome://extensions/ -> Developer mode -> Load unpacked)"
echo "3. Note the Extension ID and update the manifest's allowed_origins"
echo "3. Re-run this script with the correct Extension ID"
echo ""
echo "To update the Extension ID in the manifest:"
echo "  sed -i '' 's/YOUR_EXTENSION_ID/<YOUR_EXTENSION_ID>/g' \"$MANIFEST_FILE\""