#!/bin/bash
# Installs the built app into ~/Applications.
#
# Replacing an existing bundle has to move the old one out of the way first: `cp -R`
# onto an existing .app copies the new bundle *inside* the old one, which leaves a
# broken app that still launches with the old code. The old copy is moved to the Trash
# rather than deleted, so it can be recovered.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/build/重要待办.app"
DEST="$HOME/Applications/重要待办.app"
# The card used to be called 今日打卡; the old copy has to go, or Spotlight shows two.
LEGACY="$HOME/Applications/今日打卡.app"

if [[ ! -d "$SOURCE" ]]; then
  echo "还没有编译过：先运行 ./build.sh" >&2
  exit 1
fi

mkdir -p "$HOME/Applications"

if [[ -e "$DEST" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$HOME/.Trash"
  mv "$DEST" "$HOME/.Trash/重要待办-旧版本-$STAMP.app"
  echo "旧版本已移到废纸篓：重要待办-旧版本-$STAMP.app"
fi

if [[ -e "$LEGACY" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$HOME/.Trash"
  mv "$LEGACY" "$HOME/.Trash/今日打卡-改名前-$STAMP.app"
  echo "改名前的老版本已移到废纸篓：今日打卡-改名前-$STAMP.app"
fi

cp -R "$SOURCE" "$DEST"
codesign --force --sign - "$DEST" >/dev/null 2>&1 || true

echo "已安装：$DEST"
echo "打开方式：open \"$DEST\"   或用聚焦搜索输入 重要待办"
echo "全局快捷键：⌥⌘T 呼出 / 收起"
