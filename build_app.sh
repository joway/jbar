#!/bin/bash
# 构建 JBar 并打包成 .app（菜单栏应用），输出到 ./build/JBar.app
#
# 环境变量：
#   JBAR_SIGN_IDENTITY  签名身份（默认 "-" 即 ad-hoc，本地自用）。
#                       发布时传 "Developer ID Application: ..."。
#   JBAR_VERSION        版本号（CFBundleShortVersionString），默认 0.1.0
#   JBAR_BUILD          构建号（CFBundleVersion），默认 1
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="JBar"
BUNDLE_ID="com.joway.jbar"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${JBAR_SIGN_IDENTITY:--}"
VERSION="${JBAR_VERSION:-0.1.0}"
BUILD_NUM="${JBAR_BUILD:-1}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# SwiftPM 资源 bundle（Firebase / GoogleUtilities 等）必须随包分发。
shopt -s nullglob
for b in "$BIN_DIR"/*.bundle; do
    cp -R "$b" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob
echo "==> 已拷贝 $(ls -d "$APP_DIR/Contents/Resources/"*.bundle 2>/dev/null | wc -l | tr -d ' ') 个资源 bundle"

# 应用图标。缺失则用 tools/make_icon.swift 现生成。
if [ ! -f "JBar.icns" ]; then
    echo "==> 生成 JBar.icns"
    swift tools/make_icon.swift build/JBar.iconset
    iconutil -c icns build/JBar.iconset -o JBar.icns
fi
cp "JBar.icns" "$APP_DIR/Contents/Resources/JBar.icns"
echo "==> 已拷贝 JBar.icns"

# Firebase 配置文件（FirebaseApp.configure 会从 Bundle 读取）。
if [ -f "GoogleService-Info.plist" ]; then
    cp "GoogleService-Info.plist" "$APP_DIR/Contents/Resources/GoogleService-Info.plist"
    echo "==> 已拷贝 GoogleService-Info.plist"
else
    echo "!! 警告：未找到 GoogleService-Info.plist，Firebase 将无法初始化"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>JBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUM</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> ad-hoc 代码签名（本地自用）"
    codesign --force --deep --sign - "$APP_DIR"
else
    echo "==> Developer ID 签名（hardened runtime）：$SIGN_IDENTITY"
    # 资源 bundle 全是纯资源（无 Mach-O），无需单独签名，会随 app 签名一并封存。
    # 唯一的可执行文件是静态链接的主程序，直接签 app 即可。
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
    echo "==> 验证签名"
    codesign --verify --strict --verbose=2 "$APP_DIR"
fi

echo "==> 完成：$APP_DIR (v$VERSION build $BUILD_NUM)"
