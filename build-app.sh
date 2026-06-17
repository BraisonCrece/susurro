#!/bin/bash
set -euo pipefail

APP="Susurro"
BUNDLE_ID="com.local.susurro"
DEST="$APP.app"

echo "==> Building release binary"
swift build -c release

BIN=".build/release/$APP"
[ -f "$BIN" ] || { echo "Binary not found at $BIN"; exit 1; }

echo "==> Assembling $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/$APP"
cp Resources/Info.plist "$DEST/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$DEST/Contents/Resources/AppIcon.icns"

# Prefer a stable self-signed identity named "Susurro" so TCC grants survive rebuilds.
# Falls back to ad-hoc (-) if that identity is not in the keychain yet.
if security find-identity -p codesigning 2>/dev/null | grep -q '"Susurro"'; then
    SIGN_ID="Susurro"
    echo "==> Codesigning with stable identity: $SIGN_ID"
else
    SIGN_ID="-"
    echo "==> Codesigning ad-hoc (no \"Susurro\" identity found; permissions will reset on rebuild)"
fi
codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$DEST"

echo
echo "Done: $DEST"
echo "Run it:        open $DEST"
echo "Install it:    cp -R $DEST /Applications/"
