#!/bin/bash
# 开发用脚本：生成 Xcode 工程 → 编译 Release → 装到 ~/Applications → 启动。
# 对外分发请用 release.sh（生成 .dmg 一键安装包）。
set -e
cd "$(dirname "$0")"

# 1. 校验完整 Xcode
DEV_DIR=$(xcode-select -p 2>/dev/null || true)
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
  echo "❌ 需要完整 Xcode。当前 developer 目录：${DEV_DIR:-未设置}"
  echo "   先：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

# 2. 校验 xcodegen
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ 未找到 xcodegen，请: brew install xcodegen"
  exit 1
fi

# 3. 生成工程
echo "▶ 生成 DingPanBar.xcodeproj ..."
xcodegen generate

# 4. 编译 Release
echo "▶ 编译 Release ..."
xcodebuild \
  -project DingPanBar.xcodeproj \
  -scheme DingPanBar \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  -quiet build

APP_SRC="build/Build/Products/Release/DingPanBar.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "❌ 编译完成但找不到产物：$APP_SRC"
  exit 1
fi

# 5. ad-hoc 签名（自机运行也用得上）
codesign --force --deep --sign - "$APP_SRC" >/dev/null 2>&1 || true

# 6. 安装到 ~/Applications（用户目录，免 sudo）
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x DingPanBar 2>/dev/null || true
rm -rf "$DEST/DingPanBar.app"
cp -R "$APP_SRC" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/DingPanBar.app" 2>/dev/null || true
echo "✅ 已安装到 $DEST/DingPanBar.app"

# 7. 启动
open "$DEST/DingPanBar.app"

cat <<'TIP'

────────────────────────────────────────────────
✅ 盯盘 Bar 已启动。看顶部菜单栏。

· 添加监控/设提醒：点状态栏图标 → 「设置…」
· 开机自启：系统设置 ▸ 通用 ▸ 登录项 ▸ + ▸ 选 ~/Applications/DingPanBar.app
· 退出 App：点状态栏图标 → 「退出」
· 更新代码：再次运行本脚本（会自动重装并重启）

对外分发：./release.sh 生成 dist/盯盘Bar-x.y.dmg
────────────────────────────────────────────────
TIP
