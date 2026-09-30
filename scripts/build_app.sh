#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/SuperQ.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Building SuperQ for macOS ==="

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "--> Compiling Swift sources..."
xcrun swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    "$PROJECT_DIR/Sources/SuperQ/"*.swift \
    -o "$MACOS_DIR/SuperQ"

echo "--> Copying Info.plist..."
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "--> Copying AppIcon.icns..."
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

echo "--> Signing application bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "=== Build Complete! ==="
echo "Application created at: $APP_BUNDLE"
