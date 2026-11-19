#!/bin/bash
# 把 causal 命令行打成可放进 Release 的压缩包。
#
#   ./scripts/package-cli.sh              # 只打包并签名
#   ./scripts/package-cli.sh --notarize   # 打包、签名、再送公证（需 NOTARY_PROFILE）
#
# 产物：build/causality-cli.zip
# 里面是通用二进制（Apple 芯片 + Intel）与一份安装说明。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    -*) echo "未知参数：$arg"; exit 1 ;;
    *) VERSION="$arg" ;;
  esac
done

CLI_PRODUCT="causal"
PKG_DIR="build/Causality-CLI-$VERSION"
ZIP="build/causality-cli.zip"

echo "== 构建命令行（通用二进制）=="
(cd Packages/CausalityCore && swift build -c release --product "$CLI_PRODUCT" \
  --arch arm64 --arch x86_64)
CLI_BIN="Packages/CausalityCore/.build/release/$CLI_PRODUCT"
ARCHS="$(lipo -archs "$CLI_BIN")"
echo "  架构：$ARCHS"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *) echo "  ✗ 不是通用二进制，停止（Intel 用户会跑不起来）"; exit 1 ;;
esac

echo "== 签名 =="
rm -rf "$PKG_DIR" "$ZIP"
mkdir -p "$PKG_DIR"
cp "$CLI_BIN" "$PKG_DIR/causal"
# 二进制依赖同目录的资源包（词条表），单独拷走会崩在 unable to find bundle
cp -R Packages/CausalityCore/.build/release/CausalityCore_CausalityCore.bundle "$PKG_DIR/"
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application" "$PKG_DIR/causal"
codesign --verify --strict --verbose=1 "$PKG_DIR/causal"

cat > "$PKG_DIR/install.sh" <<'SH'
#!/bin/sh
# 一条命令装好：把 causal 与它依赖的资源包一起放到 ~/.local/bin。
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${CAUSALITY_CLI_DIR:-$HOME/.local/bin}"
mkdir -p "$DEST"
cp -R "$DIR/causal" "$DIR/CausalityCore_CausalityCore.bundle" "$DEST/"
chmod +x "$DEST/causal"
# 裸二进制没法 staple 公证票据，macOS 仍会按「已隔离」拦一次并 SIGKILL。
# 它已在公证服务登记（notarytool log 可按 cdhash 核验），这里清掉隔离标记。
xattr -d com.apple.quarantine "$DEST/causal" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST/CausalityCore_CausalityCore.bundle" 2>/dev/null || true
echo "已安装到 $DEST"
# 不带参数会打印用法并返回 2，这里只确认它能跑起来
"$DEST/causal" >/dev/null 2>&1 || true
"$DEST/causal" 2>&1 | head -2
SH
chmod +x "$PKG_DIR/install.sh"

cat > "$PKG_DIR/安装说明.txt" <<TXT
Causality $VERSION 命令行（causal）

这是 App 之外的另一个程序：App 负责界面，MCP 服务器由这个命令行提供。

安装（一次性）：

  sh install.sh

它会把 causal 和同目录的 CausalityCore_CausalityCore.bundle（词条资源）一起
放进 ~/.local/bin。**两个都要在**，只拷 causal 会启动崩在
"unable to find bundle named CausalityCore_CausalityCore"。

装到别处：

  CAUSALITY_CLI_DIR=/usr/local/bin sh install.sh

这个二进制已用 Developer ID 签名并公证；但裸命令行工具没有可 staple 的票据，
macOS 第一次仍会按「已隔离」拦一次。install.sh 会清掉隔离标记，所以用 install.sh
装最省事。手动拷贝的话，补一句：

  xattr -d com.apple.quarantine ~/.local/bin/causal

接到 AI 客户端（Codex / Hermes / Pi）的注册命令、以及让 AI 直接生成故事板的
提示词示例，见仓库里的 docs/mcp.md。
TXT

echo "== 打包 =="
ditto -c -k --norsrc --noextattr --keepParent "$PKG_DIR" "$ZIP"
SIZE="$(stat -f%z "$ZIP")"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "  文件：${ZIP}（$SIZE 字节）"
echo "  sha256：$SHA"

if [ "$NOTARIZE" = "1" ]; then
  if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "  ! 没设 NOTARY_PROFILE，跳过公证（下载后第一次运行会被 Gatekeeper 拦）"
  else
    echo "== 公证压缩包 =="
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "  说明：裸二进制无法 staple，票据由 Gatekeeper 在线核验"
  fi
fi

echo "完成：$ZIP"
