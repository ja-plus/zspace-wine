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
4. **中文字体修正**：注入排除「文泉驿微米黑」的 fontconfig，
   让应用字体栈回落到微软雅黑（详见 `run.sh` 内注释与 `.agents/checklist.md`）
5. 首次运行初始化 Wine 容器，等待 `system.reg` 落盘（`wineboot` 是异步的，必须轮询）
6. 清理老容器里遗留的 `wqy-microhei` 注册表条目（**清之前要先让 wineserver 退出**，
   否则它退出时会把旧注册表写回文件）
7. 释放程序文件到 `C:\Program Files\zspace`（约 850 MB）
8. `exec` 启动 `极空间.exe`

### 中文字体修正的坑（已踩实，勿重走）

| 无效做法 | 原因 |
|---|---|
| fontconfig `<rejectfont>` | Wine 用目录扫描结果（`FcConfigGetFonts`），不经过 query 过滤 |
| `HKCU\Software\Wine\Fonts\Replacements` | 不作用于 Chromium 的 DirectWrite |
| `--enable-lcd-text` / `FontSmoothing*` / `Antialias`/`Gamma` | Chromium 用 Skia 自绘，截图逐像素无变化 |
| fontconfig `target="scan"` 改字体名 | fc-list 能看到，Wine 不认（字面名取自 FreeType） |
| `Software\Wine\Fonts\LogPixels` | Wine 每次从 X 重新推导 DPI，会被覆盖 |

**唯一有效**：注入 `FONTCONFIG_FILE`，配置里 `<dir>` 只收"直接含字体文件或叶子目录"的路径，
从而排除 `/usr/share/fonts/truetype/wqy`。必须在 `wineboot` 之前 export。

## 4. 发布

本项目**不自动发布**。产物只在本地 `build/` 里。

- 用户要装：`sudo apt install ./build/com.zspace.spark_<ver>-<rev>_amd64.deb`
- 要投星火商店：让用户自己走投递流程，并提醒他确认官方授权。
  **Agent 不要代为上传。**

## 5. 版本号约定

- deb 版本 = `<官方版本号>-<修订号>`，例：`2.46.2026101501-1`
- 官方版本号变 → 修订号从 1 重新开始
- 同一官方版本下，打包脚本/启动器有改动 → 修订号 +1（`--rev N`）
