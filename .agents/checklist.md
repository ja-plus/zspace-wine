# checklist.md —— 产物验收清单

> **Agent 打包后必须逐项过这张表。** 全绿才可以说"打包完成"。
> 每次把结果（过 / 不过 + 证据）记进 `.agents/memory.md`。
> 有一项不过 → 修到过，或如实告诉用户没过。**不许跳过，不许含糊。**

产物路径：`build/com.zspace.spark_<版本>-<修订>_amd64.deb`（下称 `$DEB`）

## A. 包结构

| # | 检查项 | 怎么验 | 必须 |
|---|---|---|---|
| A1 | deb 合法 | `dpkg-deb -I $DEB` 能正常输出 | ✅ |
| A2 | `Package` 名正确 | control 里 `Package: com.zspace.spark` | ✅ |
| A3 | desktop 名 = 包名 | 包里有 `./usr/share/applications/com.zspace.spark.desktop` | ✅ |
| A4 | 装在 `/opt/durapps/` | 包里有 `./opt/durapps/com.zspace.spark/files/app/` | ✅ |
| A5 | 主程序完整 | 包里有 `./opt/durapps/com.zspace.spark/files/app/极空间.exe` | ✅ |
| A6 | asar 完整 | 包里有 `.../files/app/resources/app.asar` | ✅ |
| A7 | 启动器在位 | 包里有 `./usr/bin/com.zspace.spark`，且 `files/run.sh` 可执行 | ✅ |
| A8 | `postrm` 清容器 | `dpkg-deb -I $DEB` 能看到 postrm，内容含 `~/.deepinwine/com.zspace.spark` | ✅ |
| A9 | 无提权操作 | `grep -E 'chmod 4755|chown root'` 在 run.sh/postinst/postrm 里均无命中 | ✅ |
| A10 | deb 文件名无中文 | 文件名是 `com.zspace.spark_<ver>-<rev>_amd64.deb` | ✅ |

## B. 启动器与中文渲染

| # | 检查项 | 怎么验 | 必须 |
|---|---|---|---|
| B1 | 脚本语法 | `bash -n` 过 run.sh / postinst / postrm | ✅ |
| B2 | 字体修正在位 | run.sh 含 `FONTCONFIG_FILE`、含 `wqy` 排除、含私有字体目录 `ZC_FONT_DIR` | ✅ |
| B3 | fontconfig 配置可生成 | 跑一次启动器后 `~/.deepinwine/com.zspace.spark/fontconfig.conf` 存在，且含 `zc-fontconf-v3` | ✅ |
| B4 | 坏字体不进字体表 | `grep -c wqy-microhei` 和 `grep -c NotoSansSC` 在 system.reg 里都为 0 | ✅ |
| B5 | 正文不是 Thin 字体 | 见下方"字面判定" | ✅ |
| B6 | `unset NODE_OPTIONS` | run.sh 里有，否则 Electron 会被当纯 Node 启动 | ✅ |
| B7 | `unset WAYLAND_DISPLAY` | run.sh 里有，否则 treeland 下窗口建不出来 | ✅ |
| B8 | 私有字体目录建成 | `ls ~/.deepinwine/com.zspace.spark/fonts \| wc -l` > 100，且里面**没有** `NotoSansSC-VF.ttf` | ✅ |

### 字面判定（B5 怎么验）

页面 CSS 的字体栈是坏的（全角逗号 `"Microsoft YaHei，Arial，Verdana，sans-serif"`），
Chromium 会走默认回退字体。判定目标是**回退结果不能是那个 Thin/Light 可变字体**。

唯一可靠的验法（CDP，Chromium 自己报）：

```bash
packaging/run.sh --remote-debugging-port=9222
# 连 page 的 ws，对正文元素调 CSS.getPlatformFontsForNode
```

判据：

- ❌ `Noto Sans SC` —— 这就是 `NotoSansSC-VF.ttf`（默认实例 Thin/Light），字细的元凶
- ✅ `Noto Sans CJK SC` —— 常规字重，当前目标
- ✅ `Microsoft YaHei` —— 也正常

辅助快验（只能证明坏字体不在字体表里，不能证明页面用了谁）：

```bash
grep -c 'NotoSansSC' ~/.deepinwine/com.zspace.spark/system.reg   # 应为 0
ls ~/.deepinwine/com.zspace.spark/fonts/NotoSansSC-VF.ttf        # 应不存在
```

## B'. 性能

| # | 检查项 | 怎么验 | 必须 |
|---|---|---|---|
| F1 | 启动参数在位 | run.sh 里有 `--disable-gpu-compositing`，且支持 `ZSPACE_GPU_COMPOSITING=1` 关掉 | ✅ |
| F2 | 帧率达标 | CDP 里跑 180 帧动画，等效 fps ≥ 58，p95 ≤ 20ms | ✅ |
| F3 | 空闲 CPU 合理 | 按 /proc 时间差采样 10s，全进程合计 < 15% | ✅ |
| F4 | 画面无异常 | 截图无黑块/花屏，中文正常显示 | ✅ |

## C. 安装与卸载

| # | 检查项 | 怎么验 | 必须 |
|---|---|---|---|
| C1 | 能装上 | `sudo apt install ./$DEB` 无报错 | ✅（需要 root，可请用户跑） |
| C2 | 能启动 | 从菜单点开，窗口正常出现 | ✅（需要用户确认） |
| C3 | 能卸载干净 | `sudo apt remove com.zspace.spark` 后 `~/.deepinwine/com.zspace.spark` 消失 | ⬜ 可选 |

## D. 记录

| # | 检查项 | 怎么验 | 必须 |
|---|---|---|---|
| D1 | 产物信息入档 | 路径 / 版本 / SHA256 / 源 exe 文件名 已写进 `.agents/memory.md` | ✅ |
| D2 | 本次偏差说明 | 如果流程和 `workflow.md` 不一致，写清原因 | ✅ |
| D3 | 版本表更新 | `.agents/sources.md` 的"当前已知版本"追加了本次版本 | ✅ |

## E. 可移植性（不绑死 deepin-wine）

| # | 检查项 | 怎么验 | 必须 |
|---|---|---|---|
| E1 | 依赖里没有 `deepin-wine-helper` | `dpkg-deb -I $DEB \| grep deepin-wine-helper` 无命中 | ✅ |
| E2 | 依赖含普通 wine 备选 | `dpkg-deb -I $DEB \| grep wine64` 有命中 | ✅ |
| E3 | 支持 `WINE=` 覆盖 | run.sh 里 `WINE` 环境变量分支存在，指定不存在的运行时会明确报错 | ✅ |
| E4 | 探测链含普通 wine | run.sh 的候选列表含 `wine64`/`wine`/`wine-stable` | ✅ |
| E5 | wineserver 归属正确 | `scripts/selftest_wineserver.sh` 全绿（5 个场景：包装脚本 / 普通 wine / symlink / 无配套 / 不存在） | ✅ |
| E6 | 非 Deepin 冒烟 | 在只装普通 wine 的发行版/容器里：能 `apt install`、能启动出窗口 | ⬜ 需真机/容器 |

---

## 结论模板（写进 memory.md 时用）

```
### 打包 YYYY-MM-DD <版本>-<rev>
- 产物：build/com.zspace.spark_<ver>-<rev>_amd64.deb
- SHA256：<...>
- 源包：packages/zspace_windows_<ver>_<ts>.exe
- 检查：A1..A10 全过 / B1..B7 全过 / C1 过（C2 待用户确认）
- 偏差：<无 / 具体说明>
```
