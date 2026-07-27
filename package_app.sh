#!/bin/bash
# Builds a release binary and wraps it into a proper double-clickable
# PipePlayer.app bundle in dist/ — re-run this any time after code changes
# to refresh the app. No Xcode required; just Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PipePlayer"
BUNDLE_ID="com.brokosz.pipeplayer"
VERSION="1.0"

swift build -c release

DIST_APP="dist/${APP_NAME}.app"
rm -rf "dist"
mkdir -p "${DIST_APP}/Contents/MacOS"
mkdir -p "${DIST_APP}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${DIST_APP}/Contents/MacOS/${APP_NAME}"

cat > "${DIST_APP}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper doesn't flag a locally-built, unsigned app.
codesign --force --deep --sign - "${DIST_APP}"

echo "Built ${DIST_APP}"
