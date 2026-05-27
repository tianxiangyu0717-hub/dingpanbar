#!/bin/bash
# 一键打包对外分发的 .dmg 安装镜像。
#
# 产出：dist/盯盘Bar-<MARKETING_VERSION>.dmg
# 用户拿到 .dmg 后：双击挂载 → 把「DingPanBar」拖到「Applications」文件夹即完成安装。
#
# 依赖：Xcode、xcodegen、create-dmg（brew install create-dmg）、codesign（系统自带）。
set -euo pipefail
cd "$(dirname "$0")"

PRODUCT_NAME="DingPanBar"
DISPLAY_NAME="盯盘 Bar"
VERSION=$(awk '/MARKETING_VERSION/ {gsub(/"/,"",$2); print $2}' project.yml)
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/_stage"
DMG_NAME="盯盘Bar-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "▶ 准备构建 $DISPLAY_NAME $VERSION ..."

# 0. 依赖检查
command -v xcodegen   >/dev/null 2>&1 || { echo "❌ 需要 xcodegen（brew install xcodegen）"; exit 1; }
command -v create-dmg >/dev/null 2>&1 || { echo "❌ 需要 create-dmg（brew install create-dmg）"; exit 1; }

# 1. 生成工程 + 编译 Release
echo "▶ xcodegen → xcodebuild Release ..."
xcodegen generate >/dev/null
xcodebuild \
  -project "${PRODUCT_NAME}.xcodeproj" \
  -scheme "$PRODUCT_NAME" \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  -quiet build

APP_SRC="build/Build/Products/Release/${PRODUCT_NAME}.app"
[[ -d "$APP_SRC" ]] || { echo "❌ 编译产物不存在：$APP_SRC"; exit 1; }

# 2. ad-hoc 签名（让 Gatekeeper 容忍未签名警告；用户首次仍可能需要绕过）
echo "▶ ad-hoc 签名 ..."
codesign --force --deep --sign - "$APP_SRC" >/dev/null

# 3. 准备暂存目录（仅放 .app，create-dmg 自动添加 Applications 软链与箭头）
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_SRC" "$STAGE_DIR/${PRODUCT_NAME}.app"

echo "▶ 暂存目录已就绪：$STAGE_DIR"

# 4. 打 DMG（专业拖拽安装界面：左边 App 图标 + 箭头 + 右边 Applications 文件夹）
#
#   窗口 540×320，App 图标居左 (135, 160)，Applications 居右 (405, 160)。
#   --app-drop-link 自动生成 /Applications 软链并在两者间画箭头。
#
echo "▶ 打包 DMG → $DMG_PATH ..."
create-dmg \
  --volname        "$DISPLAY_NAME" \
  --window-pos     200 120 \
  --window-size    540 320 \
  --icon-size      120 \
  --icon           "${PRODUCT_NAME}.app" 135 160 \
  --hide-extension "${PRODUCT_NAME}.app" \
  --app-drop-link  405 160 \
  "$DMG_PATH" \
  "$STAGE_DIR"

# 5. 清理暂存
rm -rf "$STAGE_DIR"

SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
echo ""
echo "✅ 完成！"
echo "   $DMG_PATH ($SIZE)"
echo ""
echo "把这个 .dmg 分享给用户。用户双击挂载后，把「DingPanBar」拖到「Applications」即完成安装。"
echo "首次打开若提示「无法验证开发者」：右键点 App → 打开 → 再点「打开」即可。"
