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
- A3 黑纸是新定义，用中性黑，不带暖棕。页面色与纸色不同，纸才有边。数值来自 Thinker，已用 WCAG 与 oklab 公式复算，第 1 条在真实渲染上再测一遍，三端共用。
  - wash 规则不变：纸色与 `#c8392f` 在 oklab 里按 88% / 76% 混合。`--paper-wash` 用自己的值，不再借 `--red-soft` / `--red-deep`。
  - 白：
    - 墙 `#f7f7f5`，纸 `#ffffff`，墨 `#1c1917`，quiet `#3F3B36`，危险红 `#63140b`。
    - wash `#fce8e5`，深一档 `#f8d2cc`。quiet 在深一档上 7.98:1；原来的 `#48443E` 只有 6.94:1。
    - 历史行 .22 / .07，对比度 1.60 / 1.15。
  - 黑：
    - 墙 `#000000`，纸 `#111111`，墨 `#ededed`（16.1:1），quiet `#c2bfb7`，危险红 `#ffc2b4`。
    - wash `#251816`，深一档 `#391d1a`，对纸 1.10 / 1.23。
    - 历史行 .17 / .065，对比度 1.56 / 1.15。
  - Mac 的白纸从 `#FDFDFB` 改为 `#ffffff`。三端同一种纸用同一组值。
- A4 产品字体三端统一用 Allo。Mac 已在用（D-120）；网页在 D-119 用过，后被 D-121 退回。
  - 沿用 D-119 的调法：ROND 30，书写 410，标题 540，警告数字 360。中文用 Resource Han Rounded。Newsreader、Zhuque Fangsong 退役。
  - 落地页的红色手写 Reenie Beanie 保留（D-121 点名恢复；D-057 定它只属于落地页，不算三端不一致）。截图包里放 hero 两版（保留手写 / 全 Allo）给哥选。
- A5 Mac 与 Windows 跟随系统外观：浅色是白纸，深色是黑纸。去掉 Lamp / Paper / Slate 开关。网页保留现有主题按钮，默认浅色。
- A6 根目录的 Zero Draft 站不在三端之内，本轮不动。它是否还在线上，未知，列入交付的未决项。
- A7 Windows 跳过 D-120，直接对齐本轮规范。先修好 token 生成器，再移植。
- A8 Windows 真机 vivobook-1 的 Smart App Control 会拦截新构建，而关闭它不可逆，本轮不关。没有真窗口时，Windows 的视觉条目和「100ms 内进房」证明不了，只能标 [!]，不写成已对齐。关 Smart App Control 或另找 Windows 机器，列进交付的未决项。
- A9 授权台数措辞：许可池 Mac 与 Windows 共用。公开网页统一「2 computers」（现有约 20 处已是，只改 `index.html` 一处）；Mac 应用内「2 Macs」，Windows 应用内「2 PCs」。
- A10 决策记录拆三条：D-124 纸张与外观跟随，D-125 字体，D-126 焦点环。纸张的提交不依赖字体的提交。
- A11 参考（哥睡前给）：Quiet.md（https://github.com/s1dashu/quiet-md）、MiaoYan（https://miaoyan.app/）。两者都是白 / 黑两种外观的安静写作工具，作为截图对照，不照搬。
- A12 本仓库规则禁止新分支：每条直接在 main 上 commit 并 push。

## 清单

每条一个提交，每条有自己的断言或截图证据。

### 0. 先修线上丢稿

- [x] 0. 网页房间顶栏 Buy 改新标签打开；测试断言房间内每个外链都不离开房间。

### A. 规范

- [ ] 1. D-124 纸张与外观跟随：白、黑两组值（A3），Mac / Windows 跟随系统外观，取代关系（D-069、D-093 纹理纸，D-120 三纸与开关，D-123「Mac 等下次签名发布」一句）。同步 `design/DESIGN.md` §12、根 `AGENTS.md` 产品段、`docs/ui-quality.md` 相关条款。附 main 白纸警告帧截图。

### B. 网页

- [ ] 2. 白纸 wash 与 quiet 改到 A3 的值（`--paper-wash` 自有值，quiet `#3F3B36`）；`paper.spec` 改断言。
- [ ] 3. 深色改黑纸（A3）；退役纹理管线（`paper.js`、`paper-render.js`、worker、内联回写），同步 `install.sh`、`qa/test-install.py`、缓存清单、`paper.spec`、`history-fade`、`door-instant`；实测白→黑→白、刷新、缩放后的像素。
- [ ] 4. D-125 + 网页字体换 Allo 与 Resource Han Rounded（取自 3984e24），手写体保留；同步 `fonts/build-fonts.py`、`fonts*.css`、`install.sh`、`typography.spec`、`shared-type-baseline.json`、D-109 中文冻结；截 hero 两版。
- [ ] 5. Pricing 文案：价格、`no subscription`、`3 free sessions` 各说一次，按钮回 `Buy`（D-114），`2 Macs` 改 `2 computers`（A9）。
- [ ] 6. Pricing 标题与价格间距为 0 的根因修复。
- [ ] 7. 三张状态卡统一中性底；断言三卡底色相同、不等于 wash、无渐变，先在旧样式上失败。
- [ ] 8. 手机端 header 与 H1 间距补足。
- [ ] 9. 房间写作 / 警告时 Buy 用 D-115 轻量样式。
- [ ] 10. 停止屏去掉角落 `0 words`。
- [ ] 11. 警告句改句子式 `Keep typing or the draft is deleted.`。
- [ ] 12. `/download/` 命令续行缩进、COPY 与下一段间距、`COPY` 改 `Copy`。
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
