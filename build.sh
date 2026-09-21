#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "==> Building DockMinimize..."
mkdir -p .cache

SOURCES=(
    Sources/WindowManager.swift
    Sources/DockMonitor.swift
    Sources/AppDelegate.swift
    Sources/main.swift
)

# Kill any existing instance before rebuilding
killall DockMinimize 2>/dev/null || true

swiftc -O -module-cache-path .cache "${SOURCES[@]}" -o DockMinimize

echo "==> Creating DockMinimize.app bundle..."
APP_DIR="DockMinimize.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

mv DockMinimize "$APP_DIR/Contents/MacOS/DockMinimize"
cp Info.plist "$APP_DIR/Contents/Info.plist"

echo "==> Signing DockMinimize.app..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Successfully built DockMinimize.app!"

if [ "$1" == "install" ]; then
    echo "==> Installing to /Applications..."
    rm -rf /Applications/DockMinimize.app
    cp -R "$APP_DIR" /Applications/
    echo "==> Installed to /Applications/DockMinimize.app"
elif [ "$1" == "run" ]; then
    echo "==> Launching DockMinimize.app..."
    open "$APP_DIR"
fi
