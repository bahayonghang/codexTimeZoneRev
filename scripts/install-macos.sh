#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="${1:-$project_root/flutter_app/build/macos/Build/Products/Release/Codex 时区启动器.app}"
destination="${2:-$HOME/Applications/Codex 时区启动器.app}"

if [[ ! -d "$source_app" ]]; then
  printf '找不到 macOS Release 应用：%s\n请先运行 just build。\n' "$source_app" >&2
  exit 1
fi
if [[ ! -d "$source_app/Contents/MacOS" ]]; then
  printf 'macOS Release 应用结构不完整：%s\n' "$source_app" >&2
  exit 1
fi
if ! /usr/bin/codesign --verify --deep --strict "$source_app"; then
  printf 'macOS 应用签名校验失败：%s\n' "$source_app" >&2
  exit 1
fi

parent="$(dirname "$destination")"
mkdir -p "$parent"
stage="$(mktemp -d "$parent/.CodexTimeZoneLauncher-install.XXXXXX")"
next="$stage/next.app"
previous="$stage/previous.app"
failed="$stage/failed.app"
old_moved=0
new_installed=0
committed=0

cleanup() {
  status=$?
  trap - EXIT
  if [[ "$committed" -ne 1 ]]; then
    if [[ "$new_installed" -eq 1 && -e "$destination" ]]; then
      mv "$destination" "$failed" || status=1
    fi
    if [[ "$old_moved" -eq 1 && -e "$previous" ]]; then
      mv "$previous" "$destination" || status=1
    fi
  fi
  rm -rf "$stage"
  exit "$status"
}
trap cleanup EXIT

/usr/bin/ditto "$source_app" "$next"
if ! /usr/bin/codesign --verify --deep --strict "$next"; then
  printf '暂存 macOS 应用签名校验失败。\n' >&2
  exit 1
fi

if [[ -e "$destination" ]]; then
  mv "$destination" "$previous"
  old_moved=1
fi
mv "$next" "$destination"
new_installed=1
if ! /usr/bin/codesign --verify --deep --strict "$destination"; then
  printf '安装后的 macOS 应用签名校验失败。\n' >&2
  exit 1
fi
committed=1
printf '已安装：%s\n' "$destination"
