#!/bin/bash
# Installs the latest Susurro release into /Applications. Downloads made with curl carry
# no quarantine flag, so this path never hits the Gatekeeper "unverified app" wall.
set -euo pipefail

ZIP_URL="https://github.com/BraisonCrece/susurro/releases/latest/download/Susurro.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading the latest Susurro release"
curl -fsSL -o "$TMP/Susurro.zip" "$ZIP_URL"
ditto -x -k "$TMP/Susurro.zip" "$TMP"

echo "==> Installing to /Applications"
osascript -e 'tell application "Susurro" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/Susurro.app
ditto "$TMP/Susurro.app" /Applications/Susurro.app
xattr -rd com.apple.quarantine /Applications/Susurro.app 2>/dev/null || true

open /Applications/Susurro.app
echo "✅ Susurro installed — the app will now walk you through permissions and setup."
