# zspace-wine

把**极空间 Windows 客户端**打成 Linux deb，用 deepin-wine 跑起来。
官方出新版时，一条命令下载 + 一条命令重新打包。

> **这个项目推荐交给 AI Agent 维护。**
> 目录里有 `AGENTS.md`（Agent 的行为契约）和 `.agents/`（规则、流程、清单、记忆）。
> 用支持 AGENTS.md 的 Agent 打开本目录，它会自动接手"查新版 → 问你要不要下 → 打包 → 自检"这一整套。
> 你自己只需要做决定，不用记命令。

---

## 你需要知道的三件事

1. **本项目只做包装，不改官方的东西。**
   安装包来自极空间官网，deb 里装的就是官方原始二进制。
2. **产物只供个人使用。**
   官方用户协议可能不允许再分发；要公开发布请先自行确认授权。
3. **打包脚本自带体检。**
   包结构、启动器、中文字体修正、上架红线……任何一项不过都不会产出 deb。

---

## 如果你想自己动手

```bash
# 1. 看看官方有没有新版（一天只查一次接口）
scripts/check_update.sh

# 2. 下载最新安装包到 packages/
scripts/download.sh
#    手动下载的也行：scripts/download.sh --file ~/下载/xxx.exe

# 3. 打包
scripts/build_deb.sh

# 4. 装
sudo apt install ./build/com.zspace.spark_<版本>-<修订>_amd64.deb
```

首次启动会自动初始化 Wine 容器（约 1 分钟），之后启动约 5–10 秒。

---

## 如果你交给 AI Agent

打开目录后 Agent 会：

- **第一次对话前**就去查官方版本；
- 本地没有安装包 → 问你要不要下载；
- 本地有包但官方出新版了 → 问你要不要下载（**每天最多问一次**）；
- 你说"打包" → 如果有新版会先问你用旧包还是新包；
- 打包结束后**逐项跑验收清单**，不通过就不算完成，并把结果记进 `.agents/memory.md`。

细节见 [`AGENTS.md`](AGENTS.md)。

---

## 目录

| 路径 | 说明 |
|---|---|
| `AGENTS.md` | Agent 的行为契约，必读 |
| `.agents/` | Agent 参考资料：记忆、流程、验收清单、官方接口 |
| `scripts/` | 三个脚本：查版本 / 下载 / 打包 |
| `packaging/` | deb 的静态素材（启动器、postinst、图标…） |
| `packages/` | 安装包存放（不进 git） |
| `build/` | 打包产物（不进 git） |
| `.state/` | 版本检查缓存（不进 git） |

## 依赖

`7z`、`dpkg-deb`、`curl`、`python3`、`xz`；运行时需要 `deepin-wine10-stable`（或 11/8）。

## 已知限制

- 设备发现、外网穿透、同步、盘符挂载、原生播放器在 Wine 下不可用
 （客户端依赖的 `libzrpc_x64.dll` 只有 Win/mac 版本）。
- IP 直连（端口 5055）可用，日常够用。
- 透明窗口（托盘弹窗、桌面歌词）在 Wine 下是黑底，属于 Wine 缺 DWM 合成，无解。

## 卸载

```bash
sudo apt remove com.zspace.spark
```

`postrm` 会清掉 `~/.deepinwine/com.zspace.spark`。
