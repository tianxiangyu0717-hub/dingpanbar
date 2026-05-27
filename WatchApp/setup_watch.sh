#!/bin/bash
# 装好完整 Xcode 后，运行本脚本即可生成并打开手表端工程。
set -e
cd "$(dirname "$0")"

# 1. 校验完整 Xcode（不是 Command Line Tools）
DEV_DIR=$(xcode-select -p 2>/dev/null || true)
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
  echo "❌ 当前 developer 目录是: ${DEV_DIR:-未设置}"
  echo "   请先安装完整 Xcode，并执行："
  echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "   再打开一次 Xcode 同意许可（或: sudo xcodebuild -license accept）"
  exit 1
fi
echo "✅ Xcode: $(xcodebuild -version | head -1)"

# 2. 校验 xcodegen
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ 未找到 xcodegen，请先: brew install xcodegen"
  exit 1
fi

# 3. 生成工程
echo "▶ 生成 GoldAU9999.xcodeproj ..."
xcodegen generate
echo "✅ 工程已生成"

# 4. 打开
open GoldAU9999.xcodeproj
cat <<'TIP'

────────────────────────────────────────────────
接下来在 Xcode 里（通过 iPhone 部署，绕开 Mac↔手表隧道）：
1. 顶部 scheme 选 GoldPhone。Team 已固化在工程里，
   如需改：三个 target 的 Signing & Capabilities → Team。
2. 数据线连 iPhone，运行目标选你的 iPhone（不要选手表/模拟器），
   点 ▶ Run。
3. 首次：iPhone ▸ 设置 ▸ 通用 ▸ VPN与设备管理 ▸ 信任开发者。
4. iPhone 打开「Watch」App ▸ 找到「金价」▸ 安装到手表。
5. 表盘加复杂功能：长按表盘 ▸ 编辑 ▸ 选复杂功能位 ▸ 选 AU9999。

提示：免费 Apple ID 安装的 App 每 7 天过期，重新 Run 即可续期。
表盘复杂功能受 watchOS 限流，实际刷新约 15–30 分钟；
要看 60 秒实时，打开手表 App 或 iPhone App 本体。
────────────────────────────────────────────────
TIP
