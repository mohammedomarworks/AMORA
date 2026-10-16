#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

CONFIGURATION="${1:-debug}"

echo "🔨 Building AMORA ($CONFIGURATION)..."
if [ "$CONFIGURATION" = "release" ]; then
    swift build -c release
    swift build -c release --product AMORA-BrowserHost
    BINARY_PATH=".build/release/AMORA"
    BROWSER_HOST_PATH=".build/release/AMORA-BrowserHost"
else
    swift build
    swift build --product AMORA-BrowserHost
    BINARY_PATH=".build/debug/AMORA"
    BROWSER_HOST_PATH=".build/debug/AMORA-BrowserHost"
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
cp "$BROWSER_HOST_PATH" "$RESOURCES_DIR/AMORA-BrowserHost"
chmod +x "$RESOURCES_DIR/AMORA-BrowserHost"
cp -R "BrowserExtensions" "$RESOURCES_DIR/BrowserExtensions"

FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

LLAMA_FRAMEWORK_PATH="$(find .build -name "llama.framework" | grep "macos" | head -1)"
if [ -n "$LLAMA_FRAMEWORK_PATH" ] && [ -d "$LLAMA_FRAMEWORK_PATH" ]; then
    echo "📦 Bundling llama.framework into $FRAMEWORKS_DIR..."
    cp -R "$LLAMA_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/AMORA" 2>/dev/null || true
    if [ -d ".build/index-build/arm64-apple-macosx/debug" ]; then
        ln -sf "$DIR/$LLAMA_FRAMEWORK_PATH" ".build/index-build/arm64-apple-macosx/debug/llama.framework" 2>/dev/null || true
    fi
fi

echo "🔌 Registering Chrome native messaging host..."
"$DIR/Scripts/install-chrome-native-host.sh" "$DIR/$RESOURCES_DIR/AMORA-BrowserHost"

VERSION_FILE="$DIR/VERSION"
APP_VERSION="1.0.0"
BUILD_NUMBER="1"

if [ -f "$VERSION_FILE" ]; then
    FILE_VERSION="$(grep '^VERSION=' "$VERSION_FILE" | cut -d '=' -f2 | tr -d '[:space:]')"
    FILE_BUILD="$(grep '^BUILD=' "$VERSION_FILE" | cut -d '=' -f2 | tr -d '[:space:]')"
    if [ -n "$FILE_VERSION" ]; then
        APP_VERSION="$FILE_VERSION"
    fi
    if [ -n "$FILE_BUILD" ]; then
        BUILD_NUMBER="$FILE_BUILD"
    fi
    cp "$VERSION_FILE" "$RESOURCES_DIR/VERSION"
fi

echo "🏷️  Packaging AMORA v$APP_VERSION (Build $BUILD_NUMBER)..."

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
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
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
    <key>NSAppleEventsUsageDescription</key>
    <string>AMORA uses Apple Events to control playback in Apple Music and Spotify.</string>
</dict>
</plist>
EOF

DEVELOPER_ID="${DEVELOPER_ID:-}"
if [ -n "$DEVELOPER_ID" ] && [ "$DEVELOPER_ID" != "-" ]; then
    echo "🔏 Code signing with Developer ID: $DEVELOPER_ID..."
    SIGN_FLAGS=(--force --timestamp --options runtime --sign "$DEVELOPER_ID")
else
    echo "🔏 Ad-hoc code signing $APP_BUNDLE..."
    SIGN_FLAGS=(--force --sign "-")
fi

ENTITLEMENTS="${ENTITLEMENTS:-}"
APP_SIGN_FLAGS=("${SIGN_FLAGS[@]}")
if [ -n "$ENTITLEMENTS" ] && [ -f "$ENTITLEMENTS" ]; then
    echo "📄 Applying entitlements: $ENTITLEMENTS..."
    APP_SIGN_FLAGS+=(--entitlements "$ENTITLEMENTS")
fi

# Sign nested components inside-out before signing the main bundle
if [ -d "$FRAMEWORKS_DIR/llama.framework" ]; then
    echo "  Signing $FRAMEWORKS_DIR/llama.framework..."
    codesign "${SIGN_FLAGS[@]}" "$FRAMEWORKS_DIR/llama.framework"
fi

if [ -f "$RESOURCES_DIR/AMORA-BrowserHost" ]; then
    echo "  Signing $RESOURCES_DIR/AMORA-BrowserHost..."
    codesign "${SIGN_FLAGS[@]}" "$RESOURCES_DIR/AMORA-BrowserHost"
fi

echo "  Signing $APP_BUNDLE..."
codesign "${APP_SIGN_FLAGS[@]}" "$APP_BUNDLE"

echo "🔍 Validating bundle signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "✅ AMORA.app built successfully at $DIR/$APP_BUNDLE"
