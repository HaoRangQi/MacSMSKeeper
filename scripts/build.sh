#!/usr/bin/env bash
#
# 短信管家 · 构建脚本
#
# 不依赖 Xcode 工程，直接用 swiftc 编译 SwiftUI 应用并组装 .app。
# 需要 Command Line Tools（提供 Swift 工具链与 macOS SDK）。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="短信管家"
BUNDLE="$ROOT/build/$APP_NAME.app"
BIN="$BUNDLE/Contents/MacOS/SMSKeeper"
TARGET_ARCH="${TARGET_ARCH:-arm64}"
MIN_MACOS="${MIN_MACOS:-26.0}"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: 找不到 swiftc，请先安装 Xcode Command Line Tools" >&2
    echo "       xcode-select --install" >&2
    exit 1
fi

echo "==> 清理旧产物"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> 编译 Swift（target ${TARGET_ARCH}-apple-macosx${MIN_MACOS}）"
# macOS 自带 bash 3.2，没有 mapfile，用 while 读入数组（路径含空格也安全）
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources" -name '*.swift' | sort)
if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "error: Sources 目录下没有找到 .swift 文件" >&2
    exit 1
fi

swiftc -O \
    -parse-as-library \
    -target "${TARGET_ARCH}-apple-macosx${MIN_MACOS}" \
    -framework AppKit -framework SwiftUI \
    "${SOURCES[@]}" \
    -o "$BIN"

echo "==> 组装 App Bundle"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "==> 完成：$BUNDLE"
