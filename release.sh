#!/bin/bash
# 发布 JBar：Developer ID 签名 → 公证(notarize) → staple → 打包 zip → 发布 GitHub Release
#
# 前置条件（只需做一次）：
#   1) 已安装 "Developer ID Application" 证书（security find-identity -v -p codesigning 可见）
#   2) 已存储公证凭据到钥匙串 profile "notarytool"：
#        xcrun notarytool store-credentials "notarytool" \
#          --apple-id "<你的 Apple ID 邮箱>" --team-id "4U547984E8" \
#          --password "<App 专用密码>"
#   3) gh 已登录（gh auth status）
#
# 用法： ./release.sh <version>      例如 ./release.sh 1.0.0
set -euo pipefail

VERSION="${1:?用法: ./release.sh <version>，例如 ./release.sh 1.0.0}"
APP_NAME="JBar"
APP_DIR="build/$APP_NAME.app"
ZIP_PATH="build/${APP_NAME}-${VERSION}.zip"
NOTARY_PROFILE="notarytool"
REPO="joway/jbar"

# 自动识别钥匙串里的 "Developer ID Application" 证书（可用 JBAR_SIGN_IDENTITY 覆盖）。
IDENTITY="${JBAR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "!! 未找到 Developer ID Application 证书，无法发布。"
    echo "   请先在钥匙串里安装该证书（Apple Developer 账号下载），或设置 JBAR_SIGN_IDENTITY。"
    exit 1
fi
echo "==> 使用签名身份：$IDENTITY"

echo "==> 1/6 构建 + Developer ID 签名"
JBAR_SIGN_IDENTITY="$IDENTITY" JBAR_VERSION="$VERSION" ./build_app.sh release

echo "==> 2/6 打包待公证 zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> 3/6 提交公证（等待结果，可能数分钟）"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> 4/6 staple 票据到 .app"
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl -a -vv -t exec "$APP_DIR"

echo "==> 5/6 重新打包（含已 staple 的票据）"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> 6/6 发布 GitHub Release v$VERSION"
NOTES="JBar v$VERSION — 即刻关注流的 macOS 菜单栏通知应用。

下载 \`${APP_NAME}-${VERSION}.zip\`，解压后将 JBar.app 拖到「应用程序」，首次打开扫码登录即可。"
gh release create "v$VERSION" "$ZIP_PATH" \
    --repo "$REPO" \
    --title "JBar v$VERSION" \
    --notes "$NOTES"

echo "==> 完成：https://github.com/$REPO/releases/tag/v$VERSION"
