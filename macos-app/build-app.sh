#!/bin/bash

set -euo pipefail

MACOS_APP_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(cd "${MACOS_APP_DIR}/.." && pwd)
DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/Volta 自动更新.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

swift build --package-path "$MACOS_APP_DIR" -c release
BUILD_BIN_DIR=$(swift build --package-path "$MACOS_APP_DIR" -c release --show-bin-path)

if [ -d "$APP_BUNDLE" ]; then
    /bin/rm -rf "$APP_BUNDLE"
fi

/bin/mkdir -p "$MACOS_DIR" "${RESOURCES_DIR}/Runtime"
/usr/bin/install -m 755 "${BUILD_BIN_DIR}/VoltaAutoUpdate" "${MACOS_DIR}/VoltaAutoUpdate"
/usr/bin/install -m 644 "${MACOS_APP_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/bin/install -m 644 "${MACOS_APP_DIR}/Resources/AppIcon/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
/usr/bin/install -m 755 "${MACOS_APP_DIR}/Resources/Runtime/schedule-manager.sh" "${RESOURCES_DIR}/Runtime/schedule-manager.sh"
/usr/bin/install -m 755 "${MACOS_APP_DIR}/Resources/Runtime/scheduled-update.sh" "${RESOURCES_DIR}/Runtime/scheduled-update.sh"
/usr/bin/install -m 644 "${MACOS_APP_DIR}/Resources/Runtime/launch-agent.plist.template" "${RESOURCES_DIR}/Runtime/launch-agent.plist.template"
/usr/bin/install -m 755 "${PROJECT_DIR}/update-volta-tools.sh" "${RESOURCES_DIR}/Runtime/update-volta-tools.sh"

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
