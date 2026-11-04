#!/usr/bin/env bash
# 单测 packaging/run.sh 的 zc_find_wineserver（产物验收清单 E5）
#
# 要点：每个场景用独立目录，否则「命令旁边有没有 wineserver」会被别的场景污染。

set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/zspace-wineserver-selftest-$$"
mkdir -p "$TMP"

mk_bin() {   # mk_bin <dir> <name> <wineserver 所在目录|-> ；'-' 表示不建 wineserver
    local d="$1" name="$2" inner="${3:--}"
    mkdir -p "$d"
    printf '#!/bin/sh\necho %s\n' "$name" > "$d/$name"
    chmod +x "$d/$name"
    if [ "$inner" != "-" ]; then
        mkdir -p "$inner"
        printf '#!/bin/sh\necho ws-of-%s\n' "$name" > "$inner/wineserver"
        chmod +x "$inner/wineserver"
    fi
}

# 场景1：包装脚本（模拟 deepin-wine10-stable），exec 了另一处的真 wine
mkdir -p "$TMP/s1/real/bin" "$TMP/s1/bin"
printf '#!/bin/sh\necho real-wine\n' > "$TMP/s1/real/bin/wine"
printf '#!/bin/sh\necho ws-s1\n'          > "$TMP/s1/real/bin/wineserver"
chmod +x "$TMP/s1/real/bin/wine" "$TMP/s1/real/bin/wineserver"
printf '#!/bin/sh\nexec %s/real/bin/wine "$@"\n' "$TMP/s1" > "$TMP/s1/bin/deepin-wine10-stable"
chmod +x "$TMP/s1/bin/deepin-wine10-stable"

# 场景2：普通 wine，wineserver 就在旁边
mk_bin "$TMP/s2/bin" wine "$TMP/s2/bin"

# 场景3：symlink，wineserver 在真实目录旁（link 所在目录里没有 wineserver）
mk_bin "$TMP/s3/lib" wine "$TMP/s3/lib"
mkdir -p "$TMP/s3/linkdir"
ln -sf "$TMP/s3/lib/wine" "$TMP/s3/linkdir/wine-link"

# 场景4：哪儿都没有配套 wineserver
mk_bin "$TMP/s4/bin" lonlywine "-"

# 抽出被测函数（避免和 run.sh 的其它逻辑耦合）
sed -n '/^zc_find_wineserver()/,/^}/p' "$R/packaging/run.sh" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] || { echo "没能从 run.sh 抽出 zc_find_wineserver"; exit 1; }
source "$TMP/fn.sh"

pass=0; fail=0
chk() {
    if [ "$1" = "$2" ]; then
        echo "  ✅ $3"; pass=$((pass+1))
    else
        echo "  ❌ $3"; echo "     期望 $2"; echo "     实际 $1"; fail=$((fail+1))
    fi
}
expect_fail() {   # expect_fail <消息> <命令…>
    local msg="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  ❌ $msg"; fail=$((fail+1))
    else
        echo "  ✅ $msg"; pass=$((pass+1))
    fi
}

got() {   # got <PATH> <WINE_CMD>
    PATH="$1" WINE_CMD="$2" zc_find_wineserver
}

chk "$(got "$TMP/s1/bin:$PATH" deepin-wine10-stable)" "$TMP/s1/real/bin/wineserver" \
    "包装脚本 → 取它 exec 的那套 wineserver"

chk "$(got "$TMP/s2/bin:$PATH" wine)" "$TMP/s2/bin/wineserver" \
    "普通 wine → 取旁边的 wineserver"

chk "$(got "$TMP/s3/linkdir:$TMP/s3/lib:$PATH" wine-link)" "$TMP/s3/lib/wineserver" \
    "symlink → 取真实目录旁的 wineserver"

expect_fail "无配套 wineserver 时返回失败（不猜别的运行时）" \
    got "$TMP/s4/bin:$PATH" lonlywine

expect_fail "不存在的运行时返回失败" got "$PATH" 不存在的运行时

echo
echo "通过 $pass / 失败 $fail"
exit $(( fail > 0 ))
