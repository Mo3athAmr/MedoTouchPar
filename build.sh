#!/bin/zsh
# MedoTouchPar — free Touch Bar customizer. Made by Moath Alhakeem.
# Builds MedoTouchPar.app, signs it, installs it into /Applications,
# enables launch at login and starts it.
#   ./build.sh               build + install + launch
#   ./build.sh --no-install  build only (output in ./build)
set -euo pipefail
cd "${0:A:h}"

APP_NAME="MedoTouchPar"
BUNDLE_ID="com.medo.MedoTouchPar"
VERSION="3.0"
BUILD_NUMBER=$(date +%Y%m%d%H%M)
OUT="build/${APP_NAME}.app"
INSTALL_DIR="/Applications"
[[ -w "$INSTALL_DIR" ]] || INSTALL_DIR="$HOME/Applications"

echo "▸ Compiling (universal: Intel + Apple Silicon)"
swift build -c release --arch arm64 --arch x86_64

echo "▸ App icon"
if [[ ! -f Resources/AppIcon.icns ]]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    swift scripts/make_icon.swift "$ICONSET/icon_1024.png" >/dev/null
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    rm "$ICONSET/icon_1024.png"
    mkdir -p Resources
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

echo "▸ Bundle"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp ".build/apple/Products/Release/${APP_NAME}" "$OUT/Contents/MacOS/${APP_NAME}"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key><string>ar</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Moath Alhakeem. Free and open source (MIT).</string>
</dict>
</plist>
PLIST

echo "▸ Signing"
# A real signing identity keeps the Accessibility grant across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --deep --options runtime --timestamp=none --sign "${IDENTITY:--}" "$OUT"
codesign --verify --strict "$OUT"
echo "  signed with: ${IDENTITY:-ad-hoc}"

[[ "${1:-}" == "--no-install" ]] && { echo "✓ Built $OUT"; exit 0; }

echo "▸ Installing to ${INSTALL_DIR}"
pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
ditto "$OUT" "${INSTALL_DIR}/${APP_NAME}.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_DIR}/${APP_NAME}.app"
"${INSTALL_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" --register-login-item || true
open "${INSTALL_DIR}/${APP_NAME}.app"
echo "✓ Installed and launched ${INSTALL_DIR}/${APP_NAME}.app"
