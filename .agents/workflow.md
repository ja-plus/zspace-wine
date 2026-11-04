# workflow.md —— 打包与发布标准流程

> Agent 要打包时按这份走。任何一步的偏差都要在 `.agents/memory.md` 里说明原因。

## 0. 前置

- 工具齐备：`7z`、`dpkg-deb`、`curl`、`python3`、`xz`、`sha256sum`
- `packages/` 里有 `.exe` 安装包（没有就先 `scripts/download.sh`）
- 已按 `AGENTS.md §2.1` 确认过版本

## 1. 标准流程

```bash
# 1) 确认版本（有新版必须先问用户）
scripts/check_update.sh --force

# 2) 打包
scripts/build_deb.sh
#    可选：--file <exe>  指定安装包
#          --rev N       Debian 修订号，默认 1
#          --keep-work   保留解包中间目录（排查时用）

# 3) 验收
#    逐项过 checklist.md，全绿才算完成
```

产物：`build/com.zspace.spark_<版本>-<修订>_amd64.deb`

## 2. 产物结构（星火规范）

```
com.zspace.spark_<ver>-<rev>_amd64.deb
├── DEBIAN/
│   ├── control                 Package: com.zspace.spark（desktop 名必须一致）
│   ├── postinst                刷新 desktop/图标缓存
│   └── postrm                  卸载时清 ~/.deepinwine/com.zspace.spark
├── opt/durapps/com.zspace.spark/
│   └── files/
│       ├── app/                官方原始二进制，**一个字节都不改**
│       └── run.sh              启动器（含中文字体修正）
├── usr/bin/com.zspace.spark    → files/run.sh 的转发脚本
├── usr/share/applications/com.zspace.spark.desktop
├── usr/share/icons/hicolor/*/apps/com.zspace.spark.png
└── usr/share/doc/com.zspace.spark/README.md
```

### 星火上架红线

| 规则 | 说明 |
|---|---|
| 装到 `/opt/durapps/<包名>/` | 其它路径会被拒 |
| 包名 `.spark` 后缀 | 如 `com.zspace.spark` |
| desktop 名 = 包名 | 文件名 `com.zspace.spark.desktop`，与 `Package:` 一致 |
| `postrm` 清容器 | `~/.deepinwine/<包名>` 必须删干净 |
| 禁止提权 | 不得出现 `chmod 4755` / `chown root`，ssinstall 会拒 |
| 文件名无中文 | 指 **deb 文件名**；官方二进制里的中文主程序名属厂商原样，保留 |
| 不改官方二进制 | 商业软件只能投稿官网可免费下载的版本，**不得改动官方二进制和配置** |

### 运行时与发行版兼容性

包**不绑死 deepin-wine**，任何装了 Wine 的发行版都能装能跑：

```
Depends: deepin-wine10-stable | deepin-wine11-stable | deepin-wine8-stable
       | deepin-wine | wine64 | wine | wine-stable
```

- apt 从左往右找第一个可用的：Deepin/UOS 上仍选 deepin-wine10，行为不变；
  其它发行版退到 `wine64`/`wine`。
- **不要**把 `deepin-wine-helper` 写回 Depends——它没被任何脚本调用过，
  写进去只会把非 Deepin 发行版挡在门外（已加自检，见 checklist E1）。
- 启动器支持 `WINE=<命令>` 强制指定运行时，便于排查。
- `zc_find_wineserver` 必须从**选中的** wine 往回推配套的 wineserver；
  先猜 `/opt/deepin-wine*` 会拿错版本，报 `version mismatch 933/891`。
- 非 Deepin 环境的中文渲染依赖发行版自带 CJK（`zc_have_yahui` 不成立时自动跳过字体修正），
  观感会和 Deepin 上略有差异，属预期。

## 3. 启动器的职责（`packaging/run.sh`）

按顺序：

1. 设 `WINEPREFIX`、`ELECTRON_DISABLE_SANDBOX=1`
2. `unset NODE_OPTIONS / ELECTRON_RUN_AS_NODE` —— 否则 Electron 会退化成纯 Node 直接崩
3. `unset WAYLAND_DISPLAY` —— treeland 下 Wine 的 wayland 驱动建不出窗口，走 XWayland
4. **中文字体修正**：私有字体目录 + fontconfig，把「默认实例是 Thin/Light 的可变字体」挡在字体集外
5. 首次运行初始化 Wine 容器，等待 `system.reg` 落盘（`wineboot` 是异步的，必须轮询）
6. 清理老容器里遗留的坏字体注册表条目（**清之前要先让 wineserver 退出**，
   否则它退出时会把旧注册表写回文件）
7. 释放程序文件到 `C:\Program Files\zspace`（约 850 MB）
8. `exec` 启动 `极空间.exe`（带 `--disable-gpu-compositing`）

### 中文字体：现象与真因（2026-11-04 用 CDP 实测，勿凭直觉改）

页面 CSS 把字体栈写成了**全角逗号**：

```
font-family: "Microsoft YaHei，Arial，Verdana，sans-serif"
```

Chromium 把整串当成一个字体名 → 必然找不到 → 走默认回退字体。
回退命中的是 `/usr/share/fonts/truetype/winfonts/NotoSansSC-VF.ttf`，
这是个**可变字体**，Wine 取到的默认实例是 Thin/Light —— 这就是「字太细」的真因，
跟文泉驿无关（文泉驿那条是上一个结论，仍然保留排除，但不是主因）。

剔掉它之后，回退落到 `Noto Sans CJK SC` 常规字重，观感正常（用户已确认）。

**做法**：`NotoSansSC-VF.ttf` 和 `msyh.ttc` 同在 winfonts 目录，没法按目录排除，
所以启动器建一个私有目录 `~/.deepinwine/<包名>/fonts`（软链接 winfonts 全部文件、
唯独跳过 `NotoSansSC-VF.ttf`），fontconfig 的 `<dir>` 用这个私有目录替换 winfonts。

### 中文字体：这些路子都走不通（已实测，别再试）

| 无效做法 | 原因 |
|---|---|
| fontconfig `<rejectfont>` | `fc-list` 里确实没了，但 **Wine 直接扫目录**，照样注册进字体表 |
| fontconfig `<rejectfont>` 排除目录 | 同上 |
| 只清注册表 `HKLM\...\Fonts` 的条目 | 下次启动 Wine 重新扫目录，条目会再写回来 |
| `HKCU\Software\Wine\Fonts\Replacements` | 不作用于 Chromium 的 DirectWrite |
| `--enable-lcd-text` / `FontSmoothing*` / `Antialias`/`Gamma` | Chromium 用 Skia 自绘，截图逐像素无变化 |
| fontconfig `target="scan"` 改字体名 | fc-list 能看到，Wine 不认（字面名取自 FreeType） |
| `Software\Wine\Fonts\LogPixels` | Wine 每次从 X 重新推导 DPI，会被覆盖 |

**唯一有效**：让坏字体文件不在 Wine 扫描的目录里（私有字体目录），
再清掉老容器注册表里的残留条目。`FONTCONFIG_FILE` 必须在 `wineboot` 之前 export。

### 验字体的正确姿势

别靠肉眼、也别靠 canvas 探针（探针只能证明「某个字体名可解析」，证明不了页面用了谁）。
用 Chromium 自带的 CDP：

```bash
# 带调试端口启动
run.sh --remote-debugging-port=9222
# 然后对页面元素问 CSS.getPlatformFontsForNode，它会直接告诉你实际渲染用的字体族
```

判据：正文元素的 `familyName` **不能是 `Noto Sans SC`**（那是那个可变字体）；
`Noto Sans CJK SC` / `Microsoft YaHei` 都属于正常。

## 3.5 性能：三段式，最后一段才是关键

### 第一段：wined3d 的 GPU 合成把窗口钉在 30fps

启动器默认加 `--disable-gpu-compositing`（保留 GPU 光栅）：

| 配置 | 帧率 | p95 帧间隔 | 空闲 CPU |
|---|---|---|---|
| 默认（ANGLE-D3D11 + GPU 合成） | 30.4 | 38.7 ms | ~17% |
| **`--disable-gpu-compositing`** | 60.4 | 17.5 ms | ~9% |
| `--disable-gpu`（完全软件） | 60.6 | 17.8 ms | ~8% |

### 第二段：Wine 拿不到真 vsync，周期性卡一两帧

测法（**必须用固定负载**，否则不可比）：往页面里注入一个 200 行的可滚动容器，
用 `Input.synthesizeScrollGesture` 驱动滚动，同时记录每帧间隔。
（早期拿页面自带的 el-table 测，结果会随每次启动恢复的视图不同而漂移，已弃用。）

关掉 GPU 合成后，只比较 vsync/限帧这一组：

| 配置 | 平均 FPS | p95 | 抖动 σ | 3 秒内超 33ms 帧 |
|---|---|---|---|---|
| 默认节流（等假 vsync） | 52 ~ 85 | 43 ~ 45 ms | ~10 | 16 ~ 17 |
| **`--disable-gpu-vsync --disable-frame-rate-limit`** | **83 ~ 97** | **18.5 ms** | **~7** | **0 ~ 1** |

关键证据：慢帧期间 `PerformanceObserver('longtask')` 计数为 **0** ——
不是页面 JS，是帧调度在空等一个不存在的 vsync。

**必须成对用**：只关 vsync 会让 Chromium 在假 vsync 上空转，空闲 CPU 15% → 76%（实测）。

**代价**：渲染不再被 60Hz 节流。静止页面空闲 CPU 约 11%，但页面**有持续动画**时
（例如刚启动的入场动画、视频播放）CPU 会明显升高（实测抓到过 96%）。
省电优先时把它去掉即可（见下）。

### 渲染后端：实测都白搭

| 配置 | 结论 |
|---|---|
| DXVK（Vulkan，2.7.1 可正常跑） | 同一负载下与 wined3d 无差异（52.0 vs 52.4 fps），多三个 DLL + Vulkan 依赖 |
| `--disable-gpu` 全软件 | 与关合成一致，无改善 |
| 关遮挡计算 / 关后台节流 | 无变化 |
| `--use-angle=gl` | Wine 无 EGL，ANGLE 直接退到 SwiftShader 纯软件 |
| wined3d + GPU 合成 + 不限帧 | **更差**（p95 68~70ms），确认必须关 GPU 合成 |

DXVK 若以后要试：x64 的 `d3d11.dll`/`dxgi.dll`/`d3d10core.dll` 放进容器 `system32`
（替换原来的软链接），`WINEDLLOVERRIDES=d3d11,dxgi,d3d10core=n,b`，
`DXVK_LOG_PATH` 可看它选了哪块 GPU。

### 复测方法与坑

```bash
run.sh --remote-debugging-port=9222
# 然后在页面里：真实列表滚动手势 + 帧间隔 + longtask 观测
```

- `ps` 的 `%CPU` 是**生命周期平均值**，刚启动会虚高；采 CPU 必须按
  `/proc/<pid>/stat` 的 utime+stime 差值算。
- 应用自身后台轮询（每 10s 拉列表、60s 超时重试）会让负载有波动，测 3 次取中位数。



## 4. 发布

本项目**不自动发布**。产物只在本地 `build/` 里。

- 用户要装：`sudo apt install ./build/com.zspace.spark_<ver>-<rev>_amd64.deb`
- 要投星火商店：让用户自己走投递流程，并提醒他确认官方授权。
  **Agent 不要代为上传。**

## 5. 版本号约定

- deb 版本 = `<官方版本号>-<修订号>`，例：`2.46.2026101501-1`
- 官方版本号变 → 修订号从 1 重新开始
- 同一官方版本下，打包脚本/启动器有改动 → 修订号 +1（`--rev N`）

## 3.7 托盘/Dock 图标是酒杯（Wine 默认图标）

- 现象：Dock 里显示红底酒杯，不是极空间图标。
- 排查结论：
  - 窗口没有 `_NET_WM_ICON`（`xprop -id <win> _NET_WM_ICON` → not found），
    说明应用本身没给窗口设图标；
  - 窗口 `WM_CLASS = ("极空间.exe", "Wine")`，DDE 的 dde-shell 按类名匹配启动器条目，
    命中 **Wine 自己的 desktop**，于是用 Wine 的酒杯图标。
- 已尝试、**无效**的做法（别再走）：
  - `.desktop` 里加 `StartupWMClass=Wine`（仍被 Wine 自己的条目抢走）；
  - 外部把 `_NET_WM_ICON` 写进窗口（xprop 有 64 元素上限，换 ctypes 写成功也没用，
    dock 不读这个属性，它只认 desktop 条目）；
  - `xdotool set_window --class com.zspace.spark` 改类名 + 对应 desktop（未生效）。
- 现状：`.desktop` 里保留 `StartupWMClass=Wine`（对别的发行版/Dock 可能有用，无害），
  但 **DDE 上图标仍是酒杯**，属已知未解决的外观问题，不影响功能。

## 3.8 启动参数不能乱加（重要）

应用会把命令行里多余的参数当成「待上传文件」，写进
`userData/ContextUploaderItems.txt`，然后下次启动弹「上传文件到」。
所以：

- 加 Chromium 开关的同时，必须把该文件改成 `-> /dev/null`（启动器里的
  `zc_mute_upload_queue`），否则每次启动都会弹窗；
- 临时用 `--remote-debugging-port` 调试也会触发同样的弹窗，调完记得让启动器把队列文件还原成软链接；
- **不要**用 `chmod 444` 锁这个文件：应用写入会抛 `EPERM` 未捕获异常。
