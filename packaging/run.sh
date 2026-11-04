#!/bin/bash
# 极空间 (Wine 版) — 启动器
# 遵循 deepin-wine 容器约定：容器位于 ~/.deepinwine/<BOTTLENAME>

BOTTLENAME="com.zspace.spark"
APPDIR="/opt/durapps/com.zspace.spark/files"
export WINEPREFIX="$HOME/.deepinwine/$BOTTLENAME"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
# Chromium 沙箱在 Wine 下无法工作，该应用又拒绝命令行 --no-sandbox，只能走环境变量
export ELECTRON_DISABLE_SANDBOX=1

# 防御：NODE_OPTIONS / ELECTRON_RUN_AS_NODE 会被 Wine 透传进容器，
# 让 Electron 以纯 Node 模式启动并立刻崩溃（表现为「点了没反应」）
unset NODE_OPTIONS ELECTRON_RUN_AS_NODE ELECTRON_NO_ATTACH_CONSOLE NODE_PATH

# 强制走 XWayland：Wine 11 默认启用 wayland 驱动，而 treeland 等合成器缺少
# xdg_toplevel_icon_manager_v1 / ext_foreign_toplevel_list_v1，会导致窗口创建失败
unset WAYLAND_DISPLAY

TARGET_DIR="$WINEPREFIX/drive_c/Program Files/zspace"

# 通知必须在后台执行：任何前台的 zenity/notify 都可能阻塞主流程
notify() {
    { notify-send -i com.zspace.spark -t 4000 "极空间" "$1" >/dev/null 2>&1 || \
      zenity --info --title="极空间" --text="$1" >/dev/null 2>&1; } &
    echo "极空间: $1" >&2
}

# 致命错误：提示放后台，绝不阻塞退出
die() {
    echo "极空间: $1" >&2
    { zenity --error --title="极空间" --text="$1" >/dev/null 2>&1 & } 2>/dev/null
    exit 1
}

# ════════════════════════════════════════════════════════════════
# 中文字体修正
# ----------------------------------------------------------------
# 应用 CSS 的字体栈是：
#   PingFang SC, Source Han Sans CN, WenQuanYi Micro Hei, Microsoft YaHei, sans-serif
# 在 Windows 上前两项不存在，最终落到微软雅黑；而 Linux 桌面普遍装有
# 文泉驿微米黑，Wine 会让 Chromium 优先命中它 —— 中文笔画偏细、西文字宽偏窄，
# 与官方 Windows 客户端观感不一致（表现为「字体不太对」）。
#
# 处理办法：给本应用的 Wine 进程单独注入一份 fontconfig 配置，
# 其 <dir> 列表不含文泉驿目录，这样该字体根本不会进入字体库，
# Chromium 直接跳到字体栈第四项微软雅黑。
#
# 两个走不通的路子（已实测）：
#   · fontconfig 的 <rejectfont> 对 Wine 无效，因为 Wine 直接取目录扫描结果；
#   · Wine 的字体替换表 HKCU\Software\Wine\Fonts\Replacements 不作用于 DirectWrite。
# ════════════════════════════════════════════════════════════════
ZC_FONT_CONF="$WINEPREFIX/fontconfig.conf"

# 只有系统里确实有微软雅黑才动手；否则保留发行版自带的中文字体
zc_have_yahui() {
    fc-list 2>/dev/null | grep -qi 'Microsoft YaHei'
}

zc_build_font_conf() {
    local root d tmp
    tmp="$ZC_FONT_CONF.dirs"
    : > "$tmp" 2>/dev/null
    {
        for root in /usr/share/fonts /usr/local/share/fonts \
                    "$HOME/.local/share/fonts" "$HOME/.fonts"; do
            [ -d "$root" ] || continue
            find "$root" -type d 2>/dev/null | while IFS= read -r d; do
                # 文泉驿目录及其子目录一律不收
                case "$d" in */wqy|*/wqy/*) continue ;; esac
                # 只收「直接放着字体文件」或「叶子目录」的路径：
                # fontconfig 的 <dir> 是递归的，若收上层目录会把文泉驿又带回来
                if ls "$d"/*.ttf "$d"/*.ttc "$d"/*.otf "$d"/*.otc \
                      "$d"/*.pfb "$d"/*.pfa >/dev/null 2>&1 || \
                   [ -z "$(find "$d" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)" ]; then
                    printf '%s\n' "$d"
                fi
            done
        done
    } | LC_ALL=C sort -u > "$tmp" 2>/dev/null

    {
        printf '%s\n' \
            '<?xml version="1.0"?>' \
            '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">' \
            '<!-- 极空间 Wine 版专用：沿用发行版规则，但字体目录剔除文泉驿微米黑 -->' \
            '<fontconfig>' \
            '  <cachedir>/var/cache/fontconfig</cachedir>' \
            '  <cachedir prefix="xdg">fontconfig</cachedir>' \
            '  <include ignore_missing="yes">/etc/fonts/conf.d</include>'
        while IFS= read -r d; do
            [ -n "$d" ] && printf '  <dir>%s</dir>\n' "$d"
        done < "$tmp"
        printf '%s\n' '</fontconfig>'
    } > "$ZC_FONT_CONF" 2>/dev/null
    rm -f "$tmp"
}

zc_setup_fonts() {
    zc_have_yahui || return 0
    mkdir -p "$WINEPREFIX" 2>/dev/null
    [ -s "$ZC_FONT_CONF" ] || zc_build_font_conf
    [ -s "$ZC_FONT_CONF" ] || return 0
    export FONTCONFIG_FILE="$ZC_FONT_CONF"
}

# 本次修正之前创建的老容器，注册表里已经写死了文泉驿字体条目，
# Wine 不会主动删除，必须手工清掉，否则上面设的 fontconfig 不生效。
# 幂等：没有可清的就直接返回。
zc_strip_wqy_fonts() {
    local f tmp need=0
    for f in "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg"; do
        [ -f "$f" ] || continue
        LC_ALL=C grep -q 'wqy-microhei' "$f" 2>/dev/null && need=1
    done
    [ "$need" = 0 ] && return 0

    # 必须先让本容器的 wineserver 退出：它退出时会把内存里的旧注册表写回文件，
    # 把刚删掉的条目又覆盖回来（刚关掉应用就立刻再点开时最容易踩到）
    if [ -n "$ZC_WINESERVER" ]; then
        WINEPREFIX="$WINEPREFIX" "$ZC_WINESERVER" -k >/dev/null 2>&1
        sleep 2
    fi

    for f in "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg"; do
        [ -f "$f" ] || continue
        LC_ALL=C grep -q 'wqy-microhei' "$f" 2>/dev/null || continue
        tmp="$f.zctmp"
        if LC_ALL=C grep -v 'wqy-microhei' "$f" > "$tmp" 2>/dev/null; then
            mv -f "$tmp" "$f"
        else
            rm -f "$tmp"
        fi
    done
}

# 找到**本运行时配套的** wineserver。
# 不能先猜 /opt/deepin-wine*：机器上同时装了普通 wine 时会拿到另一套，
# 报 version mismatch（933/891 之类）。必须从实际选中的 wine 往回推。
zc_find_wineserver() {
    local real dir
    real="$(command -v "$WINE_CMD" 2>/dev/null)" || return 1

    # 包装脚本（deepin-wine10-stable 之类）只是 exec 了真正的 wine，
    # wineserver 在那个 wine 旁边，不在包装脚本旁边
    if head -1 "$real" 2>/dev/null | grep -q '^#!'; then
        dir="$(grep -oE '/[^ ]*/bin/wine' "$real" 2>/dev/null | head -1)"
        dir="${dir%/wine}"
        if [ -n "$dir" ] && [ -x "$dir/wineserver" ]; then
            printf '%s' "$dir/wineserver"; return 0
        fi
    fi

    # 依次看：命令所在目录、symlink 解析后的真实目录
    for dir in "$(dirname "$real")" \
               "$(dirname "$(readlink -f "$real" 2>/dev/null)")"; do
        [ -n "$dir" ] && [ -x "$dir/wineserver" ] && { printf '%s' "$dir/wineserver"; return 0; }
    done

    # 兜底故意不猜 /opt/deepin-wine*：
    # 机器上同时装了两种 wine 时，猜错会把另一套的 wineserver 杀掉，
    # 报 version mismatch。找不到配套的就返回失败，让调用方跳过 kill。
    return 1
}

# 运行时选择：deepin-wine 优先（中文/输入法等兼容性最好），
# 没有就退到发行版自带的 wine。可用 WINE 环境变量强制指定。
WINE_CMD=""
if [ -n "${WINE:-}" ]; then
    if command -v "$WINE" >/dev/null 2>&1; then
        WINE_CMD="$WINE"
    else
        die "环境变量 WINE 指定的运行时不存在：$WINE"
    fi
else
    for w in deepin-wine10-stable deepin-wine11-stable deepin-wine8-stable deepin-wine \
             wine64 wine wine-stable; do
        if command -v "$w" >/dev/null 2>&1; then WINE_CMD="$w"; break; fi
    done
fi
[ -z "$WINE_CMD" ] && die "未找到 Wine 运行时。请安装 deepin-wine10-stable（推荐）或发行版自带的 wine；也可用 WINE=<命令> 指定"

ZC_WINESERVER=$(zc_find_wineserver)

# 必须在 wineboot 之前设置，首次初始化时就不会把文泉驿注册进容器
zc_setup_fonts

# 已有实例在跑：直接返回（该应用不支持多开）
if pgrep -f "极空间\.exe" >/dev/null 2>&1; then
    exit 0
fi

# 容器是否可用：注册表已落盘 + system32 存在 + Program Files 可写
bottle_ok() {
    [ -s "$WINEPREFIX/system.reg" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ]
}

# wineboot 之后 wineserver 仍在后台写注册表，必须轮询等待，不能立刻判定失败
wait_bottle() {
    local i
    for i in $(seq 1 150); do
        bottle_ok && return 0
        sleep 1
    done
    return 1
}

if ! bottle_ok; then
    notify "首次启动，正在初始化运行环境（约 1 分钟），请稍候…"
    # 半成品容器会让 wineboot 反复失败，先清掉
    if [ -d "$WINEPREFIX" ] && [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
        rm -rf "$WINEPREFIX"
        zc_setup_fonts
    fi
    # 清掉可能残留的旧 wineserver（跨版本会报 version mismatch）
    [ -n "$ZC_WINESERVER" ] && WINEPREFIX="$WINEPREFIX" "$ZC_WINESERVER" -k >/dev/null 2>&1
    sleep 2

    "$WINE_CMD" wineboot -u >/dev/null 2>&1
    if ! wait_bottle; then
        # 再给一次机会：重启 wineboot
        [ -n "$ZC_WINESERVER" ] && WINEPREFIX="$WINEPREFIX" "$ZC_WINESERVER" -k >/dev/null 2>&1
        sleep 2
        "$WINE_CMD" wineboot -u >/dev/null 2>&1
        wait_bottle || die "初始化 Wine 容器失败。请手动执行：WINEPREFIX=\"$WINEPREFIX\" $WINE_CMD wineboot -u"
    fi
fi

# 清掉老容器里遗留的文泉驿字体注册（必要时会先让本容器的 wineserver 退出）
zc_strip_wqy_fonts

if [ ! -d "$TARGET_DIR" ]; then
    notify "正在释放程序文件（约 850 MB），请稍候…"
    mkdir -p "$WINEPREFIX/drive_c/Program Files" || die "无法写入容器目录"
    cp -r "$APPDIR/app" "$TARGET_DIR" || die "释放程序文件失败，请检查磁盘空间（需约 1.5 GB 空闲）"
fi

notify "正在启动…"
exec "$WINE_CMD" "C:\\Program Files\\zspace\\极空间.exe" "$@"
