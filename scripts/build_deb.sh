#!/usr/bin/env bash
# 把 packages/ 里的官方 Windows 安装包打成星火规范的 Wine deb。
#
#   scripts/build_deb.sh                     # 用 packages/ 里版本最高的那个包
#   scripts/build_deb.sh --file <exe>        # 指定安装包（同时拷入 packages/）
#   scripts/build_deb.sh --rev 2             # 指定 Debian 修订号（默认 1）
#   scripts/build_deb.sh --keep-work         # 保留解包中间目录，便于排查
#
# 产物：build/com.zspace.spark_<版本>-<修订>_amd64.deb
# 退出码：0 成功；1 失败。任一自检不通过都不会产出 deb。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

REV=1; EXE=""; KEEP_WORK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --file|-f)  EXE="${2:?--file 需要路径}"; shift 2 ;;
        --rev)      REV="${2:?--rev 需要数字}"; shift 2 ;;
        --keep-work) KEEP_WORK=1; shift ;;
        -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
        *) die "未知参数：$1" ;;
    esac
done

need 7z
need python3
need dpkg-deb

# ── 1. 选定安装包 ──────────────────────────────────────────────
if [ -n "$EXE" ]; then
    [ -f "$EXE" ] || die "找不到安装包：$EXE"
    "$ROOT/scripts/download.sh" --file "$EXE" >/dev/null
    EXE="$PKG_DIR/$(basename "$EXE")"
else
    line="$(local_package)" || die "packages/ 下没有 .exe 安装包。先运行 scripts/download.sh，或用 --file 指定"
    EXE="${line#*|}"
fi

# 版本号从文件名解析：zspace_windows_<版本>_<时间戳>.exe
VER="$(basename "$EXE" | sed -nE 's/^zspace_windows_([0-9][0-9.]*)_[0-9]+\.exe$/\1/p')"
[ -n "$VER" ] || VER="$(basename "$EXE" .exe | sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+[0-9.]*).*/\1/p')"
[ -n "$VER" ] || die "无法从文件名解析版本号：$(basename "$EXE")（期望形如 zspace_windows_2.46.2026101501_101619.exe）"

PKG_NAME="com.zspace.spark"
DEB_VERSION="${VER}-${REV}"
WORK="$BUILD_DIR/work-${VER}"
# staging 用唯一目录名，不做「先删后拷」：
# 一是避免残留内容混进同一个包，二是受限环境下批量删除可能被安全策略拦下
STAGE="$BUILD_DIR/stage-${DEB_VERSION}-$$"
DEB="$BUILD_DIR/${PKG_NAME}_${DEB_VERSION}_amd64.deb"

info "安装包：$(basename "$EXE")"
info "版本号：$DEB_VERSION"

# ── 2. 解包 ────────────────────────────────────────────────────
if [ -d "$WORK/app" ] && [ -f "$WORK/app/resources/app.asar" ]; then
    ok "复用已解包目录：$WORK/app"
else
    remove_dir "$WORK"
    mkdir -p "$WORK"
    info "解包 NSIS 安装包…"
    ( cd "$WORK" && 7z x -y "$EXE" >/dev/null ) || die "NSIS 解包失败"

    P7Z="$WORK/\$PLUGINSDIR/app-64.7z"
    [ -f "$P7Z" ] || die "安装包里没有 \$PLUGINSDIR/app-64.7z，结构与预期不符"
    info "解包 app-64.7z…"
    7z x -y -o"$WORK/app" "$P7Z" >/dev/null || die "app-64.7z 解包失败"
fi

APP="$WORK/app"
[ -f "$APP/极空间.exe" ]        || die "解包结果缺少 主程序 极空间.exe"
[ -f "$APP/resources/app.asar" ] || die "解包结果缺少 resources/app.asar"

# ── 3. 产物体检（不通过就不打包）────────────────────────────────
info "体检解包结果…"
fail=0

# 3.1 asar 未加固：能直接读出 JS 字符串即视为未加固
if grep -aq 'electron-builder\|BrowserWindow\|app.asar' "$APP/resources/app.asar"; then
    ok "app.asar 未加固，可直接读取（便于后续排查）"
else
    warn "app.asar 看起来是加固过的，后续排查会困难（不影响打包）"
fi

# 3.2 关键运行时文件
for f in "icudtl.dat" "resources.pak" "v8_context_snapshot.bin" "locales/zh-CN.pak"; do
    [ -e "$APP/$f" ] || { err "缺少运行时文件：$f"; fail=1; }
done
[ "$fail" = 0 ] && ok "Electron 运行时文件齐全"

# 3.3 启动器语法
bash -n "$PACK_DIR/run.sh" || { err "packaging/run.sh 语法错误"; fail=1; }
bash -n "$PACK_DIR/postinst" || { err "postinst 语法错误"; fail=1; }
bash -n "$PACK_DIR/postrm"   || { err "postrm 语法错误"; fail=1; }
[ "$fail" = 0 ] && ok "脚本语法检查通过"

# 3.4 启动器必须含字体修正（中文渲染质量）
grep -q 'FONTCONFIG_FILE' "$PACK_DIR/run.sh" || { err "run.sh 缺少字体修正（FONTCONFIG_FILE）"; fail=1; }
grep -q 'wqy-microhei'    "$PACK_DIR/run.sh" || { err "run.sh 缺少文泉驿清理逻辑"; fail=1; }
[ "$fail" = 0 ] && ok "启动器含中文字体修正"

# 3.5 星火规范：不许提权；包体文件名尽量无中文（官方二进制里的中文主程序除外）
grep -qE 'chmod[[:space:]]+4755|chown[[:space:]]+root' "$PACK_DIR/run.sh" && { err "run.sh 含提权操作，违反星火规范"; fail=1; }
[ "$fail" = 0 ] && ok "星火上架规范检查通过"

[ "$fail" = 0 ] || die "体检未通过，已中止打包（不产出 deb）"

# ── 4. 组装 deb ────────────────────────────────────────────────
info "组装包结构…"
if [ -e "$STAGE" ]; then
    die "staging 目录意外已存在：$STAGE（换 PID 重试）"
fi
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/opt/durapps/$PKG_NAME/files" \
         "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/doc/$PKG_NAME" \
         "$STAGE/usr/share/icons"

DST="$STAGE/opt/durapps/$PKG_NAME/files/app"
if [ -e "$DST" ]; then
    die "残留目录没清干净：$DST（会导致新旧内容混进同一个包）"
fi
cp -a "$APP" "$DST"
install -m 755 "$PACK_DIR/run.sh"     "$STAGE/opt/durapps/$PKG_NAME/files/run.sh"
install -m 755 "$PACK_DIR/launcher.sh" "$STAGE/usr/bin/$PKG_NAME"
install -m 644 "$PACK_DIR/com.zspace.spark.desktop" "$STAGE/usr/share/applications/$PKG_NAME.desktop"
install -m 644 "$PACK_DIR/README-doc.md" "$STAGE/usr/share/doc/$PKG_NAME/README.md"
cp -a "$PACK_DIR/icons/hicolor" "$STAGE/usr/share/icons/"

install -m 755 "$PACK_DIR/postinst" "$STAGE/DEBIAN/postinst"
install -m 755 "$PACK_DIR/postrm"   "$STAGE/DEBIAN/postrm"

INSTALLED_SIZE=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $DEB_VERSION
Architecture: amd64
Maintainer: Local Build <local@localhost>
Installed-Size: $INSTALLED_SIZE
Depends: deepin-wine10-stable | deepin-wine11-stable | deepin-wine8-stable, deepin-wine-helper
Section: net
Priority: optional
Homepage: https://www.zspace.cn
Description: 极空间私有云客户端 (Wine 版)
 基于极空间官方 Windows 客户端 V${VER},通过 deepin-wine 运行。
 首次启动会自动创建 Wine 容器(~/.deepinwine/$PKG_NAME),
 并把程序文件释放到 C:\\Program Files\\zspace。
 完全使用官方原始二进制,不做任何修改。
EOF

# 星火要求包体文件名无中文；官方二进制里的 主程序名 属于厂商原样，不动
bad="$(non_ascii_names "$STAGE" | grep -v '/files/app/' | head -1 || true)"
[ -n "$bad" ] && warn "包体存在非 ASCII 文件名：$bad"

# ── 5. 构建 + 复核 ─────────────────────────────────────────────
info "构建 deb…"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB" >/dev/null || die "dpkg-deb 失败"

info "复核产物…"
dpkg-deb -I "$DEB" >/dev/null || die "产物不是合法 deb"

# 注意：不要写成 dpkg-deb -c | grep -q —— grep 提前关管道会给 tar 发 SIGPIPE，
# 表现为「tar 子进程被信号(断开的管道) 终止」，实际包是好的。
LIST="$BUILD_DIR/.deblist"
dpkg-deb -c "$DEB" > "$LIST" || die "无法读取产物内容"
grep -q '\./opt/durapps/'"$PKG_NAME"'/files/app/极空间\.exe$' "$LIST" \
    || die "产物里找不到 极空间.exe"
grep -q '\./usr/share/applications/'"$PKG_NAME"'\.desktop$' "$LIST" \
    || die "产物里找不到 desktop 文件（desktop 名必须等于包名）"
grep -q '\./usr/bin/'"$PKG_NAME"'$' "$LIST" \
    || die "产物里找不到启动器 /usr/bin/$PKG_NAME"
dpkg-deb -I "$DEB" | grep -q 'postrm' || die "产物缺 postrm（星火要求卸载时清容器）"
ok "产物结构复核通过"

SHA=$(sha256sum "$DEB" | cut -d' ' -f1)
SIZE=$(stat -c%s "$DEB")

if [ "$KEEP_WORK" = 0 ]; then
    # 清理失败不影响产物，只提示
    remove_dir "$WORK" "$STAGE" || warn "中间目录清理不彻底，可手动删掉 $WORK $STAGE"
fi

cat <<EOF

${C_OK}打包完成${C_OFF}
  产物   : $DEB
  版本   : $DEB_VERSION
  大小   : $(human_size "$SIZE")
  SHA256 : $SHA
  安装   : sudo apt install $DEB
EOF

# 供 agent 记录到 .agents/memory.md
echo "DEB_PATH=$DEB"
echo "DEB_VERSION=$DEB_VERSION"
echo "DEB_SHA256=$SHA"
echo "DEB_SIZE=$SIZE"
echo "SOURCE_EXE=$(basename "$EXE")"
