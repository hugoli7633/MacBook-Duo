#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/MacBook Duo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/ModuleCache"

mkdir -p "$MODULE_CACHE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Assets/MacBookDuo.icns" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Assets/MacBookDuo.png" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Assets/MacBookPro14.png" "$CONTENTS_DIR/Resources/"
mkdir -p "$CONTENTS_DIR/Helpers"
swiftc -module-cache-path "$MODULE_CACHE_DIR" -O -framework AppKit "$PROJECT_DIR/Helpers/RestartHelper.swift" -o "$CONTENTS_DIR/Helpers/RestartHelper"
codesign --force --sign - "$CONTENTS_DIR/Helpers/RestartHelper"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -framework QuartzCore \
  -framework MetalKit \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -framework Security \
  -framework ServiceManagement \
  -o "$MACOS_DIR/HingeGlass" \
  "$PROJECT_DIR"/Sources/*.swift

codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
