#!/bin/bash
# 把 CausalityCore 里的权威词条表同步回 App 目标。
#
# App 界面文案走 SwiftUI 的 LocalizedStringKey，从 `Sources/Causality/*.lproj` 取；
# 唯一权威副本在 `Packages/CausalityCore/Sources/CausalityCore/Resources/`。
# 改词条只改权威副本，再跑这条脚本；脚本可反复执行。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Packages/CausalityCore/Sources/CausalityCore/Resources"
TARGET="$ROOT/Sources/Causality"

changed=0
for language in zh-Hans en ja zh-Hant; do
  src="$SOURCE/$language.lproj/Localizable.strings"
  dst="$TARGET/$language.lproj/Localizable.strings"
  if [ ! -f "$src" ]; then
    echo "缺少权威词条表：$src" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  if cmp -s "$src" "$dst"; then
    :
  else
    cp "$src" "$dst"
    changed=$((changed + 1))
    echo "已同步 $language.lproj"
  fi

  # 复数规则只在英文有；其他语言没有这份文件就不管。
  srcdict="$SOURCE/$language.lproj/Localizable.stringsdict"
  dstdict="$TARGET/$language.lproj/Localizable.stringsdict"
  if [ -f "$srcdict" ]; then
    if cmp -s "$srcdict" "$dstdict"; then
      :
    else
      cp "$srcdict" "$dstdict"
      changed=$((changed + 1))
      echo "已同步 $language.lproj 的复数规则"
    fi
  fi
done

if [ "$changed" -eq 0 ]; then
  echo "词条表已是最新"
fi
