#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/CodexQuota.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
swiftc -parse-as-library -O -framework AppKit -framework SwiftUI -framework Combine -o "$APP/Contents/MacOS/CodexQuota" "$ROOT/CodexQuota.swift"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
ICONSET="$ROOT/dist/CodexQuota.iconset"
mkdir -p "$ICONSET"
swiftc -O -framework AppKit "$ROOT/IconGenerator.swift" -o "$ROOT/dist/make-icon"
"$ROOT/dist/make-icon" "$ROOT/dist/codex-quota-icon.png"
for pair in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
    read -r size name <<< "$pair"
    sips -s format png -z "$size" "$size" "$ROOT/dist/codex-quota-icon.png" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
echo "Built $APP"
