# AGENTS.md —— 极空间 Wine 打包项目

> **这个仓库优先由 AI Agent 维护。** 人负责做决定，Agent 负责执行、自检和留痕。
> 你（Agent）读完这份文件就可以开始工作；细节规则在 `.agents/` 里的分散文件中。

---

## 0. 开工前必读

| 文件 | 作用 | 什么时候读 |
|---|---|---|
| `.agents/memory.md` | 跨会话记忆（做过的决定、产物记录、踩过的坑） | **每次会话开始** |
| `.agents/sources.md` | 官方接口、版本来源、字段含义 | 需要查版本/下载地址时 |
| `.agents/workflow.md` | 打包与发布的标准流程 | 要打包时 |
| `.agents/checklist.md` | 产物验收清单 | **打包结束后必须逐项过** |

---

## 1. 会话开始时的行为（响应用户第一个问题之前）

**先跑版本检查，再开口。** 不要等到用户问"有没有更新"。

```bash
scripts/check_update.sh          # 内部有 24 小时缓存，同一天重复调用不会打接口
```

按输出里的 `STATUS` 决定怎么问用户。**只问一次，一句话 + 选项，不要长篇：**

| `STATUS` | 你的动作 |
|---|---|
| `no-package` | 问：「本地还没有 Windows 安装包（官方最新 V2.46.x），要我现在下载吗？」选项：A 下载 / B 我自己手动下载 / C 先跳过 |
| `newer-available` | 问：「官方有新版本 V2.47（你本地 V2.46），要下载吗？」选项：A 下载 / B 先用本地的 / C 先跳过 |
| `up-to-date` | **不要打扰用户**，直接进入正题 |
| `local-newer` | 提示一句「本地包比官方还新，确认来源」，然后继续 |

拿到用户答复后再继续处理他原本的问题。
用户如果明确说"先跳过"/"不用"，本会话内不要再重复问同一件事。

### 每天只问一次

`scripts/check_update.sh` 自己管缓存（`.state/update.json` + `.state/update.checked-at`）。
你不需要额外判断"今天问过了没有"——**同一天里再次调用会拿到缓存，`STATUS` 不变时保持沉默。**
跨天后再问。

### 手动下载也算

用户如果自己从浏览器下了 exe，用这个把它收进项目：

```bash
scripts/download.sh --file ~/下载/xxx.exe
```

---

## 2. 用户说「打包 / 打个 deb / 做个安装包」时

### 2.1 先确认版本（这是硬规则）

```bash
scripts/check_update.sh --force
```

- `STATUS=newer-available` → **必须先问**：
  「官方有 V2.47，你本地是 V2.46。A 用本地包打 / B 先下载新包再打」
  **不许替用户决定，也不许静默用旧包。**
- 其它状态 → 直接打。

### 2.2 打包

```bash
scripts/build_deb.sh              # 用 packages/ 里版本最高的包
scripts/build_deb.sh --file <exe> # 指定包
scripts/build_deb.sh --rev 2      # 指定 Debian 修订号（默认 1）
```

脚本自己会做体检：asar 是否可读、Electron 运行时文件是否齐全、
启动器语法、中文字体修正是否还在、有没有违规提权、包体结构是否合规。
**任一项不通过它就不会产出 deb。**

### 2.3 你对产物负责

打包脚本返回成功 ≠ 任务完成。你必须：

1. 逐项过 `.agents/checklist.md`，把结果如实记下来；
2. 有任何一项没过 → **修到过，或者如实告诉用户没过**。
   **绝对不许说"打包完成"却没跑完检查。**
3. 把产物路径、版本、SHA256 写进 `.agents/memory.md`（格式见该文件）。

---

## 3. 事实与口径

- 本项目**只做包装**：拿官方 Windows 安装包，用 deepin-wine 跑起来，
  打成符合星火规范的 deb。**不修改、不破解、不替换官方二进制。**
- 星火上架红线（详见 `.agents/workflow.md`）：
  - 装到 `/opt/durapps/<包名>/`
  - 包名必须以 `.spark` 结尾，desktop 名必须等于包名
  - `postrm` 必须清理 `~/.deepinwine/<包名>`
  - 禁止 `chmod 4755` / `chown root`（ssinstall 会拒绝提权）
  - deb 文件名不能有中文
  - 商业软件只能投稿官网可免费下载的版本，**不得改动官方二进制和配置**
- 官方用户协议可能不允许再分发，**本项目产物只供个人使用**。
  用户要公开发布前，提醒他自行确认授权。

---

## 4. 禁止事项

- 不要在没问过用户的情况下自动下载大文件（>100 MB）。
- 不要在没跑 checklist 的情况下宣称产物可用。
- 不要删 `packages/` 里的安装包（那是用户攒的离线物料），除非用户明确要求。
- 不要把 `*.exe`、`build/*.deb` 提交进 git（见 `.gitignore`）。
- 不要改 `packaging/run.sh` 里的字体修正逻辑而不重新验证中文渲染。

---

## 5. 目录一览

```
zspace-wine/
├── AGENTS.md            ← 你在读的这份，Agent 的行为契约
├── README.md            ← 给人看的
├── .agents/             ← Agent 的参考与记忆
│   ├── memory.md        跨会话记忆（追加式）
│   ├── workflow.md      打包/发布标准流程
│   ├── checklist.md     产物验收清单
│   └── sources.md       官方接口与字段含义
├── scripts/
│   ├── check_update.sh  查官方最新版本（每日一次缓存）
│   ├── download.sh      下载 / 导入安装包到 packages/
│   ├── build_deb.sh     打 deb + 自检
│   └── common.sh        公共函数
├── packaging/           deb 的静态素材（run.sh / postinst / postrm / 图标 …）
├── packages/            安装包存放（不进 git）
├── build/               打包产物（不进 git）
├── .state/              版本检查缓存（不进 git）
└── logs/                运行日志（不进 git）
```
