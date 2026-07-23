#!/usr/bin/env bash
# Build Uninstaller.app from the SwiftPM binary and (optionally) install + launch it.
#
#   Scripts/make-app.sh            # build build/Uninstaller.app
#   Scripts/make-app.sh --install  # also copy to /Applications and open it
#
# Works with CommandLineTools (no full Xcode). Requires: swift, codesign, iconutil.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Uninstaller"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▸ Building release binary…"
swift build -c release --package-path "$ROOT" --product "$APP_NAME"
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "  (codesign skipped; app still runs locally)"

echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/$APP_NAME.app"
  echo "▸ Installing to ${DEST}…"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # Clear any quarantine so it opens without a Gatekeeper prompt.
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  echo "✓ Installed. Launching…"
  open "$DEST"
fi
