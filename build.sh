#!/bin/zsh
# Builds Windows App Runner and installs it to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/Windows App Runner.app"
BUILD=build

rm -rf "$BUILD"
mkdir -p "$BUILD/AppIcon.iconset"

echo "→ Compiling"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -o "$BUILD/WindowsAppRunner" Sources/*.swift

echo "→ Rendering icon"
swift Resources/MakeIcon.swift "$BUILD/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "→ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/WindowsAppRunner" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "✓ Installed $APP"
