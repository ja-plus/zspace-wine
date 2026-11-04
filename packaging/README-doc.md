# 极空间 (Wine 版，非官方)

基于极空间官方 Windows 客户端 V2.46.2026101501，通过 deepin-wine 运行。
**程序文件为官方原始二进制，未做任何修改、剥离或替换。**

## 结构

| 路径 | 说明 |
|---|---|
| `/opt/durapps/com.zspace.spark/files/app` | 官方程序文件（V2.46.2026101501） |
| `/opt/durapps/com.zspace.spark/files/run.sh` | 启动器 |
| `~/.deepinwine/com.zspace.spark` | Wine 容器（首次运行自动创建，约 1.3 GB） |

## 首次启动

点图标即可。首次会自动初始化容器并把程序释放到 `C:\Program Files\zspace`，
实测约 20 秒完成，期间会弹出系统通知提示进度。之后启动约 5-10 秒。

## 已知问题与排查

### 中文「字体不太对」（笔画偏细、西文字宽偏窄）

应用的 CSS 字体栈是：

```
PingFang SC, Source Han Sans CN, WenQuanYi Micro Hei, Microsoft YaHei, sans-serif
```

Windows 上前两项不存在，最终用微软雅黑；而 Linux 桌面普遍装有文泉驿微米黑，
Wine 会让 Chromium 优先命中它，于是中文按「微米黑」渲染，与官方 Windows 客户端不一致。

启动器会给本应用的 Wine 进程单独注入一份 fontconfig 配置
（`~/.deepinwine/com.zspace.spark/fontconfig.conf`），其字体目录不含文泉驿，
字体栈自然回落到微软雅黑。**仅影响本应用，不改动系统字体设置。**

两个实测走不通的路子，避免重复踩坑：

- fontconfig 的 `<rejectfont>` 对 Wine 无效 —— Wine 直接取目录扫描结果，只能靠 `<dir>` 排除；
- Wine 的字体替换表 `HKCU\Software\Wine\Fonts\Replacements` 不作用于 Chromium 的 DirectWrite。

老容器（本次修正前创建）的注册表里已经写死了文泉驿条目，Wine 不会自己删，
启动器会自动清一次；若手动排查可看：

```sh
grep -c wqy-microhei ~/.deepinwine/com.zspace.spark/system.reg   # 正常应为 0
```

### 点了图标没反应

按顺序试：

```sh
# 1. 看启动器的真实输出
WINEDEBUG=err+all /opt/durapps/com.zspace.spark/files/run.sh 2>&1 | tail -30

# 2. 容器坏了就重建（不会丢数据，只是重置 Windows 环境）
rm -rf ~/.deepinwine/com.zspace.spark

# 3. 手动初始化容器
WINEPREFIX=~/.deepinwine/com.zspace.spark deepin-wine10-stable wineboot -u
```

### 报 `version mismatch 933/891`

不同 wine 版本共用一个前缀时，残留的 wineserver 会让客户端连不上。清掉即可：

```sh
WINEPREFIX=~/.deepinwine/com.zspace.spark deepin-wine10-stable wineserver -k
```

启动器已内置这一步，正常不会遇到。

### 报 `Cannot find module ... node-language-shim.cjs`

说明 `NODE_OPTIONS` 或 `ELECTRON_RUN_AS_NODE` 被透传进了容器，Electron 被当成
纯 Node 进程启动。启动器已 `unset` 这些变量；若你从某个 Electron 应用的终端里启动，
请先 `unset NODE_OPTIONS ELECTRON_RUN_AS_NODE`。

### 窗口不出现但进程在跑

本项目已在 **treeland (Wayland) + DDE** 环境实测通过。若你的合成器不支持 Wine 的
wayland 驱动，启动器已默认 `unset WAYLAND_DISPLAY` 走 XWayland。请确认 `XAUTHORITY`
可读（DDE 下通常是 `/run/user/<uid>/treeland-xauthority`）。

### 中文文件名

实测中文文件名（`极空间.exe`）在 wine 10/11 下均可正常启动，无需改名。

## 卸载

```sh
sudo apt remove com.zspace.spark
```

`postrm` 会清理 `~/.deepinwine/com.zspace.spark`，不留容器残留。

## 声明

未修改官方二进制，未绕过任何授权或服务端校验。
官方用户协议可能不允许此类再分发，仅供个人使用。
