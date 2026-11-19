#!/bin/bash
# 打一个可公证的 Release 包。
#
#   ./scripts/release.sh --dry-run        # 只到 .xcarchive，免证书
#   ./scripts/release.sh --version 0.2.0  # 正式：archive → export → notarize → staple
#
# 正式发布需要：
#   · Config/Local.xcconfig 里的开发者证书与 team
#   · 环境变量 NOTARY_PROFILE（notarytool 的 keychain profile）
#   · 系统代理已关（codesign 取时间戳走网络，代理会 502）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
ALLOW_PROXY=0
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --allow-proxy) ALLOW_PROXY=1 ;;
    --version) shift; VERSION="${1:-}" ;;
    *) echo "未知参数：$1"; exit 2 ;;
  esac
  shift
done

if [ -z "$VERSION" ]; then
  VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
fi
if [ -z "$VERSION" ]; then
  echo "读不到版本号；用 --version 指定"
  exit 2
fi
echo "版本：$VERSION"

# 代理预检：codesign 的时间戳服务对代理很敏感。
PROXY_ON="$(scutil --proxy 2>/dev/null | grep -E 'HTTPEnable : 1|HTTPSEnable : 1|SOCKSEnable : 1' || true)"
if [ -n "$PROXY_ON" ] && [ "$ALLOW_PROXY" -eq 0 ]; then
  echo "系统代理开着，公证/签名可能 502。先关代理，或加 --allow-proxy。"
  echo "$PROXY_ON"
  exit 1
fi

echo "== 生成 Xcode 工程 =="
xcodegen generate >/dev/null

ARCHIVE="build/Causality-$VERSION.xcarchive"
rm -rf "$ARCHIVE"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "== 演练：只到 archive（不签名、不公证）=="
  xcodebuild -project Causality.xcodeproj -scheme Causality \
    -configuration Release -destination 'platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO archive | tail -5
  echo "演练完成：$ARCHIVE"
  exit 0
fi

if [ ! -f Config/Local.xcconfig ]; then
  echo "缺少 Config/Local.xcconfig：开发者证书与 team 从它读。"
  exit 1
fi
# xcconfig 里写的 DEVELOPMENT_TEAM 不一定能覆盖到 target，显式传给 xcodebuild。
TEAM="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Za-z0-9]+).*/\1/p' Config/Local.xcconfig | head -1)"
SIGN_ARGS=()
if [ -n "$TEAM" ]; then
  SIGN_ARGS+=("DEVELOPMENT_TEAM=$TEAM")
fi
if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "缺少 NOTARY_PROFILE：先 xcrun notarytool store-credentials 建一个。"
  exit 1
fi

echo "== archive =="
xcodebuild -project Causality.xcodeproj -scheme Causality \
  -configuration Release -destination 'platform=macOS' \
  -archivePath "$ARCHIVE" "${SIGN_ARGS[@]}" archive | tail -5

EXPORT_DIR="build/export-$VERSION"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "== export =="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" | tail -5

APP="$EXPORT_DIR/Causality.app"
if [ ! -d "$APP" ]; then
  echo "导出里没有 Causality.app：$EXPORT_DIR"
  exit 1
fi

# ---------- 内嵌命令行 ----------
# 用户装完 App 就自带 causal（MCP 服务器），菜单「工具 › 安装命令行工具」一键装到 ~/.local/bin。
echo "== 内嵌命令行 =="
(cd Packages/CausalityCore && swift build -c release --product causal --arch arm64 --arch x86_64)
CLI_RES="$APP/Contents/Resources/cli"
mkdir -p "$CLI_RES"
cp "Packages/CausalityCore/.build/release/causal" "$CLI_RES/causal"
cp -R "Packages/CausalityCore/.build/release/CausalityCore_CausalityCore.bundle" "$CLI_RES/"
codesign --force --options runtime --timestamp --sign "Developer ID Application" "$CLI_RES/causal"
# App 内容变了，必须重签 App 本体，公证才针对最终产物
codesign --force --options runtime --timestamp --sign "Developer ID Application" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
echo "  已内嵌：Contents/Resources/cli/causal（$(lipo -archs "$CLI_RES/causal")）"
ZIP="build/Causality-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "== notarize app =="
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo "完成：${ZIP}（已公证、已 staple）"

# ---------- DMG ----------
# 装窗口里只有一个 App 和 Applications 软链：用户拖进去就装完。
DMG="build/Causality-$VERSION.dmg"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "== dmg =="
hdiutil create -quiet -volname "Causality $VERSION" \
  -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

echo "== notarize dmg =="
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "== verify =="
spctl -a -vvv --type execute "$APP"
spctl -a -vvv --type open --context context:primary-signature "$DMG"

# ---------- CLI（给 MCP 客户端用）----------
# App 里不含命令行；MCP 服务器是单独的 causal，随 Release 一起发。
echo "== cli =="
"$ROOT/scripts/package-cli.sh" "$VERSION" --notarize

echo "完成：${DMG}（App 与 DMG 均已公证、已 staple）；CLI 见 build/causal-${VERSION}-macos.zip"
