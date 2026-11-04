#!/usr/bin/env bash
# 查询极空间官方 Windows 客户端的最新版本。
#
#   scripts/check_update.sh              # 查一次（24 小时内的缓存直接复用）
#   scripts/check_update.sh --force      # 忽略缓存，强制查询
#   scripts/check_update.sh --json       # 输出接口原始 JSON
#   scripts/check_update.sh --quiet      # 只输出 KEY=VALUE，不打印说明文字
#
# 接口来源与字段含义见 .agents/sources.md
# 退出码：0 成功；1 调用失败。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

FORCE=0; JSON=0; QUIET=0
for a in "$@"; do
    case "$a" in
        --force|--refresh) FORCE=1 ;;
        --json)            JSON=1 ;;
        --quiet|-q)        QUIET=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) die "未知参数：$a" ;;
    esac
done

CACHE="$STATE_DIR/update.json"
STAMP="$STATE_DIR/update.checked-at"
TTL=$((24 * 3600))

need curl
need python3

# ── 取接口数据（带每日一次缓存）─────────────────────────────────
fetch() {
    local url="${API_BASE}?app_id=${APP_ID}&app_version=V0.0.0&nas_id=&plat=app&channel=${CHANNEL}&skip_app_sync_upgrade=1"
    curl -fsSL --connect-timeout 15 --max-time 60 "$url" -o "$CACHE.tmp" || return 1
    python3 - "$CACHE.tmp" <<'PY' || return 1
import json, sys
raw = open(sys.argv[1], encoding='utf-8').read()
d = json.loads(raw)
assert d.get('code') == '200', d.get('msg')
data = d['data']
for k in ('app_version', 'download_url', 'package_size', 'update_time'):
    assert data.get(k), f'接口缺少字段 {k}'
json.dump(d, open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False)
PY
    mv -f "$CACHE.tmp" "$CACHE"
    date +%s > "$STAMP"
}

cache_fresh() {
    [ -s "$CACHE" ] && [ -s "$STAMP" ] || return 1
    local now then
    now=$(date +%s); then=$(cat "$STAMP" 2>/dev/null || echo 0)
    [ $((now - then)) -lt $TTL ]
}

if [ "$FORCE" = 1 ] || ! cache_fresh; then
    info "查询官方最新版本…"
    fetch || die "官方接口调用失败（网络不通或接口变更）。可稍后重试，或手动下载后用 scripts/download.sh --file <exe> 放入 packages/"
    ok "已更新缓存：$CACHE"
else
    [ "$QUIET" = 1 ] || info "使用缓存（$(human_size $(python3 -c "import time;print(int(time.time())-$(cat "$STAMP"))"))前查询）"
fi

[ "$JSON" = 1 ] && { cat "$CACHE"; exit 0; }

# ── 汇总 ───────────────────────────────────────────────────────
python3 - "$CACHE" "$PKG_DIR" "$QUIET" <<'PY'
import json, os, sys, glob, time, shlex

cache_path, pkg_dir, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
d = json.load(open(cache_path, encoding='utf-8'))['data']

latest = d['app_version']
url = d['download_url']
size = int(d['package_size'])
updated = d.get('update_time', '')
notes = (d.get('version_content') or '').replace('\r\n', '\n').strip()

def norm(v):
    v = v.lstrip('Vv')
    return [int(x) if x.isdigit() else 0 for x in v.split('.')]

# 本地包：取版本最高的一份
best_v, best_f = '', ''
for f in glob.glob(os.path.join(pkg_dir, '*.exe')):
    base = os.path.basename(f)
    v = base[len('zspace_windows_'):-len('.exe')].rsplit('_', 1)[0] if base.startswith('zspace_windows_') and base.endswith('.exe') else os.path.splitext(base)[0]
    v = v.strip() or os.path.splitext(base)[0]
    if not best_v or norm(v) > norm(best_v):
        best_v, best_f = v, f

if not best_f:
    status = 'no-package'
elif norm(latest) > norm(best_v):
    status = 'newer-available'
elif norm(latest) == norm(best_v):
    status = 'up-to-date'
else:
    status = 'local-newer'

if not quiet:
    def mb(n): return f"{n/1024/1024:.1f} MB"
    print()
    print(f"  官方最新版 : {latest}")
    print(f"  更新日期   : {updated}")
    print(f"  安装包大小 : {mb(size)}")
    print(f"  下载地址   : {url}")
    if best_f:
        print(f"  本地版本   : {best_v}")
        print(f"  本地文件   : {os.path.basename(best_f)}")
    else:
        print("  本地版本   : （packages/ 下没有安装包）")
    if status == 'newer-available':
        print(f"  状态       : 官方有新版本（{best_v} → {latest}）")
    elif status == 'up-to-date':
        print(f"  状态       : 已是最新")
    elif status == 'local-newer':
        print(f"  状态       : 本地版本比官方还新，谨慎处理")
    else:
        print(f"  状态       : 本地没有安装包")
    if notes:
        print("  更新内容   :")
        for line in notes.splitlines()[:12]:
            if line.strip():
                print(f"    {line.strip()}")
    print()

print(f"LATEST_VERSION={shlex.quote(latest)}")
print(f"LOCAL_VERSION={shlex.quote(best_v or 'none')}")
print(f"STATUS={shlex.quote(status)}")
print(f"DOWNLOAD_URL={shlex.quote(url)}")
print(f"PACKAGE_SIZE={size}")
print(f"UPDATE_TIME={shlex.quote(updated)}")
print(f"LOCAL_FILE={shlex.quote(best_f or 'none')}")
print(f"UPDATE_NOTES={shlex.quote(notes)}")
PY
