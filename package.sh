#!/bin/zsh
# Builds Windows App Runner into dist/ and zips it for a GitHub release.
# Unlike build.sh it does not install anything into ~/Applications.
#
#   ./package.sh            # version is read from Resources/Info.plist
#
# Output: dist/Windows-App-Runner-<version>-macOS-arm64.zip
set -euo pipefail
cd "${0:A:h}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD=build
DIST=dist
APP="$DIST/Windows App Runner.app"
ZIP="$DIST/Windows-App-Runner-$VERSION-macOS-arm64.zip"

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD/AppIcon.iconset" "$DIST"

echo "→ Compiling $VERSION"
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/WindowsAppRunner" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "→ Zipping"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

echo "✓ $ZIP"
