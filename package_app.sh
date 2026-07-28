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

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${DIST_APP}/Contents/Resources/AppIcon.icns"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Bagpipe Tune File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.brokosz.pipeplayer.bww</string>
                <string>com.brokosz.pipeplayer.bmw</string>
                <string>com.brokosz.pipeplayer.abc</string>
                <string>com.brokosz.pipeplayer.musicxml</string>
                <string>com.brokosz.pipeplayer.mxl</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.brokosz.pipeplayer.bww</string>
            <key>UTTypeDescription</key>
            <string>Bagpipe Music Writer Tune</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.plain-text</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>bww</string></array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.brokosz.pipeplayer.bmw</string>
            <key>UTTypeDescription</key>
            <string>Bagpipe Musicworks Tune</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.plain-text</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>bmw</string></array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.brokosz.pipeplayer.abc</string>
            <key>UTTypeDescription</key>
            <string>ABC Notation Tune</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.plain-text</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>abc</string></array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.brokosz.pipeplayer.musicxml</string>
            <key>UTTypeDescription</key>
            <string>MusicXML Tune</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.xml</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>musicxml</string>
                    <string>xml</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.brokosz.pipeplayer.mxl</string>
            <key>UTTypeDescription</key>
            <string>Compressed MusicXML Tune</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>mxl</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Downloaded resources (e.g. an icon dragged in from Downloads) can carry
# FinderInfo/resource-fork xattrs that make codesign refuse to sign — strip
# them from the assembled bundle before signing rather than assuming the
# source file in Resources/ is always already clean.
xattr -cr "${DIST_APP}"

# Ad-hoc sign so Gatekeeper doesn't flag a locally-built, unsigned app.
codesign --force --deep --sign - "${DIST_APP}"

echo "Built ${DIST_APP}"
