#!/bin/zsh
# MedoTouchPar — free Touch Bar customizer. Made by Moath Alhakeem.
#   ./build.sh               universal build, install to /Applications, enable launch at login, start
#   ./build.sh --no-install  universal build only (build/MedoTouchPar.app)
#   ./build.sh --release     Intel and Apple Silicon apps + DMGs in build/release
set -euo pipefail
cd "${0:A:h}"

APP_NAME="MedoTouchPar"
BUNDLE_ID="com.medo.MedoTouchPar"
VERSION="1.0"
BUILD_NUMBER=$(date +%Y%m%d%H%M)
MODE="${1:-}"
INSTALL_DIR="/Applications"
[[ -w "$INSTALL_DIR" ]] || INSTALL_DIR="$HOME/Applications"
# A real signing identity keeps the Accessibility grant across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')

make_icon() {
    [[ -f Resources/AppIcon.icns ]] && return
    echo "▸ App icon"
    local iconset
    iconset=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$iconset" Resources
    swift scripts/make_icon.swift "$iconset/icon_1024.png" >/dev/null
    for s in 16 32 128 256 512; do
        sips -z $s $s "$iconset/icon_1024.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$iconset/icon_1024.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    rm "$iconset/icon_1024.png"
    iconutil -c icns "$iconset" -o Resources/AppIcon.icns
}

# make_bundle <binary> <output .app>
make_bundle() {
    local binary=$1 out=$2
    rm -rf "$out"
    mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
    cp "$binary" "$out/Contents/MacOS/${APP_NAME}"
    cp Resources/AppIcon.icns "$out/Contents/Resources/AppIcon.icns"
    cat > "$out/Contents/Info.plist" <<PLIST
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
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ar</string></array>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Moath Alhakeem. Free and open source (MIT).</string>
</dict>
</plist>
PLIST
    codesign --force --deep --options runtime --timestamp=none --sign "${IDENTITY:--}" "$out"
    codesign --verify --strict "$out"
}

# make_dmg <.app> <output .dmg>: drag-to-Applications disk image with the app icon.
make_dmg() {
    local app=$1 dmg=$2 stage
    stage=$(mktemp -d)/${APP_NAME}
    mkdir -p "$stage"
    ditto "$app" "$stage/${APP_NAME}.app"
    ln -s /Applications "$stage/Applications"
    cp Resources/AppIcon.icns "$stage/.VolumeIcon.icns"
    xcrun SetFile -a C "$stage"
    rm -f "$dmg"
    hdiutil create -quiet -volname "${APP_NAME} ${VERSION}" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg"
    codesign --force --sign "${IDENTITY:--}" --timestamp=none "$dmg"
}

make_icon

if [[ "$MODE" == "--release" ]]; then
    RELEASE=build/release
    rm -rf "$RELEASE"
    mkdir -p "$RELEASE"
    for arch label in arm64 AppleSilicon x86_64 Intel; do
        echo "▸ Compiling for ${label} (${arch})"
        # Separate scratch paths: SwiftPM trips over switching architectures in one build folder.
        swift build -c release --arch "$arch" --scratch-path ".build/release-${arch}"
        make_bundle ".build/release-${arch}/${arch}-apple-macosx/release/${APP_NAME}" "$RELEASE/${label}/${APP_NAME}.app"
        echo "  architecture: $(lipo -archs "$RELEASE/${label}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}")"
        make_dmg "$RELEASE/${label}/${APP_NAME}.app" "$RELEASE/${APP_NAME}-${VERSION}-${label}.dmg"
    done
    echo "✓ Release DMGs:"
    ls -lh "$RELEASE"/*.dmg | awk '{print "  " $5 "  " $9}'
    exit 0
fi

echo "▸ Compiling (universal: Intel + Apple Silicon)"
swift build -c release --arch arm64 --arch x86_64
OUT="build/${APP_NAME}.app"
echo "▸ Bundle & sign"
make_bundle ".build/apple/Products/Release/${APP_NAME}" "$OUT"
echo "  signed with: ${IDENTITY:-ad-hoc}"

[[ "$MODE" == "--no-install" ]] && { echo "✓ Built $OUT"; exit 0; }

echo "▸ Installing to ${INSTALL_DIR}"
pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
ditto "$OUT" "${INSTALL_DIR}/${APP_NAME}.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_DIR}/${APP_NAME}.app"
"${INSTALL_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" --register-login-item || true
open "${INSTALL_DIR}/${APP_NAME}.app"
echo "✓ Installed and launched ${INSTALL_DIR}/${APP_NAME}.app"
