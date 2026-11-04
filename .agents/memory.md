# memory.md —— 跨会话记忆

> **只追加，不改写历史。** 每次会话把有价值的东西写在文件末尾。
> 新会话开始时先读完本文件，再动手。

## 记忆规则

1. **写什么**：用户拍板的决定、产物记录（路径/版本/SHA256）、踩过的坑、
   官方接口的变化。不写过程流水账、不写临时路径。
2. **怎么写**：分节，带日期。格式见下方模板。
3. **改口径时**：旧结论不要删，在下面加一行"**已被 XXX 取代**"并说明原因。
4. **不存敏感信息**：密码、token、内网地址一律不写。

## 记录模板

```
## YYYY-MM-DD <一句话标题>
- 背景：
- 决定/结论：
- 证据：
- 影响：
```

---

# 以下是实际记录（按时间追加）

## 2026-11-04 项目建立

- 背景：要把极空间 Windows 客户端长期用 deepin-wine 跑在统信上，
  希望官方出新版时能自动发现、下载、重新打包，并且由 AI Agent 维护。
- 决定/结论：
  - 项目落在 `~/Desktop/zspace-wine`，用 git 管理，Agent 以 `AGENTS.md` 为行为契约。
  - 版本来源用官方接口 `upgrade.zenithspace.net/upgrade_server/v2/check_upgrade`
    （`app_id=APP_ZSPACE_DESKTOP_WIN`, `channel=zspace`），每日缓存一次。
  - 打包链路：NSIS exe → `$PLUGINSDIR/app-64.7z` → `app/` → 按星火规范组 deb。
  - 中文字体必须回落到微软雅黑（原因与无效做法见 `.agents/workflow.md`）。
- 证据：`scripts/check_update.sh` 实测拿到 `V2.46.2026101501`，
  `scripts/build_deb.sh` 实测产出 deb 且结构复核通过。
- 影响：后续版本更新只需 `download.sh` + `build_deb.sh`，无需重新摸索。

## 2026-11-04 中文字体修正（极重要）

- 背景：应用字体栈
  `PingFang SC, Source Han Sans CN, WenQuanYi Micro Hei, Microsoft YaHei, sans-serif`
  在 Linux 桌面上会命中第 3 项「文泉驿微米黑」，中文偏细、西文偏窄。
- 决定/结论：注入排除 `wqy` 目录的 `FONTCONFIG_FILE`，让字体栈落到微软雅黑；
  老容器还要清掉已写死的 `wqy-microhei` 注册表条目（**清之前先让 wineserver 退出**，
  否则它退出时会把旧注册表写回）。
- 证据：canvas 像素哈希，修复前 `appStack == WenQuanYi Micro Hei`，
  修复后 `appStack == Microsoft YaHei`；13px 墨量 雅黑 145173 / 思源黑体 141905 /
  等线 102192 / 默认回退 99754。
- 影响：`packaging/run.sh` 里的字体段落是这次的结论，改动前务必重新验证中文渲染。

## 2026-11-04 首次打包 2.46.2026101501-1

- 背景：项目脚本写完后的第一次完整打包，作为后续流程的基线。
- 决定/结论：
  - 产物 `build/com.zspace.spark_2.46.2026101501-1_amd64.deb`（309.7 MB）
  - SHA256 `f499e8493305b0f91a49f46c6dccc93c5ca18dee6d695086fada224e0b7351ca`
  - 源包 `packages/zspace_windows_2.46.2026101501_101619.exe`
  - 验收：A1–A10 全过，B1/B2/B6/B7 全过（18/18）；
    B3–B5 需装机后验证，C1–C3 需 root，留给用户确认。
- 证据：`dpkg-deb -I/-c` 复核通过；启动器 `bash -n` 通过；
  包内含 `files/app/极空间.exe`、`files/app/resources/app.asar`、`usr/bin/com.zspace.spark`。
- 影响：后续版本更新沿用同一条链路，产物信息照此格式追加。

### 打包链路踩过的坑（脚本已修，记录以免回退）

1. `dpkg-deb -c | grep -q` 会让 grep 提前关管道，tar 收到 SIGPIPE 报
   「tar 子进程被信号(断开的管道) 终止」——**包本身是好的**，是校验姿势不对。
   改成先落盘再 grep。
2. `set -e` 下函数末尾写 `[ -e ] && warn`，目录已删时整条返回 1，
   函数返回值带出去会中止脚本。删除类函数必须显式 `return 0`/`return 1`。
3. staging 目录用**唯一名**（带 PID），不要"先删后拷"：
   既避免残留内容被 `cp -a` 拷成 `app/app`（包体翻倍、条目翻倍），
   也避开受限环境下批量删除被安全策略拦下的情况。

## 2026-11-04 去掉 deepin-wine 绑定，产物 2.46.2026101501-2

- 背景：用户问「是不是只有 Deepin 环境能跑」。结论是卡在**运行时依赖**，不是桌面环境：
  原 Depends 里的 `deepin-wine-helper` 是硬依赖且**从未被任何脚本调用**，
  加上 run.sh 只认 `deepin-wine*`，把其它发行版挡在门外。
- 决定/结论：
  - Depends 改为 `deepin-wine10-stable | deepin-wine11-stable | deepin-wine8-stable
    | deepin-wine | wine64 | wine | wine-stable`（去掉 deepin-wine-helper）。
    apt 从左往右挑，Deepin 上仍选 deepin-wine10，行为不变。
  - run.sh 探测链加 `wine64`/`wine`/`wine-stable`，并支持 `WINE=<命令>` 强制指定。
  - `zc_find_wineserver` 改成从**选中的** wine 往回推配套 wineserver
    （包装脚本 → 解析它 exec 的真 wine；symlink → readlink -f 后看真实目录），
    **兜底故意不猜 `/opt/deepin-wine*`**：同时装两种 wine 时猜错会杀掉另一套的
    wineserver、报 version mismatch；找不到就返回失败让调用方跳过 kill。
  - 非 Deepin 环境的中文渲染依赖发行版自带 CJK（`zc_have_yahui` 不成立时跳过字体修正）。
- 证据：`scripts/selftest_wineserver.sh` 5 场景全绿（包装脚本/普通 wine/symlink/
  无配套/不存在）；`build_deb.sh --rev 2` 复核 A+B+E 共 19 项全过，
  Depends 已无 deepin-wine-helper、含 wine64。
- 影响：任何装了 Wine 的发行版都能装能跑；星火投稿不受影响（Deepin 上 apt 仍选第一项）。
  **E6（非 Deepin 真机/容器冒烟）尚未做**，留给有需要时装个容器补测。

### 产物 2.46.2026101501-2

- 路径：`build/com.zspace.spark_2.46.2026101501-2_amd64.deb`（309.7 MB）
- SHA256 `24b83b7f8e35f41e2715102516438e3c889a37bfb5f17eacedcd24a112ff7833`
- 源包：`packages/zspace_windows_2.46.2026101501_101619.exe`
- 上一条记录里的 `-1` **已被本条取代**（原因：依赖与运行时探测不具可移植性）。
