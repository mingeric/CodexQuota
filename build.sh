#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/CodexQuota.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library -O -framework AppKit -framework SwiftUI -framework Combine -o "$APP/Contents/MacOS/CodexQuota" "$ROOT/CodexQuota.swift"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
echo "Built $APP"
