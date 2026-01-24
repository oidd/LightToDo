#!/bin/bash

# StickyNotes App Bundle 打包脚本 (Tiptap 适配版)
# 将 Swift 可执行文件及其资源 bundle 打包为 macOS App Bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
# 自动检测架构路径 (arm64-apple-macosx 或 x86_64-apple-macosx)
ARCH_DIR=$(ls "$PROJECT_DIR/.build" | grep "apple-macosx" | head -n 1)
BUILD_DIR="$PROJECT_DIR/.build/$ARCH_DIR/release"
APP_NAME="Light To Do"
EXE_NAME="LightToDo"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
EXECUTABLE="$BUILD_DIR/$EXE_NAME"
BUNDLE_NAME="${EXE_NAME}_${EXE_NAME}.bundle"
RESOURCES_BUNDLE="$BUILD_DIR/$BUNDLE_NAME"

echo "🔨 正在构建 Release 版本..."
cd "$PROJECT_DIR/Sources/LightToDo/react-editor"
npm install && npm run build
# 关键一步：同步构建产物到资源目录
cp dist/index.html "$PROJECT_DIR/Sources/LightToDo/Resources/lexical-editor.html"

cd "$PROJECT_DIR"
swift build -c release

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ 错误: 找不到可执行文件 $EXECUTABLE"
    exit 1
fi

echo "📦 正在创建 App Bundle..."

# 清理旧的 App Bundle
rm -rf "$APP_BUNDLE"

# 创建 App Bundle 目录结构
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/"

# 复制资源 Bundle (非常重要！否则 Tiptap.html 无法加载)
if [ -d "$RESOURCES_BUNDLE" ]; then
    echo " folder 发现资源束，正在拷贝..."
    cp -r "$RESOURCES_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
else
    echo "⚠️ 警告: 未发现资源束 $BUNDLE_NAME，请检查 Package.swift 配置"
fi

# 生成应用图标 (.icns)
echo "🎨 正在生成应用图标..."
ICONSET_DIR="$PROJECT_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
SRC_ICON="$PROJECT_DIR/Assets.xcassets/AppIcon.appiconset/icon_light.png"

sips -z 16 16     "$SRC_ICON" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
sips -z 32 32     "$SRC_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 32 32     "$SRC_ICON" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
sips -z 64 64     "$SRC_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 128 128   "$SRC_ICON" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
sips -z 256 256   "$SRC_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$SRC_ICON" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
sips -z 512 512   "$SRC_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$SRC_ICON" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
sips -z 1024 1024 "$SRC_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# 创建 Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>LightToDo</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.ivean.lighttodo</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>轻待办</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 创建 PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ App Bundle 创建成功: $APP_BUNDLE"
echo "🚀 正在启动应用..."
open "$APP_BUNDLE"
