#!/bin/sh
# Builds build/DockMenu.app. Needs only the Xcode Command Line Tools.
set -eu
cd "$(dirname "$0")"

APP=build/DockMenu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# The target is explicit: the compiler's default can be newer than this macOS.
swiftc -Osize -wmo -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx14.0" \
    -Xlinker -dead_strip \
    -o "$APP/Contents/MacOS/DockMenu" Sources/*.swift
strip -x "$APP/Contents/MacOS/DockMenu"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
