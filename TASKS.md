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
- 第 6、8、9、11、12、12b、13 条：待审。
- 第 14（含 20）、15、16、17、18、19、21 条：待审。

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
- [x] 8. 手机端 header 与 H1 间距：删掉 ≤820px 时把 hero 顶距压到 4px 的覆盖，回到与桌面相同的 16px；新断言在 390x844、375x667、320x700 下要求 ≥16px（旧样式 4px、失败），61% 纸面下限的既有断言仍通过。
- [x] 9. 房间顶栏 Buy 回到 D-115 的轻量样式（无填充、`--hair` 细边），落地页及其他页的 Buy 仍是 D-122 的实心墨色。phase4 断言房间 Buy 无填充（旧样式为墨色、失败）。
- [x] 10. 不改：停止屏角落的 `0 words` 是 D-043 明文写定的契约（「`0 words` after a wipe」），D-070 也保留了页脚；Mac 同样显示。只改网页会造成三端不一致，所以本轮不改。
- [x] 11. 警告句改为 Mac 的句子式 `Keep typing or the draft is deleted.`，去掉 .04em 字距（房间与演示同改）；phase4 断言 `text-transform:none`、`letter-spacing:normal`（旧样式 .04em、失败）；DESIGN.md §12 同步。
- [x] 12. `/download/`：文件名续行去掉 0.5ch 内缩，与 `shasum` 同一左缘；Copy 控件与下一段留 12px；`COPY`/`COPIED` 改为句子式 `Copy`/`Copied`（与房间的 `Copy text`/`Copied` 一致）。mac.spec 新断言在旧样式上失败（偏 3.9px、间距 0）。
- [x] 12b. 房间里浏览器「后退」：有字（或在 kept 屏）时，第一次后退把 `#trial` 推回历史并武装与 Esc 相同的确认，2 秒内第二次后退才离开；空房间照常直接离开。phase4 新用例在旧代码上失败（房间被隐藏）。
- [x] 13. 网页文档同步：`writeitdown/AGENTS.md` 改正 Buy 样式（D-122 墨色、房间内 D-115）、入口文案 `Start a free 60-second session`、FAQ 数量（6）、Pricing 卡结构、状态卡；README 入口文案。`tokens.json` 与看板在第 2、3 条已重导并由 `tokens-json.test`、`boards.test` 守住。

### C. macOS

- [x] 14. Mac 两种纸跟随系统外观（D-124）：Palette 只剩 white/black，只按 appearance 求解；删掉 Lamp/Paper/Slate、`PaperModeRepaint`、`PaperModeSwitch`、Settings 的 Paper 行、纸面纹理（`PaperField`、`PaperSheetCache`、`Turbulence`）与选择器预渲染；退出确认改为墨色；旧设置里的 `paperMode`/`theme` 读入即丢、不写回，试用次数与许可字段不变（`SettingsStoreTests` 8 种存档逐项断言）；外观切换不是输入（`PaperAppearanceTests`）；`DesignTokenTests` 改读 `writeitdown/tokens.css`，删除 `design/paper-tokens.css`（单一来源）；Mac AGENTS、`docs/wid-mac-behavior.md` 48/62/84/86/87、PLAN §6、Q-09/Q-22、根 AGENTS 同步。`swift test` 400 项通过；快照白/黑两纸已目检。
- [x] 15. D-126 焦点环：墨色主按钮与其他控件一样，用 3pt 外偏移的 2pt 墨色环（卡片上为页面墨、纸上为纸墨）；三个测试先在旧代码上失败；`swift test` 400 项通过；快照 `picker-focus`、`room-copy-focus` 白/黑两纸目检可见。
- [x] 16. 激活卡：Activate 药丸预留 `Activate`/`Activating`/`Begin` 中最宽的宽度；入口卡始终保留一行反馈高度，`Checking your license key…` 出现时卡片不动。新测试 `activatingMovesNothing` 在旧代码上失败（宽 +13pt、Buy 右移 7pt、卡片位移）。
- [x] 17. 结账不可用时状态行到 web 试用按钮的间距从 6pt 改为 20pt（与可结账时的说明行一致）；新测试在旧值上失败（6pt）。
- [x] 18. License 输入框：新增 `FirstLineTextField`（Controls.swift），文字与编辑光标都在垂直中线，画卡片自己的底色与 `hairStrong` 细边、8pt 圆角，不再用系统 roundedBezel；激活卡与 Settings 共用。新测试在旧字段上失败（有 bezel、上下差 16pt、无卡片底色）。
- [x] 19. Settings 行标签改句子式：`Reduced motion`、`Focus mode`、`Font size`，无障碍名同步；BatchFiveTests 断言旧写法不再出现（旧代码失败）。
- [x] 20. `SessionViewController.swift` L3 头注释：拒删提示位置改为 D-100 的「书写行下方」，并去掉换纸开关描述；并入第 14 条提交。
- [x] 21. 快照缺陷：(a) 会话条在窗口改尺寸后被重置为空，现于截图前重新 settle，并在每个运行中的房间状态断言纸顶 2pt 条为墨色（去掉 settle 时 4 处失败）；(b) 截图前统一跑一轮 runloop 再布局，kept 与 copy-focus 的标题顶端都在 114px；(c) checking 改为「存有 key、结果未知、检查进行中」的入口卡，断言 `licenseValidationInFlight && !hasFullAccess`，截图显示 `Checking your license…` 与禁用的 Buy。

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
