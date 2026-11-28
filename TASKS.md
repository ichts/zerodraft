# TASKS: 三端统一（白纸 / 黑纸、Allo）与细节修复

## PRD（哥，2026-11-27，原话按顺序）

1. 「不太喜欢 writeitdown.app 中间那个纸色，跟其他的不太配……现在就想弄成白色简洁的就好了」（语音转写曾误作「紫色」）
2. 「就按 zachery 的那个工作流，我们重新定义一下，然后让 Thinker 和 Codex 审查一下」
3. 「基本上是能用的，但有很多不好的细节……多验证，把网页端、macOS、Windows 三端好好结合起来，怎么统一，把细节都修好」
4. 「有两个模式就够了：白，或者黑」
5. 「看看 GitHub 的某些 PR，在这个纸色之前我们做过一个几乎纯白色的，挺够了，再加一个黑的就够了」
6. 「也许可以用这个字体：https://allo.joshpuckett.me/ ，还可以根据需求自己微调」

底稿：
- Artist 的三端审查，在 `.audit/artist-review.md`，不进 commit。
- Thinker 与 Codex 对上一版草案的审查。

## 假设（查不到原话支持的，取推荐项）

- A1 「zachery 的工作流」指本文件这套流程：TASKS.md、假设、四个顾问时刻。不是把 Zachary 前端规范整套套到页面上。所以本轮不换 Geist、不换图标、不删 `Why it works`、不删手写标题。
- A2 白纸参照 #70（9447d99）：纸 `#ffffff`，页 `#f7f7f5`，纸墨 `#1c1917`，hairline 加柔和阴影，无纹理。网页浅色在 main 上已是这一版（D-123），尚未部署。
- A3 黑纸是新定义，中性黑，不带暖棕；黑纸放在纯黑墙上，亮一档，纸才有边。最终数值见 D-124：白（墙 `#f7f7f5`、纸 `#ffffff`、墨 `#1c1917`、quiet `#3f3b36`、wash `#f2f2f2`/`#e6e6e6`、历史行 .22/.07、红 `#b00c15`），黑（墙 `#000`、纸 `#111`、墨 `#ededed`、quiet `#c2bfb7`、wash `#1b1b1b`/`#262626`、历史行 .17/.065、红 `#ff453a`）。Mac 白纸从 `#FDFDFB` 改为 `#ffffff`。
- A4 产品字体三端统一用 Allo。Mac 已在用（D-120）；网页在 D-119 用过，后被 D-121 退回。
  - 沿用 D-119 的调法：ROND 30，书写 410，标题 540，警告数字 360。中文用 Resource Han Rounded。Newsreader、Zhuque Fangsong 退役。
  - 落地页的红色手写 Reenie Beanie 保留（D-121 点名恢复；D-057 定它只属于落地页，不算三端不一致）。哥已在 Artideck 选定保留手写（hero-hand，2026-11-28）。
- A5 Mac 与 Windows 跟随系统外观：浅色是白纸，深色是黑纸。去掉 Lamp / Paper / Slate 开关。网页保留现有主题按钮，默认浅色。
- A6 根目录的 Zero Draft 站不在三端之内，本轮不动。它是否还在线上，未知，列入交付的未决项。
- A7 Windows 跳过 D-120，直接对齐本轮规范。先修好 token 生成器，再移植。
- A8 Windows 真机 vivobook-1 的 Smart App Control 会拦截新构建，而关闭它不可逆，本轮不关。没有真窗口时，Windows 的视觉条目和「100ms 内进房」证明不了，只能标 [!]，不写成已对齐。关 Smart App Control 或另找 Windows 机器，列进交付的未决项。
- A9 授权台数措辞：许可池 Mac 与 Windows 共用。公开网页统一「2 computers」（现有约 20 处已是，只改 `index.html` 一处）；Mac 应用内「2 Macs」，Windows 应用内「2 PCs」。
- A10 决策记录拆三条：D-124 纸张与外观跟随，D-125 字体，D-126 焦点环。纸张的提交不依赖字体的提交。
- A11 参考（哥睡前给）：Quiet.md（https://github.com/s1dashu/quiet-md）、MiaoYan（https://miaoyan.app/）。两者都是白 / 黑两种外观的安静写作工具，作为截图对照，不照搬。
- A12 本仓库规则禁止新分支：每条直接在 main 上 commit 并 push。
- A13 红色重做（哥在 Artideck 评论：「不太喜欢这个红色……包括 light 和 dark 的所有红色，都很奇怪」）。方案在画板第 2 轮：A 淡红 wash；B 灰 wash + 红色只留数字与手写（推荐）；C 无红。新红统一一个色相：浅色 `#b00c15`，深色 `#ff453a`，警告句用墨色。哥已在画板选定 B（red-b，2026-11-28）。B 的数字在最深一档上为 5.78:1（浅）/ 4.44:1（深），属大字（≥24px，WCAG 3:1），D-124 写明数字按大字门槛。

## 审查

Reviewer 改为本群「Gemini 审查」（哥 2026-11-28 指示，不再等 Codex）。
- 第 1、2（含 7）、3 条：Gemini 第 1 轮打回，修复随第 4、5 条一起提交，待第 2 轮复审。
- 第 4、5 条：待审。
- 第 6 条：待审。

## 清单

每条一个提交，每条有自己的断言或截图证据。

### 0. 先修线上丢稿

- [x] 0. 网页房间顶栏 Buy 改新标签打开；测试断言房间内每个外链都不离开房间。

### A. 规范

- [x] 1. D-124 纸张、外观跟随与红色（A3、A5、A13）写进 `docs/wid-decisions.md`。各面文档（`design/DESIGN.md`、`docs/ui-quality.md` Q-09/Q-22、根 `AGENTS.md`、模块 AGENTS）随各自实现条目同步，保持文档与代码一致。截图证据：Artideck 画板 `white-black-paper`（哥已看过并选定 B）。

### B. 网页

- [x] 2. 网页浅色按 D-124：灰 wash `#f2f2f2`/`#e6e6e6`（`--paper-wash` 自有值）、quiet `#3f3b36`、一个红 `#b00c15`（数字、手写、标签、hairline），警告句与退出确认用墨色，退役 `--red-soft`/`--red-deep`/`--paper-danger`；`paper.spec`、`moments.spec` 等改断言。
- [x] 3. 深色改黑纸（D-124：墙 `#000`、纸 `#111`、灰 wash、红 `#ff453a`）；退役纹理管线（`paper.js`、`paper-render.js`、worker、内联回写），同步 `install.sh`、`qa/test-install.py`、缓存清单、`paper.spec`、`history-fade`、`door-instant`；实测白→黑→白、刷新、缩放后的像素。
- [x] 4. D-125 + 网页字体换 Allo 与 Resource Han Rounded（取自 3984e24），手写体保留；同步 `fonts/build-fonts.py`、`fonts*.css`、`install.sh`、`typography.spec`、`shared-type-baseline.json`、D-109 中文冻结；截 hero 两版。
- [x] 5. Pricing 文案：价格、`no subscription`、`3 free sessions` 各说一次（事实行不再重复价格），`2 Macs` 改 `2 computers`（A9），两行内。按钮保留 `Buy for $4.99`：它出自哥合并的 #184，是最新认可版本，不按 D-114 改回 `Buy`。
- [x] 6. Pricing 标题与价格间距为 0：根因是 `.card p{margin:0}` 的优先级（0,1,1）高于 `.price-fig`（0,1,0），覆盖了 `margin-top`；选择器改为 `.mac-card .price-fig`。mac.spec 断言价格与标题间距 ≥16px，旧样式上为 0、失败。
- [x] 7. 三张状态卡统一中性底：并入第 2 条（退役 `--red-soft`/`--red-deep` 时必须一起改），断言在旧样式上已证明失败。
- [ ] 8. 手机端 header 与 H1 间距补足。
- [ ] 9. 房间写作 / 警告时 Buy 用 D-115 轻量样式。
- [ ] 10. 停止屏去掉角落 `0 words`。
- [ ] 11. 警告句改句子式 `Keep typing or the draft is deleted.`。
- [ ] 12. `/download/` 命令续行缩进、COPY 与下一段间距、`COPY` 改 `Copy`。
- [ ] 12b. 房间里浏览器「后退」会清空草稿（Codex 在第 0 条复审中发现，`room.js:369` 的 `hashchange`）：改为与 Esc 相同的两步确认，或说明为何不可行。
- [ ] 13. 网页文档同步：`writeitdown/AGENTS.md`、`docs/design-system/tokens.json` 重导、`docs/design/canvas.json` 看板。

### C. macOS

- [ ] 14. Mac 两种纸，跟随系统外观；删三纸、开关与 `PaperModeRepaint`；旧设置迁移逐项写明并测（`lamp`/`paper`/`slate`、旧 `light`/`dark`/`system`、首次安装；试用次数与许可字段不变）；切换不改草稿、焦点、计时；token 回到单一来源；`DesignTokenTests`、`PaperContrastTests`、`SnapshotTests`、`PaperModeTests`、`SettingsStoreTests` 按 A3 改；`docs/wid-mac-behavior.md` 换纸用例、`WRITEITDOWN_PLAN.md` §6、`apps/macos/FirstLine/AGENTS.md` 同步。
- [ ] 15. D-126 焦点环：白纸、黑纸、卡片上的主按钮聚焦都看得见。
- [ ] 16. Activate → Activating 宽度不跳、卡片不跳。
- [ ] 17. 结账不可用时 7pt 间距改 20。
- [ ] 18. License 输入框文字垂直居中，去冷灰 bezel。
- [ ] 19. Settings 标签句子式大写，accessibility label 同步。
- [ ] 20. `SessionViewController.swift` L3 头注释改正。
- [ ] 21. 快照缺陷：会话条没画出、kept 旧帧、checking fixture。

### D. Windows

- [ ] 22. 关窗保护：有稿时 Alt+F4 / ✕ 走两步确认（D-118），SYNC.md 加行。
- [ ] 23. `gen_tokens.py` 与字体派生读 Mac 新 Palette 与 Allo，`check_tokens.sh` 能跑，CI 在 PR 上执行。
- [ ] 24. Windows 对齐 D-124 / D-125：白黑两纸跟随系统、Allo、纸圆角 4、警告句、警告数字字形、kept 按钮字重、深色红字；SYNC.md 逐行。
- [ ] 25. kept 页 Ctrl+C 复制。
- [ ] 26. 复制失败显示 `Try copy again`。
- [ ] 27. Begin 后预热，100ms 内进房。
- [ ] 28. 激活卡不被裁。
- [ ] 29. 焦点环不读成双线。

### E. 验收

- [ ] 30. 三端逐屏验收与全部命令（根 `npm test`、`writeitdown npm run test:full`、`verify-writing-deadlines`、`swift build && swift test`、Windows `go test ./...` 与 `check_tokens.sh`），advisor 终审，验收表。
