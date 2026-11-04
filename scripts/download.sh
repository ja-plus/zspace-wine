#!/usr/bin/env bash
# 把官方 Windows 安装包放进 packages/。
#
#   scripts/download.sh                 # 下载官方最新版（自动解析版本与地址）
#   scripts/download.sh --force         # 已存在也重新下载
#   scripts/download.sh --url <地址>    # 指定下载地址
#   scripts/download.sh --file <路径>   # 手动下载好的 exe，拷入 packages/（推荐离线场景）
#
# 退出码：0 成功；1 失败。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

FORCE=0; URL=""; FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --force)   FORCE=1; shift ;;
        --url)     URL="${2:?--url 需要地址}"; shift 2 ;;
        --file|-f) FILE="${2:?--file 需要路径}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) die "未知参数：$1" ;;
    esac
done

need curl
need python3

# ── 手动导入 ───────────────────────────────────────────────────
if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || die "找不到文件：$FILE"
    base="$(basename "$FILE")"
    case "$base" in
        *.exe) ;;
        *) die "不是 .exe：$base" ;;
    esac
    head -c 2 "$FILE" | grep -q 'MZ' || die "$base 不是有效的 Windows 可执行文件（缺少 MZ 头）"
    dest="$PKG_DIR/$base"
    if [ -e "$dest" ] && [ "$FORCE" = 0 ]; then
        ok "已存在，跳过：$base"
    else
        info "拷入 packages/：$base"
        cp -f "$FILE" "$dest"
    fi
    ok "本地包就绪：$dest"
    echo "LOCAL_FILE=$dest"
    echo "PACKAGE_SIZE=$(stat -c%s "$dest")"
    exit 0
fi

# ── 自动下载 ───────────────────────────────────────────────────
if [ -z "$URL" ]; then
    info "解析官方最新版本…"
    # 复用每日缓存；--force 时同时刷新
    if [ "$FORCE" = 1 ]; then
        out="$("$ROOT/scripts/check_update.sh" --force --quiet)" || die "获取版本信息失败"
    else
        out="$("$ROOT/scripts/check_update.sh" --quiet)" || die "获取版本信息失败"
    fi
    eval "$out"
    URL="$DOWNLOAD_URL"
    [ -n "$URL" ] || die "接口没有返回下载地址"
    [ "${STATUS:-}" != "no-package" ] || true
    info "目标版本：${LATEST_VERSION:-未知}（$(human_size "${PACKAGE_SIZE:-0}")）"

    # 已有同版本包且未 --force
    if [ "$(strip_v "${LOCAL_VERSION:-}")" = "$(strip_v "${LATEST_VERSION:-}")" ] && [ "$FORCE" = 0 ]; then
        ok "本地已是该版本（${LOCAL_VERSION:-?}），无需下载（要覆盖请加 --force）"
        echo "LOCAL_FILE=$LOCAL_FILE"
        exit 0
    fi
fi

base="$(basename "${URL%%\?*}")"
[ -n "$base" ] || base="zspace_windows_download.exe"
case "$base" in *.exe) ;; *) base="$base.exe" ;; esac
dest="$PKG_DIR/$base"
part="$dest.part"

info "下载：$URL"
info "目标：$dest"
curl -fL --connect-timeout 20 --retry 3 --retry-delay 3 -C - -o "$part" "$URL" \
    || die "下载失败。可以用浏览器手动下载后执行：scripts/download.sh --file <exe>"

# ── 校验 ───────────────────────────────────────────────────────
[ -s "$part" ] || die "下载结果为空"
head -c 2 "$part" | grep -q 'MZ' || die "下载到的不是 Windows 可执行文件（缺少 MZ 头）"

got=$(stat -c%s "$part")
if [ -n "${PACKAGE_SIZE:-}" ] && [ "${PACKAGE_SIZE:-}" != "0" ]; then
    if [ "$got" != "$PACKAGE_SIZE" ]; then
        warn "体积不符：预期 $PACKAGE_SIZE，实际 $got（可能是断点续传残留，删除重下）"
        rm -f "$part"
        die "请加 --force 重新下载"
    fi
fi

mv -f "$part" "$dest"
ok "下载完成：$(basename "$dest")（$(human_size "$got")）"
echo "LOCAL_FILE=$dest"
echo "PACKAGE_SIZE=$got"
echo "LATEST_VERSION=${LATEST_VERSION:-unknown}"
