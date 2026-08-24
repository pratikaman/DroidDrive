#!/bin/zsh
# Builds DroidDrive.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Compiling (release)…"
swift build -c release

APP="DroidDrive.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DroidDrive "$APP/Contents/MacOS/DroidDrive"
cp packaging/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f packaging/AppIcon.icns ]]; then
  echo "▸ Generating app icon…"
  swift packaging/make_icon.swift packaging
fi
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - "$APP"

echo "✓ Built $(pwd)/$APP"
