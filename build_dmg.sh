#!/bin/bash

# LightToDo DMG 打包脚本
# 功能：自动构建 App Bundle 并生成可分发的 .dmg 文件

set -e
# 确保脚本在它所在的目录下运行，允许从任意位置执行
cd "$(dirname "$0")"

# 配置
APP_NAME="Light To Do"
APP_DIR="$(pwd)"
APP_BUNDLE="$APP_DIR/$APP_NAME.app"
DMG_NAME="LightToDo_Installer.dmg"
TEMP_DMG="temp_$DMG_NAME"
STAGING_DIR="dmg_staging"

echo "🚀 第一步：执行 build_app.sh 确保构建最新版本..."
chmod +x build_app.sh
./build_app.sh

echo "📦 第二步：准备打包目录..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 复制 App 到临时目录
cp -r "$APP_BUNDLE" "$STAGING_DIR/"

# 创建 Applications 软链接（让用户能直接拖拽安装）
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 第三步：创建 DMG 镜像..."
rm -f "$DMG_NAME" "$TEMP_DMG"

# 创建临时读写镜像
hdiutil create -srcfolder "$STAGING_DIR" -volname "$APP_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$TEMP_DMG"

# 挂载镜像以进行格式化
device=$(hdiutil attach -readwrite -noverify "$TEMP_DMG" | egrep '^/dev/' | sed 1q | awk '{print $1}')
sleep 2 # 等待挂载

sync
hdiutil detach "$device"

echo "🔒 第四步：压缩并转换位最终 DMG 格式..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"

# 清理
rm -rf "$STAGING_DIR"
rm -f "$TEMP_DMG"

echo "----------------------------------------------------"
echo "✅ 打包完成！"
echo "📂 文件位置: $(pwd)/$DMG_NAME"
echo "📢 提示: 由于未进行代码签名（Signing），用户下载后打开时可能需要："
echo "   右键点击应用选择『打开』，或在『系统设置 -> 隐私与安全性』中手动允许运行。"
echo "----------------------------------------------------"
