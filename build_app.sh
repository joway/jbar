#!/bin/bash
# 构建 JBar 并打包成 .app（菜单栏应用），输出到 ./build/JBar.app
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="JBar"
BUNDLE_ID="com.joway.jbar"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

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
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 代码签名（本地自用）"
codesign --force --deep --sign - "$APP_DIR"

echo "==> 完成：$APP_DIR"
echo "运行：open $APP_DIR  （或 ./$APP_DIR/Contents/MacOS/$APP_NAME 看日志）"
