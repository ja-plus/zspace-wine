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

## 2026-11-04 「字太细」的真正原因：可变字体默认实例是 Thin/Light

- 背景：上一轮把文泉驿排掉后，用户仍反馈「文字还是太细」。
- 决定/结论：真因不是文泉驿，而是页面 CSS 字体栈写成了**全角逗号**
  `"Microsoft YaHei，Arial，Verdana，sans-serif"` —— Chromium 当成一个字体名，
  必然找不到，于是走默认回退，命中 `winfonts/NotoSansSC-VF.ttf`（可变字体，
  默认实例 Thin/Light）。让这个文件不出现在 Wine 的字体扫描目录里，
  回退就落到 `Noto Sans CJK SC` 常规字重，用户确认观感正常。
- 证据：CDP `CSS.getPlatformFontsForNode` 直读实际渲染字体：
  修复前正文 = `Noto Sans SC[系统]`，修复后 = `Noto Sans CJK SC[系统]`。
  辅助：`fc-match "Microsoft YaHei，Arial，Verdana，sans-serif"` 也说明这串不是列表。
- 影响：`packaging/run.sh` 增加私有字体目录 `~/.deepinwine/<包名>/fonts`
  （软链接 winfonts 全部文件、跳过 `NotoSansSC-VF.ttf`），fontconfig 的 `<dir>`
  用私有目录替换 winfonts；注册表清理从 `wqy-microhei` 扩到 `NotoSansSC-VF`。
  **`<rejectfont>` 对 Wine 无效**（Wine 直接扫目录），只清注册表也会被重新写回。

## 2026-11-04 性能：关掉 GPU 合成，30fps → 60fps

- 背景：用户反馈软件卡顿。实测默认配置下窗口被钉在 30fps，空转 CPU ~17%。
- 决定/结论：启动器默认加 `--disable-gpu-compositing`（保留 GPU 光栅）。
  恢复默认可用 `ZSPACE_GPU_COMPOSITING=1`。
- 证据（同一台机器，CDP 180 帧动画 + /proc 时间差采 CPU）：
  | 配置 | fps | p95 | 空闲 CPU |
  |---|---|---|---|
  | ANGLE-D3D11 + GPU 合成 | 30.4 | 38.7ms | ~17% |
  | `--disable-gpu-compositing` | 60.4 | 17.5ms | ~9% |
  | `--disable-gpu` 全软件 | 60.6 | 17.8ms | ~8% |
  | DXVK(Vulkan) + GPU 合成 | 60.3 | 17.7ms | ~11.5% |
- 影响：
  - `--use-angle=gl` 在 Wine 下不可用（无 EGL，退化成 SwiftShader 软件渲染）。
  - DXVK 2.7.1 实测能跑（x64 d3d11/dxgi/d3d10core 放 system32 +
    `WINEDLLOVERRIDES=d3d11,dxgi,d3d10core=n,b`，日志确认走 NVIDIA MX250 的 Vulkan），
    但收益为 0、还多依赖，**不默认启用**；以后要试按 workflow.md §3.5 的表复测。
  - 踩坑：`ps` 的 `%CPU` 是生命周期均值，刚启动虚高，对比方案必须按 /proc 时间差采样。

### 产物 2.46.2026101501-3

- 路径：`build/com.zspace.spark_2.46.2026101501-3_amd64.deb`（309.8 MB）
- SHA256 `4f3c38ee23240400f1ec9e2971a500f1af2ccdd047bfdcbcdabb378c65af3c6a`
- 源包：`packages/zspace_windows_2.46.2026101501_101619.exe`（官方无更新，`STATUS=up-to-date`）
- 验收：A1–A10 全过；B1–B8 全过（B5 用 CDP 实测正文 = `Noto Sans CJK SC`，
  私有目录 681 个字体、无 `NotoSansSC-VF.ttf`，注册表 `NotoSansSC` 计数 0）；
  F1 参数在位；F2 空闲时 60.4fps / p95 17.5ms（应用自身后台轮询时会掉到 46–59fps，
  属应用行为，非启动器问题）；F3 空闲 CPU ~9–17%（同样受应用自身轮询影响）；F4 截图无异常。
  C1/C2 待用户自行 `apt install` 后确认。
- 偏差：中间目录清理被环境拦下（`safe-delete` 需确认），不影响产物；
  `build/work-*`、`build/stage-*` 需手动清。

## 2026-11-04 「还是不如原生流畅」的根因：Wine 给不出真 vsync

- 背景：修到 60fps 后用户仍觉得不如原生。拿**页面里真实存在的 el-table 列表**
  做合成滚动手势（`Input.synthesizeScrollGesture`）量化，才发现瓶颈不在帧率。
- 决定/结论：
  - 四种渲染配置（关合成 / DXVK+Vulkan / 关遮挡节流 / 全软件）结果**完全一致**：
    52fps、p95 44~45ms、3 秒里 17 帧超 33ms。→ 换渲染后端没用。
  - 慢帧期间 `PerformanceObserver('longtask')` 计数为 **0**。→ 也不是页面 JS。
  - 真因：Chromium 在 Wine 下等的 vsync 是假的，周期性空等 1~2 帧。
  - 解法：`--disable-gpu-vsync --disable-frame-rate-limit` 与 `--disable-gpu-compositing`
    一起用 → 65fps、p95 20ms、超 33ms 帧 0~1、抖动 σ 10.5→6。
  - **两个开关必须成对**：只关 vsync 会在假 vsync 上空转，空闲 CPU 15%→76%。
- 证据：三次取中位数，`/proc` 时间差采 CPU；细节表见 `workflow.md §3.5`。
- 影响：`packaging/run.sh` 默认参数改为三个开关；代价是渲染不再受 60Hz 节流
  （动画可能超 60 帧、个别场景可能轻微撕裂），`ZSPACE_GPU_COMPOSITING=1` 可回退。
  仍然存在的差距：输入链路多两跳（X11→XWayland→Wine 消息循环→Chromium），
  这是 Wine 的结构性成本，包装层改不掉。

### 产物 2.46.2026101501-4（默认参数改为三段式）

- 路径：`build/com.zspace.spark_2.46.2026101501-4_amd64.deb`（309.8 MB）
- SHA256 `8f921c76c7163f0844fdd5c136acb163c85782dc420c989c79c5bd162e16916a`
- 变更：启动参数 = `--disable-gpu-compositing --disable-gpu-vsync --disable-frame-rate-limit`
- 验收：固定负载滚动 p95 18.5ms / 超 33ms 帧 0~1（对比默认节流 43~45ms / 16~17 帧）；
  静止空闲 CPU ~11%；语法/结构自检全过。
- 已知取舍：不限帧后，页面有持续动画时 CPU 会升高（抓到过 96%，随后回落）；
  省电优先可用 `ZSPACE_GPU_COMPOSITING=1` 回到默认节流。
- 测法翻车记录：一开始拿页面自带的 el-table 测，每次启动视图不同导致结果漂移
  （有一次直接「没有可滚动区域」）——**基准必须用注入的固定负载**。

## 2026-11-04 输入延迟实测：事件投递只要 2~3ms，不是瓶颈

- 背景：用户反馈「输入还有办法解决吗」。用 `xdotool` 从 X11 侧发真实事件，
  页面里打 `Date.now()` 时间戳对齐系统时钟，算出端到端投递延迟。
- 证据：鼠标移动 10 次中位 **3ms**、滚轮 10 次中位 **2ms**（含 xdotool 4ms 进程启动开销，
  实际接近 1ms）。页面事件全部按时收到，没有丢。
- 结论：X11→XWayland→Wine 消息循环→Chromium 这条链路**不堵**，
  能感觉到的「钝」来自「输入→画面更新」的最后一段（出帧等待 + XWayland 多一层合成），
  结构性成本约 1 帧，包装层没有可用开关再压。
- 影响：不再为此投入；省下的时间放在帧节奏（已修）上更值。

## 2026-11-04 启动弹「上传文件到」= 我们自己的命令行参数被当成文件

- 背景：用户反馈每次启动都弹「上传文件到：」对话框。
- 根因：应用把 `process.argv` 里不是它自己的参数一律当「待上传文件」，
  写进 `userData/ContextUploaderItems.txt`（`{"updateTime":…,"list":["--disable-gpu-compositing"]}`），
  首页加载时 `AutoCheckClipboard` 读取该文件，2 分钟内有效就弹窗。
  我们传的 Chromium 开关（以及调试端口参数）全都中招。
- 解决的两种错法（都试过）：
  - `chmod 444` 锁文件 → 主进程抛 `EPERM: operation not permitted` 未捕获异常，**不能用**；
  - 直接删文件 → 下次启动又被写回来。
- 有效做法：把该文件换成 `-> /dev/null` 软链接。写入照样「成功」（内容被丢弃），
  读取永远是空，`JSON.parse` 抛异常被应用自己 catch，于是永远不会弹。
- 证据：替换后 CDP 查 DOM `hasDlg=false`，main.log 无 uncaughtException。

## 2026-11-04 启动时的系统提示是启动器自己发的

- 原因：`run.sh` 里 `notify "正在启动…"` 每次启动都发一条桌面通知。
- 处理：删掉这行，只在「首次初始化容器」「释放程序文件」时提示。

### 产物 2.46.2026101501-5

- 路径：`build/com.zspace.spark_2.46.2026101501-5_amd64.deb`（309.7 MB）
- SHA256 `e4feb8d9a3d87d0aa8012bfc25a06bfa4efad11b1fa40d81036cacf376b76055`
- 变更：① 去掉每次启动的桌面通知；② 上传队列文件改 `-> /dev/null`（修启动弹窗）；
  ③ `.desktop` 加 `StartupWMClass=Wine`（DDE 上图标仍未解决，见 workflow §3.7）
- 验收：启动后 CDP 查 `hasDlg=false`；main.log 无 uncaughtException；
  X11 会话固定负载滚动 80–98fps、p95 18.7ms、0 帧 >33ms。
