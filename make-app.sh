#!/bin/bash
# Build the MorseRunner macOS app bundle from the SwiftPM build.
set -e
cd "$(dirname "$0")"

APP="dist/MorseRunner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# build only the app product (the test target needs @testable, debug only)
swift build -c release --product MorseRunner

cp .build/release/MorseRunner "$APP/Contents/MacOS/MorseRunner"
cp -R Resources/* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Morse Runner</string>
    <key>CFBundleDisplayName</key>
    <string>Morse Runner for macOS</string>
    <key>CFBundleIdentifier</key>
    <string>org.morserunner.macos</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>MorseRunner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Morse Runner plays simulated CW audio through your speakers.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
