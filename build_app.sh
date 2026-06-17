#!/bin/bash
# Builds menuApp and packages it into a double-clickable .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="menuApp"
BUILD_CONFIG="release"
BUNDLE="${APP_NAME}.app"
CONTENTS="${BUNDLE}/Contents"

echo "→ Building (${BUILD_CONFIG})…"
swift build -c "${BUILD_CONFIG}"

BIN_PATH="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)/${APP_NAME}"

echo "→ Assembling ${BUNDLE}…"
rm -rf "${BUNDLE}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${BIN_PATH}" "${CONTENTS}/MacOS/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>menuApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.menuapp.menubar</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc codesign so WKWebView / network access works without Gatekeeper friction.
echo "→ Codesigning (ad-hoc)…"
codesign --force --deep --sign - "${BUNDLE}" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app will still run)"

echo "✓ Built ${BUNDLE}"
echo "  Run it:    open ${BUNDLE}"
echo "  Install:   cp -r ${BUNDLE} /Applications/"
