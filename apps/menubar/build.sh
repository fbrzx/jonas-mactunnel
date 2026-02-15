#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="OCTunnel"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"

echo "Compiling ${APP_NAME}..."
swiftc -O \
    -o "${SCRIPT_DIR}/${APP_NAME}" \
    "${SCRIPT_DIR}/${APP_NAME}.swift" \
    -framework Cocoa \
    -suppress-warnings

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${SCRIPT_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${SCRIPT_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    cp "${SCRIPT_DIR}/.env" "${APP_BUNDLE}/Contents/Resources/.env"
fi

# Clean up loose binary
rm -f "${SCRIPT_DIR}/${APP_NAME}"

echo "Built: ${APP_BUNDLE}"
echo ""
echo "To install to Applications:"
echo "  cp -r \"${APP_BUNDLE}\" ~/Applications/"
echo ""
echo "To launch now:"
echo "  open \"${APP_BUNDLE}\""
