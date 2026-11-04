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
