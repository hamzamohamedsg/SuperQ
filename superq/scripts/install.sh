#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SOURCE="$PROJECT_DIR/build/SuperQ.app"
DEST_DIR="/Applications"

echo "=== Installing SuperQ ==="

if [ ! -d "$APP_SOURCE" ]; then
    echo "App bundle not found. Building now..."
    "$PROJECT_DIR/scripts/build_app.sh"
fi

killall SuperKill SuperQ 2>/dev/null || true
rm -rf "$DEST_DIR/SuperKill.app" "$DEST_DIR/SuperQ.app"

echo "--> Copying to $DEST_DIR/SuperQ.app..."
cp -R "$APP_SOURCE" "$DEST_DIR/SuperQ.app"

echo "--> Stripping quarantine attributes..."
xattr -cr "$DEST_DIR/SuperQ.app" 2>/dev/null || true

echo "--> Launching SuperQ..."
open "$DEST_DIR/SuperQ.app"

echo "=== Installation Complete! ==="
echo "SuperQ is running in your menu bar (clean 'Q' item)."
echo "Press ⇧⌘Q (Shift + Cmd + Q) anytime to force quit the active app."
