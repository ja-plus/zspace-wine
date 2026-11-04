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

# ════════════════════════════════════════════════════════════════
# 强制直连：清掉桌面会话里残留的代理环境变量
# ----------------------------------------------------------------
# 代理类工具（Watt Toolkit / Steam++、Clash、iKuuu 等）会往桌面会话注入
#   http_proxy / https_proxy / all_proxy
# 这些变量会被 Wine 原样透传进容器，Electron 主进程的 Node 侧（axios）会无条件走代理。
# 它们的 no_proxy 往往只有 10.*/172.16.*/192.168.* 而**不含 127.0.0.1**，
# 于是连极空间自己的本机服务也会被塞进代理：
#   127.0.0.1:13579  应用内置网页代理（AppStore / syncApi / healthcheck）
#   127.0.0.1:8384   syncthing 状态接口
# 代理一旦没在监听（工具退出、换端口、只开了 SOCKS），整台应用的网络就全挂：
#   main.log   → getLocalFoldersInfo error: ... connect ECONNREFUSED 127.0.0.1:7890
#   player.log → TcpRecvInfoShow {"show_info":"connect ECONNREFUSED 127.0.0.1:7890"}
#   界面表现   → 点开视频弹「connect ECONNREFUSED 127.0.0.1:7890」，同步/应用商店全部报错
# 注意：Chromium 侧读的是 Windows 系统代理（Wine 侧为直连），所以海报墙能正常显示，
#       只有主进程发出的请求会挂 —— 别被「界面能开」误导成网络本身没问题。
#
# 2026-11-04 实测（本机 gsettings 里 mode=none，但 host 仍是 127.0.0.1:7890）：
#   curl 直连 127.0.0.1:13579            → 302
#   同一请求加 http_proxy=…:7890         → curl exit 7（连接被拒）
#
# 极空间是局域网 NAS 客户端，本身不需要经过科学上网代理，直连是正确的默认行为。
# 想临时恢复继承来的代理：ZSPACE_KEEP_PROXY=1
# ════════════════════════════════════════════════════════════════
if [ "${ZSPACE_KEEP_PROXY:-0}" != "1" ]; then
    unset http_proxy https_proxy all_proxy ftp_proxy
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY FTP_PROXY
    # 兜底：万一有组件绕开上面的清理自行读系统代理，至少让本机与内网不经代理
    ZC_NO_PROXY="localhost,127.0.0.1,::1,10.*,172.16.*,172.17.*,172.18.*,172.19.*,172.20.*,172.21.*,172.22.*,172.23.*,172.24.*,172.25.*,172.26.*,172.27.*,172.28.*,172.29.*,172.30.*,172.31.*,192.168.*"
    export no_proxy="$ZC_NO_PROXY"
    export NO_PROXY="$ZC_NO_PROXY"
fi

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
# 2026-11-04 追查（看 CDP 的 CSS.getPlatformFontsForNode，别再靠猜）：
#   页面把字体栈写成了全角逗号 `"Microsoft YaHei，Arial，Verdana，sans-serif"`，
#   Chromium 当成一个字体名，必然找不到 → 走默认回退字体。
#   回退结果本来是 /usr/share/fonts/truetype/winfonts/NotoSansSC-VF.ttf，
#   这是个可变字体，Wine 取到的默认实例是 Thin/Light —— 这就是「字太细」的真凶。
#   把它从字体集里剔掉后，回退落到 Noto Sans CJK SC 常规字重，观感恢复正常。
#   注意：NotoSansSC-VF.ttf 和 msyh.ttc 同在 winfonts 目录，没法按目录排除，
#   只能建一个剔掉它的私有目录（ZC_FONT_DIR）让 Wine 扫，并清掉注册表残留条目。
#
# 走不通的路子（已实测，别再试）：
#   · fontconfig 的 <rejectfont>：fc-list 里确实没了，但 Wine 直接扫目录，照样注册回来；
#   · Wine 的字体替换表 HKCU\Software\Wine\Fonts\Replacements 不作用于 DirectWrite；
#   · 只清注册表不动字体集：Wine 每次启动重新扫目录，条目会再写回来。
# ════════════════════════════════════════════════════════════════
ZC_FONT_CONF="$WINEPREFIX/fontconfig.conf"
# 微软雅黑和「坏字体」NotoSansSC-VF.ttf 在同一个目录（/usr/share/fonts/truetype/winfonts），
# 没法按目录排除。Wine 又会无视 fontconfig 的 <rejectfont> 直接扫目录，
# 所以这里建一个只放干净字体的私有目录，让 Wine 只扫它。
ZC_FONT_DIR="$WINEPREFIX/fonts"

# 只有系统里确实有微软雅黑才动手；否则保留发行版自带的中文字体
zc_have_yahui() {
    fc-list 2>/dev/null | grep -qi 'Microsoft YaHei'
}

# 私有字体目录：winfonts 里除可变字体外的全部 Windows 字体（用软链接，不复制）
zc_build_font_dir() {
    local src=/usr/share/fonts/truetype/winfonts f
    [ -d "$src" ] || return 1
    mkdir -p "$ZC_FONT_DIR" 2>/dev/null || return 1
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        case "${f##*/}" in
            NotoSansSC-VF.ttf|NotoSerifSC-VF.ttf) continue ;;
        esac
        ln -sf "$f" "$ZC_FONT_DIR/${f##*/}" 2>/dev/null
    done
    # 彩色 emoji 单独从 noto 目录借一个（不借 CJK，避免又抢回回退位）
    [ -f /usr/share/fonts/truetype/noto/NotoColorEmoji.ttf ] && \
        ln -sf /usr/share/fonts/truetype/noto/NotoColorEmoji.ttf "$ZC_FONT_DIR/" 2>/dev/null
    return 0
}

zc_build_font_conf() {
    local root d tmp
    tmp="$ZC_FONT_CONF.dirs"
    : > "$tmp" 2>/dev/null
    zc_build_font_dir
    {
        for root in /usr/share/fonts /usr/local/share/fonts \
                    "$HOME/.local/share/fonts" "$HOME/.fonts"; do
            [ -d "$root" ] || continue
            find "$root" -type d 2>/dev/null | while IFS= read -r d; do
                # 文泉驿目录及其子目录一律不收
                case "$d" in */wqy|*/wqy/*) continue ;; esac
                # winfonts 整目录换成私有目录（见 zc_build_font_dir）
                case "$d" in /usr/share/fonts/truetype/winfonts) printf '%s\n' "$ZC_FONT_DIR"; continue ;; esac
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
            '<!-- zc-fontconf-v3 极空间 Wine 版专用：沿用发行版规则，剔除会破坏中文观感的字体 -->' \
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
    # 配置有版本标记：旧版本生成的（缺新规则）要重建，否则老容器一直沿用旧观感
    if [ ! -s "$ZC_FONT_CONF" ] || ! grep -q 'zc-fontconf-v3' "$ZC_FONT_CONF" 2>/dev/null; then
        zc_build_font_conf
    fi
    [ -s "$ZC_FONT_CONF" ] || return 0
    export FONTCONFIG_FILE="$ZC_FONT_CONF"
}

# 本次修正之前创建的老容器，注册表里已经写死了坏字体条目，
# Wine 不会主动删除，必须手工清掉，否则上面设的 fontconfig 不生效。
# 需要清的两类：
#   · wqy-microhei：文泉驿微米黑，中文偏细
#   · NotoSansSC-VF：可变字体默认实例是 Thin/Light，正文发虚偏细（真正的主因）
# 幂等：没有可清的就直接返回。
zc_strip_bad_fonts() {
    local f tmp need=0
    local pat='wqy-microhei\|NotoSansSC-VF'
    for f in "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg"; do
        [ -f "$f" ] || continue
        LC_ALL=C grep -q "$pat" "$f" 2>/dev/null && need=1
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
        LC_ALL=C grep -q "$pat" "$f" 2>/dev/null || continue
        tmp="$f.zctmp"
        if LC_ALL=C grep -v "$pat" "$f" > "$tmp" 2>/dev/null; then
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

# 清掉老容器里遗留的坏字体注册（必要时会先让本容器的 wineserver 退出）
zc_strip_bad_fonts

if [ ! -d "$TARGET_DIR" ]; then
    notify "正在释放程序文件（约 850 MB），请稍候…"
    mkdir -p "$WINEPREFIX/drive_c/Program Files" || die "无法写入容器目录"
    cp -r "$APPDIR/app" "$TARGET_DIR" || die "释放程序文件失败，请检查磁盘空间（需约 1.5 GB 空闲）"
fi

# 性能：Wine（wined3d）下的 D3D11 交换链合成会把窗口钉在 30fps，
# 空转还要占 CPU。关掉「GPU 合成」、保留「GPU 光栅」后实测：
#   帧率 30 → 60fps，p95 帧间隔 38.7ms → 17.5ms，空闲 CPU 17% → 9%，
#   而 video_decode / rasterization 仍是 enabled，视频解码路径不受影响。
#
# 再加 --disable-gpu-vsync --disable-frame-rate-limit：
# Wine 给不出真实的垂直同步信号，Chromium 等的那个 vsync 是假的，
# 结果每 200ms 左右就卡掉 1~2 帧（真实列表滚动实测：p95 45ms、3 秒里 17 帧超 33ms）。
# 关掉 vsync 和帧率上限后同一个负载：p95 20ms、超 33ms 帧 0~1 个、抖动标准差 10.5 → 6。
# 注意两个开关必须成对用：只关 vsync 会让它在假 vsync 上空转，空闲 CPU 冲到 76%。
# 代价是渲染不再受 60Hz 节流，动画可能超 60 帧、个别场景可能有轻微撕裂。
#
# 想恢复 Chromium 默认行为：ZSPACE_GPU_COMPOSITING=1
ZC_LAUNCH_ARGS=()
if [ "${ZSPACE_GPU_COMPOSITING:-0}" != "1" ]; then
    ZC_LAUNCH_ARGS+=(--disable-gpu-compositing --disable-gpu-vsync --disable-frame-rate-limit)
fi

# 应用会把命令行里「不是自己的」参数当成待上传文件：我们传的 Chromium 开关
# （--disable-gpu-compositing 等）会被它写进 userData/ContextUploaderItems.txt，
# 然后下次启动弹一个「上传文件到」对话框。把这个队列文件换成 /dev/null：
# 写入照常成功（但被丢弃）、读取永远为空，既不报 EPERM 也不会再误弹。
zc_mute_upload_queue() {
    local f
    for f in "$WINEPREFIX"/drive_c/users/*/AppData/Roaming/zspace/ContextUploaderItems.txt; do
        [ -d "$(dirname "$f")" ] || continue
        ln -sfn /dev/null "$f" 2>/dev/null
    done
    return 0
}
zc_mute_upload_queue

# 启动时不再弹桌面通知：它每次都会弹，属于噪音。只有首次初始化/释放文件时才提示。
exec "$WINE_CMD" "C:\\Program Files\\zspace\\极空间.exe" "${ZC_LAUNCH_ARGS[@]}" "$@"
