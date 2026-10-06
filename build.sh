#!/bin/bash
# Builds 重要待办.app with the installed Command Line Tools (no full Xcode needed).
#
#   ./build.sh              build the app bundle
#   ./build.sh --preview    also render the card to preview/*.png
#   ./build.sh --test       run the headless logic checks
#   ./build.sh --run        build, then launch

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos13.0"
APP="$HERE/build/重要待办.app"
EXEC="DailyCheck"
SOURCES=(Sources/main.swift Sources/Store.swift Sources/Theme.swift
         Sources/WidgetView.swift Sources/Panel.swift Sources/StatusBar.swift
         Sources/HotKey.swift Sources/Resize.swift)

echo "==> compiling"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -sdk "$SDK" -target "$TARGET" \
  -framework AppKit -framework SwiftUI -framework Carbon \
  "${SOURCES[@]}" \
  -o "$APP/Contents/MacOS/$EXEC"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>重要待办</string>
  <key>CFBundleDisplayName</key><string>重要待办</string>
  <key>CFBundleIdentifier</key><string>com.local.dailycheck</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   (ad-hoc signing skipped)"
echo "==> built $APP"

if [[ "${1:-}" == "--preview" ]]; then
  echo "==> rendering previews"
  swiftc -O -sdk "$SDK" -target "$TARGET" \
    -framework AppKit -framework SwiftUI \
    Sources/Store.swift Sources/Theme.swift Sources/WidgetView.swift Sources/Preview.swift \
    -o "$HERE/build/preview-render"
  "$HERE/build/preview-render" "$HERE/preview"
fi

if [[ "${1:-}" == "--run" ]]; then
  echo "==> launching"
  open "$APP"
fi

if [[ "${1:-}" == "--test" ]]; then
  echo "==> running checks"
  swiftc -O -sdk "$SDK" -target "$TARGET" \
    Sources/Store.swift Sources/Tests.swift \
    -o "$HERE/build/logic-tests"
  "$HERE/build/logic-tests"
fi
