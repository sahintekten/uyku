#!/bin/bash
# Builds Uyku from source on this Mac and installs it to ~/Applications.
set -euo pipefail

REPO="https://github.com/sahintekten/uyku"
APP="$HOME/Applications/Uyku.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Uyku is built on your Mac, which needs Apple's Command Line Tools."
  echo "Starting their installer; run this script again when it has finished."
  xcode-select --install || true
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
if [ ! -f "$SRC/Sources/main.swift" ]; then
  # Started with "curl ... | bash": download the source first.
  echo "Downloading Uyku..."
  mkdir "$WORK/src"
  curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$WORK/src" --strip-components=1
  SRC="$WORK/src"
fi

echo "Building..."
BUNDLE="$WORK/Uyku.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
swiftc -O -swift-version 5 "$SRC/Sources/main.swift" -o "$BUNDLE/Contents/MacOS/Uyku"
cp "$SRC/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$SRC/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$BUNDLE" 2>/dev/null

pkill -x Uyku 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mv "$BUNDLE" "$APP"
open "$APP"

echo "Done. Look for the eye in your menu bar."
echo "Click it to switch, right-click it for options."
