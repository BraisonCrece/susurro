#!/bin/bash
set -euo pipefail

APP="Susurro"
BUNDLE_ID="com.local.susurro"
DEST="$APP.app"
VERSION=""
INSTALL=false

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --install) INSTALL=true; shift ;;
        *) echo "Uso: $0 [--version X.Y.Z] [--install]"; exit 1 ;;
    esac
done

# Universal (arm64 + x86_64) needs xcbuild, which ships with full Xcode but not with the
# Command Line Tools; with CLT only, fall back to a native single-arch build.
if [ -d "$(xcode-select -p 2>/dev/null)/../SharedFrameworks/XCBuild.framework" ]; then
    echo "==> Building release binary (universal)"
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/$APP"
else
    echo "==> Building release binary ($(uname -m) only; universal builds need full Xcode)"
    swift build -c release
    BIN=".build/release/$APP"
fi
[ -f "$BIN" ] || { echo "Binary not found at $BIN"; exit 1; }

# The Sparkle SPM artifact ships the framework inside an xcframework; pick the macOS slice.
SPARKLE=$(find .build/artifacts -type d -path "*macos*/Sparkle.framework" | head -1)
[ -n "$SPARKLE" ] || { echo "Sparkle.framework not found under .build/artifacts"; exit 1; }

echo "==> Assembling $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources" "$DEST/Contents/Frameworks"
cp "$BIN" "$DEST/Contents/MacOS/$APP"
cp Resources/Info.plist "$DEST/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$DEST/Contents/Resources/AppIcon.icns"

if [ -n "$VERSION" ]; then
    echo "==> Stamping version $VERSION"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$DEST/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$DEST/Contents/Info.plist"
fi

echo "==> Embedding Sparkle.framework"
# ditto preserves the symlink structure inside the framework (cp would break codesigning).
ditto "$SPARKLE" "$DEST/Contents/Frameworks/Sparkle.framework"
FRAMEWORK="$DEST/Contents/Frameworks/Sparkle.framework"
# Susurro is not sandboxed, so Sparkle's XPC services are unused; dropping them slims the
# bundle and the signing surface (removal documented by Sparkle for this case).
rm -rf "$FRAMEWORK/Versions/Current/XPCServices" "$FRAMEWORK/XPCServices"

# Prefer a stable self-signed identity named "Susurro" so TCC grants survive updates.
# Falls back to ad-hoc (-) if that identity is not in the keychain yet.
if security find-identity -p codesigning 2>/dev/null | grep -q '"Susurro"'; then
    SIGN_ID="Susurro"
    echo "==> Codesigning with stable identity: $SIGN_ID"
else
    SIGN_ID="-"
    echo "==> Codesigning ad-hoc (no \"Susurro\" identity found; permissions will reset on rebuild)"
fi

# Inside-out, never --deep (Sparkle's documented signing order).
codesign --force --sign "$SIGN_ID" "$FRAMEWORK/Versions/Current/Autoupdate"
codesign --force --sign "$SIGN_ID" "$FRAMEWORK/Versions/Current/Updater.app"
codesign --force --sign "$SIGN_ID" "$FRAMEWORK"
codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$DEST"
codesign --verify --strict --deep "$DEST"

# Install to /Applications so Spotlight/Raycast can find it. TCC keys on the (stable)
# signature rather than the path, so accessibility grants carry over.
if [ "$INSTALL" = true ]; then
    INSTALLED="/Applications/$APP.app"
    echo "==> Installing to $INSTALLED"
    rm -rf "$INSTALLED"
    cp -R "$DEST" "$INSTALLED"
fi

echo
echo "Done: $DEST"
echo "Run it:        open $DEST"
echo "Install it:    ./build-app.sh --install   (copies to /Applications)"
