#!/bin/bash
# Builds Notchling.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Notchling.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift -o "$APP/Contents/MacOS/Notchling"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/Notchling.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Notchling.app"
fi
