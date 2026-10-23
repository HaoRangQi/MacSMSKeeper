#!/usr/bin/env bash
#
# 本地一键发版：./scripts/release.sh 1.1.0
#
# 做四件事：本地化检查 → 自检 → 打包 → 打 tag 推送 → 创建 Release 上传附件。
# 不需要 gh CLI，凭据从 git credential helper（macOS Keychain）取。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PRODUCT="MacSMSKeeper"
BOLD="\033[1m"; DIM="\033[2m"; RED="\033[31m"; GREEN="\033[32m"; NC="\033[0m"
say()  { printf "${BOLD}==>${NC} %s\n" "$*"; }
die()  { printf "${RED}error:${NC} %s\n" "$*" >&2; exit 1; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "用法: $0 <版本号>   例如: $0 1.1.0"
TAG="v$VERSION"
ZIP="$ROOT/dist/${PRODUCT}-v${VERSION}-macos26.zip"
NOTES="$(mktemp)"; trap 'rm -f "$NOTES"' EXIT

# ------------------------------------------------- 0. 换机器也能一次跑通的前置检查
say "检查工具链"
require() {
    command -v "$1" >/dev/null 2>&1 && return 0
    shift
    die "缺少命令 $1" "${2:-安装 Command Line Tools：xcode-select --install}"
}
require git git "macOS 自带"
require make make "安装 Command Line Tools：xcode-select --install"
require python3 python3 "安装 Command Line Tools：xcode-select --install"
require xcrun xcrun "安装 Command Line Tools：xcode-select --install"
require swiftc swiftc "安装 Command Line Tools：xcode-select --install"
require ditto ditto "macOS 自带"

SDK_VER="$(xcrun --show-sdk-version 2>/dev/null || echo 0)"
SDK_MAJOR="${SDK_VER%%.*}"
if [ "${SDK_MAJOR:-0}" -lt 26 ]; then
    # 注意用 ${SDK_VER} 花括号形式：$SDK_VER， 里的全角逗号会被 bash
    # 当作变量名的一部分，导致 "unbound variable"
    die "当前 macOS SDK 为 ${SDK_VER}，本项目要求 26+（用到 Liquid Glass）。请先升级系统。"
fi
printf "    macOS SDK %s · 工具链就绪\n" "$SDK_VER"

# ---------------------------------------------------------------- 1. 前置检查
say "检查工作区"
[ -z "$(git status --porcelain)" ] || die "有未提交改动，先 commit 再发版"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
printf "    分支 %s · 版本 %s\n" "$BRANCH" "$TAG"

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    && die "tag $TAG 已存在，换个版本号"

say "本地化检查"
python3 scripts/check-localization.py

# 先验证凭据再花几分钟构建，失败要早失败
say "检查 GitHub 凭据"
python3 scripts/gh-release.py --check

# ---------------------------------------------------------------- 2. 构建
say "自检"
make selftest

say "打包"
make dist VERSION="$VERSION"
[ -f "$ZIP" ] || die "找不到 $ZIP"

# ---------------------------------------------------------------- 3. 推送代码与 tag
say "推送代码与 tag"
git push origin "$BRANCH" 2>&1 || die "推送代码失败。新机器上第一次推送需要登录：按提示输入 GitHub 用户名和 Personal Access Token（需要 repo 权限）"
git tag -a "$TAG" -m "$PRODUCT $VERSION"
git push origin "$TAG" 2>&1 || die "推送 tag 失败，请检查网络与凭据"

# ---------------------------------------------------------------- 4. 发布
say "创建 Release 并上传附件"
python3 scripts/changelog-section.py "$VERSION" > "$NOTES" 2>/dev/null \
    || printf "短信管家 %s\n" "$VERSION" > "$NOTES"

python3 scripts/gh-release.py "$TAG" "$PRODUCT $VERSION" "$NOTES" "$ZIP"

printf "\n${GREEN}完成${NC} %s 已发布\n" "$TAG"
