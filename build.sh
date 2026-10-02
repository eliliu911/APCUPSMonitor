#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Compiling APCUPSMonitor..."
mkdir -p .build/module-cache
swiftc -O -target arm64-apple-macos14.0 \
    -module-cache-path .build/module-cache \
    APCUPSMonitor/*.swift \
    -framework IOKit -framework SwiftUI -framework AppKit \
    -o .build/APCUPSMonitor

echo "==> Packaging APCUPSMonitor.app..."
mkdir -p APCUPSMonitor.app/Contents/MacOS
mkdir -p APCUPSMonitor.app/Contents/Resources
cp APCUPSMonitor/Info.plist APCUPSMonitor.app/Contents/Info.plist
if [[ -f APCUPSMonitor/AppIcon.icns ]]; then
    cp APCUPSMonitor/AppIcon.icns APCUPSMonitor.app/Contents/Resources/AppIcon.icns
fi
cp .build/APCUPSMonitor APCUPSMonitor.app/Contents/MacOS/APCUPSMonitor
codesign --force --deep --sign - APCUPSMonitor.app

echo "==> Build complete: APCUPSMonitor.app"

if [[ "${1:-}" == "install" ]]; then
    TARGET_DIR="${2:-/Applications}"
    echo "==> Installing to ${TARGET_DIR}..."
    rm -rf "${TARGET_DIR}/APCUPSMonitor.app"
    cp -R APCUPSMonitor.app "${TARGET_DIR}/"
    echo "==> Successfully installed to ${TARGET_DIR}/APCUPSMonitor.app"
fi
