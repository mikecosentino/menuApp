#!/bin/bash
# Builds a Developer ID-signed, notarized, stapled menuApp.app, zips it, and
# (optionally) publishes a GitHub release.
#
# One-time setup (see README "Releasing"):
#   1. A "Developer ID Application" certificate in your keychain.
#   2. A notarytool keychain profile:
#        xcrun notarytool store-credentials menuApp-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Usage:
#   MENUAPP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   MENUAPP_NOTARY_PROFILE="menuApp-notary" \
#   ./release.sh 1.2.0            # build + notarize + staple + zip
#   ./release.sh 1.2.0 --publish  # …and create the GitHub release/tag
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
PUBLISH=""
[ "${2:-}" = "--publish" ] && PUBLISH=1

: "${MENUAPP_SIGN_IDENTITY:?Set MENUAPP_SIGN_IDENTITY to your 'Developer ID Application: …' identity}"
: "${MENUAPP_NOTARY_PROFILE:?Set MENUAPP_NOTARY_PROFILE to your notarytool keychain profile name}"

if [ -z "${VERSION}" ]; then
    echo "Usage: ./release.sh <version> [--publish]" >&2
    exit 1
fi

APP="menuApp.app"
ZIP="menuApp-${VERSION}.zip"

# 1. Build + Developer ID sign (build_app.sh honors VERSION + MENUAPP_SIGN_IDENTITY).
VERSION="${VERSION}" MENUAPP_SIGN_IDENTITY="${MENUAPP_SIGN_IDENTITY}" ./build_app.sh

# 2. Sanity-check the signature.
echo "→ Verifying signature…"
codesign --verify --strict --verbose=2 "${APP}"

# 3. Zip for submission (ditto preserves bundle structure/symlinks/perms).
echo "→ Zipping for notarization…"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

# 4. Notarize — blocks until Apple finishes scanning.
echo "→ Notarizing (this can take a few minutes)…"
xcrun notarytool submit "${ZIP}" --keychain-profile "${MENUAPP_NOTARY_PROFILE}" --wait

# 5. Staple the ticket into the .app so it validates offline, then re-zip.
echo "→ Stapling…"
xcrun stapler staple "${APP}"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

# 6. Confirm Gatekeeper will accept it.
echo "→ Gatekeeper assessment:"
spctl --assess --type execute --verbose=4 "${APP}" || true

echo "✓ ${ZIP} is notarized and stapled."

if [ -n "${PUBLISH}" ]; then
    TAG="v${VERSION}"
    echo "→ Publishing GitHub release ${TAG}…"
    gh release create "${TAG}" "${ZIP}" \
        --title "menuApp ${VERSION}" \
        --generate-notes
    echo "✓ Released ${TAG}"
else
    echo "  Publish with:"
    echo "    gh release create v${VERSION} \"${ZIP}\" --title \"menuApp ${VERSION}\" --generate-notes"
fi
