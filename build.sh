#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="JayTune"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BUILD_DIR="$SCRIPT_DIR/.build"
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk")"

ACTION="${1:-build}"

if [ "$ACTION" = "clean" ]; then
    echo "🧹 清理构建目录..."
    rm -rf "$BUILD_DIR" "$APP_BUNDLE"
    echo "✅ 清理完成"
    exit 0
fi

echo "🔨 编译 $APP_NAME (SDK: $SDK_PATH)..."

# 收集所有 Swift 源文件
SWIFT_FILES=($(find "$SCRIPT_DIR/$APP_NAME/JayTune" -name "*.swift" | sort))
echo "   找到 ${#SWIFT_FILES[@]} 个源文件"

mkdir -p "$BUILD_DIR"

# 编译（使用 xcrun 调用正确的 swiftc，不指定-sdk让系统自动选择）
xcrun swiftc \
    -target arm64-apple-macosx14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -Onone -g \
    "${SWIFT_FILES[@]}" \
    -o "$BUILD_DIR/$APP_NAME"

echo "✅ 编译成功: $BUILD_DIR/$APP_NAME"

# 创建 .app Bundle
echo "📦 打包 .app Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Tools"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 生成 Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>JayTune</string>
    <key>CFBundleIdentifier</key>
    <string>com.jaytune.JayTune</string>
    <key>CFBundleName</key>
    <string>JayTune</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
</dict>
</plist>
PLIST

# 生成并复制 App Icon (.icns)
ICONSET_DIR="$SCRIPT_DIR/$APP_NAME/IconSet.iconset"
ICNS_FILE="$SCRIPT_DIR/$APP_NAME/AppIcon.icns"

if [ -d "$ICONSET_DIR" ]; then
    # 生成 .icns 文件
    iconutil --convert icns --output "$ICNS_FILE" "$ICONSET_DIR" 2>/dev/null || true
fi

if [ -f "$ICNS_FILE" ]; then
    cp "$ICNS_FILE" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ 已打包 AppIcon.icns"
elif [ -d "$SCRIPT_DIR/$APP_NAME/Assets.xcassets" ]; then
    # 备用：复制 Assets.xcassets
    cp -R "$SCRIPT_DIR/$APP_NAME/Assets.xcassets" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ 已打包 Assets.xcassets"
fi

# 复制 AFC 工具
if [ -d "$SCRIPT_DIR/$APP_NAME/Tools" ]; then
    cp "$SCRIPT_DIR/$APP_NAME/Tools/"* "$APP_BUNDLE/Contents/Resources/Tools/" 2>/dev/null || true
    chmod +x "$APP_BUNDLE/Contents/Resources/Tools/"* 2>/dev/null || true
    echo "   ✅ 已打包 Tools"
fi

# 复制本地化资源 (.lproj)
for LANG_DIR in "$SCRIPT_DIR/$APP_NAME/"*.lproj; do
    if [ -d "$LANG_DIR" ]; then
        LANG_NAME=$(basename "$LANG_DIR")
        cp -R "$LANG_DIR" "$APP_BUNDLE/Contents/Resources/"
        echo "   ✅ 已打包本地化: $LANG_NAME"
    fi
done

# 备用：复制 Localizable.strings 到根 Resources（确保可找到）
if [ -f "$SCRIPT_DIR/$APP_NAME/en.lproj/Localizable.strings" ] && [ ! -f "$APP_BUNDLE/Contents/Resources/Localizable.strings" ]; then
    cp "$SCRIPT_DIR/$APP_NAME/en.lproj/Localizable.strings" "$APP_BUNDLE/Contents/Resources/"
fi

# ad-hoc 签名
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null && echo "   ✅ 已签名" || echo "   ⚠️  签名跳过"

echo ""
echo "✅ $APP_BUNDLE 已创建"

if [ "$ACTION" = "run" ]; then
    echo "🚀 启动 $APP_NAME..."
    open "$APP_BUNDLE"
fi
