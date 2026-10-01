#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

CONFIGURATION="${1:-debug}"

echo "🔨 Building AMORA ($CONFIGURATION)..."
if [ "$CONFIGURATION" = "release" ]; then
    swift build -c release
    BINARY_PATH=".build/release/AMORA"
else
    swift build
    BINARY_PATH=".build/debug/AMORA"
fi

APP_BUNDLE="AMORA.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating $APP_BUNDLE bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/AMORA"
chmod +x "$MACOS_DIR/AMORA"

cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AMORA</string>
    <key>CFBundleIdentifier</key>
    <string>com.amora.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AMORA</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrefersDisplaySafeAreaCompatibilityMode</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "🔏 Ad-hoc code signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✅ AMORA.app built successfully at $DIR/$APP_BUNDLE"
