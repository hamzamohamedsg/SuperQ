#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/SuperQ.app"
STAGING_DIR="$BUILD_DIR/dmg_staging"
TMP_DMG="$BUILD_DIR/SuperQ_rw.dmg"
FINAL_DMG="$PROJECT_DIR/SuperQ.dmg"
VOL_NAME="SuperQ"

echo "=== Creating SuperQ Installer (.dmg) ==="

# 1. Build app if needed
if [ ! -d "$APP_BUNDLE" ]; then
    echo "--> Building SuperQ.app..."
    "$PROJECT_DIR/scripts/build_app.sh"
fi

# 2. Generate DMG background if missing
if [ ! -f "$PROJECT_DIR/Resources/dmg_background.png" ]; then
    echo "--> Generating background image..."
    xcrun swift "$PROJECT_DIR/scripts/generate_dmg_background.swift"
fi

# 3. Clean up existing staging and temp files
echo "--> Preparing staging folder..."
rm -rf "$STAGING_DIR" "$TMP_DMG"
mkdir -p "$STAGING_DIR"

# Copy App
cp -R "$APP_BUNDLE" "$STAGING_DIR/SuperQ.app"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"

# Add background image
mkdir -p "$STAGING_DIR/.background"
cp "$PROJECT_DIR/Resources/dmg_background.png" "$STAGING_DIR/.background/background.png"

# Add volume icon
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi

# 4. Create temporary read-write disk image directly from staging folder
echo "--> Creating temporary disk image..."
hdiutil create \
    -ov \
    -srcfolder "$STAGING_DIR" \
    -volname "$VOL_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    "$TMP_DMG"

# 5. Mount temporary disk image
echo "--> Mounting disk image..."
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
DEVICE=$(echo "$MOUNT_OUTPUT" | grep '^/dev/' | head -n 1 | awk '{print $1}')
MOUNT_DIR="/Volumes/$VOL_NAME"

echo "Mounted at: $MOUNT_DIR ($DEVICE)"

if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# 7. Customize Finder window layout via AppleScript
echo "--> Configuring Finder layout and icon positions..."
osascript <<EOF || true
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 200, 840, 560}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 96
        set arrangement of viewOptions to not arranged
        set background picture of viewOptions to file ".background:background.png"
        set position of item "SuperQ.app" of container window to {140, 185}
        set position of item "Applications" of container window to {400, 185}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

# 8. Unmount volume
echo "--> Finalizing and unmounting..."
sync
sleep 1
hdiutil detach "$DEVICE" -force || hdiutil detach "$MOUNT_DIR" -force

# 9. Convert to final read-only, compressed DMG
echo "--> Compressing final DMG..."
rm -f "$FINAL_DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"

# Clean up temporary files
rm -rf "$STAGING_DIR" "$TMP_DMG"

echo "=== DMG Build Complete! ==="
echo "Installer created at: $FINAL_DMG"
ls -lh "$FINAL_DMG"
