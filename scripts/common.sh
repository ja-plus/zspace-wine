#!/usr/bin/env bash
# 极空间 Wine 打包项目 —— 公共函数
# 所有脚本 source 本文件，不要在脚本之间重复定义。

set -euo pipefail

# 项目根目录（scripts/ 的上一级）
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT/.state"
PKG_DIR="$ROOT/packages"
BUILD_DIR="$ROOT/build"
LOG_DIR="$ROOT/logs"
PACK_DIR="$ROOT/packaging"

mkdir -p "$STATE_DIR" "$PKG_DIR" "$BUILD_DIR" "$LOG_DIR"

# ── 官方接口（来源见 .agents/sources.md）────────────────────────
API_BASE="https://upgrade.zenithspace.net/upgrade_server/v2/check_upgrade"
APP_ID="APP_ZSPACE_DESKTOP_WIN"
CHANNEL="zspace"
# Win7 兼容版另有 APP_ZSPACE_DESKTOP_WIN7，本项目默认不做

# ── 输出 ────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
    C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi

info()  { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn()  { printf '%s警告%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
err()   { printf '%s错误%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
die()   { err "$*"; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "缺少依赖：$1"
}

# ── 版本比较：V2.46.2026101501 → 逐段数值比较 ──────────────────
# 用法：version_gt A B   （A > B 时返回 0）
version_gt() {
    python3 - "$1" "$2" <<'PY'
import sys
def norm(v):
    v = v.lstrip('Vv')
    return [int(x) if x.isdigit() else 0 for x in v.split('.')]
a, b = norm(sys.argv[1]), norm(sys.argv[2])
n = max(len(a), len(b))
a += [0]*(n-len(a)); b += [0]*(n-len(b))
sys.exit(0 if a > b else 1)
PY
}

# ── 本地已有的安装包 ───────────────────────────────────────────
# 打印「版本|文件名」，多份时取版本最高的一份；没有则非零退出
local_package() {
    local best="" bestv="" f v
    shopt -s nullglob
    for f in "$PKG_DIR"/*.exe; do
        v="$(basename "$f" | sed -nE 's/^zspace_windows_([0-9][0-9.]*)_[0-9]+\.exe$/\1/p')"
        [ -z "$v" ] && v="$(basename "$f" .exe)"
        if [ -z "$bestv" ] || version_gt "$v" "$bestv"; then
            bestv="$v"; best="$f"
        fi
    done
    shopt -u nullglob
    [ -n "$best" ] || return 1
    printf '%s|%s\n' "$bestv" "$best"
}

human_size() {
    python3 - "$1" <<'PY'
import sys
n = int(sys.argv[1])
for u in ('B','KB','MB','GB'):
    if n < 1024 or u == 'GB':
        print(f"{n:.1f} {u}" if u != 'B' else f"{n} B"); break
    n /= 1024
PY
}

# 去掉版本号开头的 V/v，便于直接字符串比较
strip_v() {
    local v="$1"
    printf '%s\n' "${v#[Vv]}"
}

# 递归删除目录。
# 1) 部分受限 shell 里 rm 被替换成受控实现，会拒绝 rm -rf；
# 2) set -e 下不能写成「[ -e ] && warn」——目录已删时它返回 1 会中止脚本。
remove_dir() {
    local d
    for d in "$@"; do
        [ -e "$d" ] || continue
        if ! rm -rf "$d" 2>/dev/null; then
            python3 - "$d" 2>>"$LOG_DIR/remove-dir.log" <<'PY' || true
import shutil, sys
target = sys.argv[1]
try:
    shutil.rmtree(target)
    print("removed", target)
except Exception as e:
    print("failed", target, repr(e))
PY
        fi
        if [ -e "$d" ]; then
            warn "无法删除目录：$d"
            return 1
        fi
    done
    return 0
}

# 列出目录下非 ASCII 文件名（星火要求包内文件名无中文）
non_ascii_names() {
    python3 - "$1" <<'PY'
import os, sys
root = sys.argv[1]
for dirpath, dirnames, filenames in os.walk(root):
    for n in filenames + dirnames:
        try:
            n.encode('ascii')
        except UnicodeEncodeError:
            print(os.path.join(dirpath, n))
PY
}
