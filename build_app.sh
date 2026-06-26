#!/bin/bash
# Builds menuApp and packages it into a double-clickable .app bundle.
#
# Env overrides (used by release.sh; safe defaults for local dev):
#   VERSION                 marketing/build version written to Info.plist (default 1.0.0)
#   MENUAPP_SIGN_IDENTITY   codesign identity; "-" = ad-hoc (default).
#                           Set to "Developer ID Application: …" for a notarizable build.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="menuApp"
BUILD_CONFIG="release"
BUNDLE="${APP_NAME}.app"
CONTENTS="${BUNDLE}/Contents"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${MENUAPP_SIGN_IDENTITY:--}"   # default ad-hoc

# Universal so the same download runs on Apple Silicon and Intel.
ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "→ Building ${APP_NAME} ${VERSION} (${BUILD_CONFIG}, universal)…"
swift build -c "${BUILD_CONFIG}" "${ARCH_FLAGS[@]}"

BIN_PATH="$(swift build -c "${BUILD_CONFIG}" "${ARCH_FLAGS[@]}" --show-bin-path)/${APP_NAME}"

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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
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

if [ "${SIGN_IDENTITY}" = "-" ]; then
    # Local dev: ad-hoc so WKWebView / network access work without friction.
    echo "→ Codesigning (ad-hoc)…"
    codesign --force --sign - "${BUNDLE}" >/dev/null 2>&1 || \
        echo "  (codesign skipped — app will still run)"
else
    # Distribution: Developer ID + hardened runtime + secure timestamp, which
    # notarization requires. No nested code, so signing the bundle once suffices.
    echo "→ Codesigning (Developer ID, hardened runtime)…"
    codesign --force --options runtime --timestamp \
        --sign "${SIGN_IDENTITY}" "${BUNDLE}"
fi

echo "✓ Built ${BUNDLE} (${VERSION})"
echo "  Run it:    open ${BUNDLE}"
echo "  Install:   cp -r ${BUNDLE} /Applications/"
