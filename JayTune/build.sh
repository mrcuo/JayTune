#!/bin/bash
# JayTune Build Script - macOS SwiftUI app via swiftc CLI
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="JayTune"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
SWIFT_SRC="${PROJECT_DIR}/${APP_NAME}"
TOOLS_SRC="${PROJECT_DIR}/Tools"

echo "=== JayTune Build ==="
echo "Step 1: Clean previous build..."
rm -rf "${APP_BUNDLE}"

echo "Step 2: Create .app bundle structure..."
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"
mkdir -p "${RESOURCES}/Tools"

echo "Step 3: Compile AFC C tools..."
gcc -o "${RESOURCES}/Tools/afc_ls"   "${TOOLS_SRC}/afc_ls.c"   -limobiledevice-1.0 -lplist-2.0 -I/opt/homebrew/include -L/opt/homebrew/lib
gcc -o "${RESOURCES}/Tools/afc_read2" "${TOOLS_SRC}/afc_read2.c" -limobiledevice-1.0 -lplist-2.0 -I/opt/homebrew/include -L/opt/homebrew/lib
gcc -o "${RESOURCES}/Tools/afc_rm"    "${TOOLS_SRC}/afc_rm.c"    -limobiledevice-1.0 -lplist-2.0 -I/opt/homebrew/include -L/opt/homebrew/lib
chmod +x "${RESOURCES}/Tools/"*
echo "  ✓ AFC tools compiled"

echo "Step 4: Copy resources..."
cp "${PROJECT_DIR}/AppIcon.icns" "${RESOURCES}/"
cp -r "${PROJECT_DIR}/en.lproj"      "${RESOURCES}/"
cp -r "${PROJECT_DIR}/zh-Hans.lproj" "${RESOURCES}/"
echo "  ✓ Resources copied"

echo "Step 5: Compile Swift sources..."
# Collect all Swift source files
SWIFT_FILES=$(find "${SWIFT_SRC}" -name "*.swift" | sort | tr '\n' ' ')

swiftc \
    -sdk $(xcrun --show-sdk-path) \
    -target x86_64-apple-macos13.0 \
    -parse-as-library \
    -o "${MACOS}/${APP_NAME}" \
    ${SWIFT_FILES} \
    -framework SwiftUI \
    -framework AppKit \
    -framework UniformTypeIdentifiers
echo "  ✓ Swift compilation done"

echo "Step 6: Write Info.plist..."
cat > "${CONTENTS}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleExecutable</key>
    <string>JayTune</string>
    <key>CFBundleIdentifier</key>
    <string>com.jaytune.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>JayTune</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>LSUIElement</key>
    <false/>
</dict>
EOF

echo "Step 7: Set executable permissions..."
chmod +x "${MACOS}/${APP_NAME}"
echo "  ✓ Permissions set"

echo ""
echo "=== Build Complete ==="
echo "Output: ${APP_BUNDLE}"
echo "Launch: open '${APP_BUNDLE}'"
