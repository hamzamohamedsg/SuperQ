#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/SuperQ.app"
TMP_DMG="$BUILD_DIR/SuperQ_rw.dmg"
FINAL_DMG="$PROJECT_DIR/SuperQ.dmg"
VOL_NAME="SuperQ"

echo "=== Building Customized SuperQ DMG ==="

# 1. Ensure SuperQ.app exists
if [ ! -d "$APP_BUNDLE" ]; then
    "$PROJECT_DIR/scripts/build_app.sh"
fi

# 2. Generate PNG background & convert to .background.tiff
echo "--> Generating background..."
xcrun swift "$PROJECT_DIR/scripts/generate_dmg_background.swift"
sips -s format tiff "$PROJECT_DIR/Resources/dmg_background.png" --out "$PROJECT_DIR/Resources/.background.tiff" >/dev/null

# 3. Clean up any existing mount points
echo "--> Cleaning previous mounts..."
hdiutil detach "/Volumes/$VOL_NAME" -force 2>/dev/null || true
rm -rf "$TMP_DMG" "$FINAL_DMG"

# 4. Create empty RW disk image (60MB to give plenty of room for files and DS_Store)
echo "--> Creating empty disk image..."
hdiutil create -size 60m -volname "$VOL_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" "$TMP_DMG"

# 5. Mount RW image
echo "--> Mounting disk image..."
DEV_NAME=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | grep '^/dev/' | head -n 1 | awk '{print $1}')
MOUNT_DIR="/Volumes/$VOL_NAME"
echo "Mounted: $DEV_NAME at $MOUNT_DIR"

# Wait for Finder/System to register mount
sleep 2

# 6. Copy App, symlink, background, and icon
echo "--> Copying files to volume..."
cp -R "$APP_BUNDLE" "$MOUNT_DIR/SuperQ.app"
ln -s /Applications "$MOUNT_DIR/Applications"
cp "$PROJECT_DIR/Resources/.background.tiff" "$MOUNT_DIR/.background.tiff"
SetFile -a V "$MOUNT_DIR/.background.tiff" 2>/dev/null || true

if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# 7. Apply AppleScript formatting to Finder window
echo "--> Applying Finder layout and background picture..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 1
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set pathbar visible of theWindow to false
        
        -- Window bounds: {left, top, right, bottom} -> 540x360 size
        set the bounds of theWindow to {300, 200, 840, 560}
        
        set theOptions to the icon view options of theWindow
        set arrangement of theOptions to not arranged
        set icon size of theOptions to 100
        set text size of theOptions to 12
        set background picture of theOptions to file ".background.tiff"
        
        -- Position items
        set position of item "SuperQ.app" of theWindow to {130, 185}
        set position of item "Applications" of theWindow to {410, 185}
        
        update without registering applications
        delay 2
        close
        delay 1
        open
        delay 2
    end tell
end tell
APPLESCRIPT

# 8. Hide invisible files and finalize permissions
echo "--> Checking generated .DS_Store..."
ls -lh "$MOUNT_DIR/.DS_Store"

echo "--> Finalizing volume..."
sync
sleep 3

# Eject volume
echo "--> Detaching volume..."
hdiutil detach "$DEV_NAME" -force

# 9. Convert to compressed, read-only DMG
echo "--> Compressing to final DMG..."
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$TMP_DMG"

# Copy to Desktop as well
cp "$FINAL_DMG" /Users/mmtechstore/Desktop/SuperQ.dmg

echo "=== Complete! ==="
echo "Final DMG created at: $FINAL_DMG"
ls -lh "$FINAL_DMG"
