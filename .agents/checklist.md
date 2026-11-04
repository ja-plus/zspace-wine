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
| B2 | 字体修正在位 | run.sh 含 `FONTCONFIG_FILE`，且含排除 `wqy` 的逻辑 | ✅ |
| B3 | fontconfig 配置可生成 | 跑一次启动器后 `~/.deepinwine/com.zspace.spark/fontconfig.conf` 存在 | ✅ |
| B4 | 文泉驿不进字体表 | `grep -c wqy-microhei ~/.deepinwine/com.zspace.spark/system.reg` 为 0 | ✅ |
| B5 | 落到微软雅黑 | 见下方"字面判定" | ✅ |
| B6 | `unset NODE_OPTIONS` | run.sh 里有，否则 Electron 会被当纯 Node 启动 | ✅ |
| B7 | `unset WAYLAND_DISPLAY` | run.sh 里有，否则 treeland 下窗口建不出来 | ✅ |

### 字面判定（B5 怎么验）

应用 CSS 的字体栈是
`PingFang SC, Source Han Sans CN, WenQuanYi Micro Hei, Microsoft YaHei, sans-serif`。
目标是让中文落到 **微软雅黑**（与官方 Windows 客户端一致）。

最快的一种判定方式：起一个最小 Electron 窗口，用 canvas 把同一串中文分别按
`"Microsoft YaHei"` 和应用字体栈画出来，比对像素哈希是否一致。
（既有探针在 `/home/japlus/zs-fontprobe`，可复用。）

拿不到探针时，退而求其次：

```bash
grep -c 'wqy-microhei' ~/.deepinwine/com.zspace.spark/system.reg   # 应为 0
grep -c 'wqy-microhei' ~/.deepinwine/com.zspace.spark/user.reg     # 应为 0
```

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
