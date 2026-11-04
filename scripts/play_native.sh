#!/bin/bash
# play_native.sh —— 用 Linux 原生播放器播极空间当前视频（走 VA-API 硬解）
#
# 为什么需要它：
#   极空间客户端的播放器是 Windows 版 VLC 跑在 Wine 里。Wine 没有 GPU 解码后端
#   （全部模块都不链接 libva），强制 avcodec-hw=d3d11va 实测 CPU 从 329% 涨到 426%，
#   画面还大量掉帧 —— 那条路已封死，见 .agents/memory.md 2026-11-04 记录。
#   而本机 Linux 侧的 VA-API 是好的（iHD 驱动 + /dev/dri/renderD128），
#   把同一个流交给原生播放器走硬解，4K HEVC 原盘不用再看它掉帧。
#
# 用法：
#   scripts/play_native.sh                # 自动抓客户端最近一次播放的地址
#   scripts/play_native.sh --list         # 只列出抓到的地址，不播放
#   scripts/play_native.sh --url <URL>    # 手动指定地址
#   scripts/play_native.sh --software     # 强制软解（对比用）
#
# 前提：极空间客户端必须在运行 —— 播放地址是它内置代理
#       http://127.0.0.1:13579 下的临时路径，客户端退出就用不了。

set -uo pipefail

LOGDIR="$HOME/.deepinwine/com.zspace.spark/drive_c/users/$USER/AppData/Roaming/zspace/logs"
LOG_MAIN="$LOGDIR/main.log"
LOG_PLAYER="$LOGDIR/player.log"
PROXY="http://127.0.0.1:13579"

URL=""
MODE="play"

while [ $# -gt 0 ]; do
    case "$1" in
        --url)      URL="${2:-}"; shift 2 ;;
        --list)     MODE="list"; shift ;;
        --software) MODE="software"; shift ;;
        -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          URL="$1"; shift ;;
    esac
done

die() { echo "错误：$1" >&2; exit 1; }

# 客户端没起来时，13579 上什么都没有，地址必然失效
if ! ss -tln 2>/dev/null | grep -q '127.0.0.1:13579'; then
    die "极空间客户端没在运行。先打开客户端并播放任意视频，再执行本脚本。"
fi

if [ -z "$URL" ]; then
    # 日志里同时有字幕(.ass)和视频(.mkv/.mp4/.ts)，只取视频
    URL=$(grep -hoE "${PROXY}/splay/[^\"' ]+\.(mkv|mp4|ts|avi|mov|m2ts)" \
              "$LOG_MAIN" "$LOG_PLAYER" 2>/dev/null | tail -1)
    [ -z "$URL" ] || URL=$(grep -hoE "${PROXY}/splay/[^\"' ]+" "$LOG_MAIN" "$LOG_PLAYER" 2>/dev/null \
              | grep -viE '\.(ass|srt|ssa|sub)$' | tail -1)
fi

[ -n "$URL" ] || die "日志里找不到播放地址。先在客户端里点开一个视频，再执行本脚本。"

# 实测地址是否还能用（临时 token 会过期）
CODE=$(curl -s -m 5 -r 0-1 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null)
case "$CODE" in
    200|206) ;;
    *) die "地址已失效（HTTP $CODE）。客户端重新播放一次，token 会刷新。" ;;
esac

if [ "$MODE" = "list" ]; then
    echo "$URL"
    exit 0
fi

echo "流地址：$URL"

# 播放器优先级：mpv（零拷贝硬解）> ffplay（能用但体验差）
if command -v mpv >/dev/null 2>&1; then
    if [ "$MODE" = "software" ]; then
        echo "播放器：mpv（--hwdec=no 软解，用于对比）"
        exec mpv --hwdec=no --vo=gpu --force-window=yes "$URL"
    fi
    echo "播放器：mpv（VA-API 硬解）"
    exec mpv --hwdec=vaapi --vo=gpu --force-window=yes \
             --hwdec-codecs=all --gpu-api=opengl "$URL"
elif command -v ffplay >/dev/null 2>&1; then
    if [ "$MODE" = "software" ]; then
        echo "播放器：ffplay（软解，用于对比）"
        exec ffplay -autoexit -window_title "极空间(软解)" "$URL"
    fi
    echo "播放器：ffplay（VA-API 硬解）"
    echo "提示：装上 mpv 体验和 CPU 都会更好：sudo apt install mpv"
    exec ffplay -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
                -autoexit -window_title "极空间(硬解)" "$URL"
else
    die "系统里没有 mpv 也没有 ffplay。装一个：sudo apt install mpv"
fi
