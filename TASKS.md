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
- 第 22、23、24、25、26、27、28 条：待审。

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
- [x] 5. Pricing 文案：事实行不再重复价格与 `no subscription`；卡内 `$4.99` 出现两次（价格大字与按钮，D-127 例外）；`3 free sessions` 只在下载按钮上说一次，Mac app 事实行只说时长（Gemini 第 1 轮打回后修正）；`2 Macs` 改 `2 computers`（A9），两行内。按钮保留 `Buy for $4.99`：它出自哥合并的 #184，是最新认可版本，不按 D-114 改回 `Buy`。
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

- [x] 22. Windows 关窗保护：`Room.ConfirmClose` 在有活稿时拒绝第一次关闭并武装与 Esc 共用的确认，2 秒内再关才放行；空房间、停止屏、成稿屏直接关；`App.MayClose` 接到 `Window.OnClose`；SYNC 第 76 行。room 与 app 两个新测试在旧代码上编译失败（方法不存在）。真窗口验证待 vivobook-1（A8）。
- [x] 23. Windows 生成器与漂移检查：`gen_tokens.py` 改读 Mac 的 white/black Palette 与角色表（别名递归解析），历史行按纸取值，警告句取 `warningText`，删掉纹理常量；`gen_fonts.py` 从 Mac 的 `allo-latin.woff2`、`resource-han-rounded-gb2312.woff2` 派生 TrueType（两次生成逐字节一致）；`check_tokens.sh` 本机通过；CI 增加 push 到 main 的触发与 `writeitdown/tokens.css` 路径、安装 brotli。
- [!] 24. Windows 对齐 D-124/D-125：纸为纯色（删 `paper/` 纹理包与 `cmd/papershot`），颜色随生成的 token；书写、标题、警告数字换 Allo 410/540/360 与 Resource Han Rounded；警告句为 Mac 的句子式、不加字距；成稿屏按钮 15/600；纸圆角随 Mac 为 4；成稿块对齐 Mac 实测帧（标题 104、按钮 221..269、正文 331）。`go test ./...`、`GOOS=windows go build` 通过。
  - 未解决：没有真窗口（A8，Smart App Control），视觉对齐与 DirectWrite 下的字形未验证；界面 chrome 仍用 Segoe UI Variable（其行盒是按 Segoe 调过的，换 Allo 需真窗口度量，SYNC 第 22 行记为 different）；真机脚本 `scripts/measure.py` 仍按 Wheat 纸取样，需在真机可用时改写。
- [x] 25. Windows 成稿屏 Ctrl+C：无论哪个成稿按钮有焦点，Ctrl+C 都复制全文（`c.Shortcut(ui.Cmd, ui.KeyC)`），与 Mac 的 Cmd+C 一致；SYNC 第 73 行。
- [x] 26. Windows 复制失败：`Config.Copy` 返回剪贴板是否真的持有全文（默认写入后读回比对），失败时显示 `Try copy again` 并朗读；SYNC 第 11 行。新测试在旧代码上编译失败、再在未接线时失败（复制 0 次）。
- [!] 27. Begin 100ms 内进房：350-390ms 的来源是同步生成纸面纹理，第 24 条去掉纹理后已不存在（SYNC 第 17 行）。未解决：没有真窗口测时（A8）。
- [!] 28. Windows 激活卡被裁：最小窗口高度从 480 提到 560（`app.MinWindowHeight`，main.go 引用同一常量），按 Artist 在真机上估算的 468 / 485 DIP 留出内容区；新测试 `TestTheActivationCardFitsTheMinimumWindow` 断言卡片在最小窗口内完整；SYNC 第 32 行。
  - 未解决：无头渲染（macOS 上的 CoreText 字体度量）里卡片只有约 425 DIP，旧值 480 也能通过，测试证明不了真机上的裁切；需在 vivobook-1 上量（A8）。
- [!] 29. Windows 焦点环读成双线：mygo 自带的外环与 CrychicUI 药丸边线叠在一起（SYNC 第 27 行记为 mygo 做不到）。本轮未改代码。
  - 未解决：只能在真窗口上判断改法是否生效（A8），且需要动 CrychicUI 的钉版或主题，超出可无窗口验证的范围。

### E. 验收

- [!] 30. 验收（2026-11-28，main `77f6399`）：根 `npm test` 21 passed；`writeitdown npm test` 353 passed（92b9ded 后），全矩阵 1376 passed（a33ed72）；`verify-writing-deadlines` 0 failures；`swift test` 404 passed；Windows `go test ./...`、`GOOS=windows go build`、`check_tokens.sh` 通过。Gemini：第 1–37 条全部通过（第 1–3、5、13–16、23、24、36 条经打回后复审通过）。Thinker 终审的 4 个取舍判断成立，其指出的漏项已作为第 31–35 条修完并经 Gemini 复审；修完后未再请 Thinker 复核（唤醒次数用尽）。
  - 未解决：(1) Mac 真窗口：cua-driver 守护进程与 TCC 权限待哥授权；(2) Windows 真窗口：A8（Smart App Control）；(3) GitHub 上 `windows`、`writeitdown` 两个工作流 disabled_manually，CI 不运行；(4) 部署由哥手动。

### F. 终审补漏（Thinker 2026-11-28）

Gemini 第 1 轮（第 1–28 条）：通过 1、2、3、4、6、8、9、10、11、12、12b、17、18、19、20、21、22、25、26、27、28；打回 5、13、14、15、16、23、24，修复在 `1c4e019`（5、13、14、16）、`9ccecbb`（15 的文档）、`2418be2`（24 的退出确认）和本节之后的 Windows 字体提交（23、24 的族名与可变轴、数字字重）。

- [x] 31. 网页成稿屏 `Copy text` 焦点环：`.home .room-primary` 仍用 `--on-ink` 内环，白纸 / 黑纸上 1.00:1 看不见；改为与 D-126 同样的 3px 外偏移墨色环，`phase4.spec` 改断言（偏移 3px、颜色等于墨色；旧样式 -2px 失败）。
- [x] 32. Windows 退出确认用墨色（D-124），不再用 `PaperDanger`；像素测试 `TestTheArmedExitConfirmationIsInk` 在旧代码上读到红色像素、失败。
- [x] 33. Windows 同步 Mac 第 16、17 条：结账不可用时间距 20；Activate 预留最宽标签；入口卡反馈行预留一行。`TestTheActivationCardMovesNothingWhenItAnswers` 在旧代码上两处都失败（宽 106.7 < 120.2；web trial 435.8 → 451.5）；间距 20 是常量改动，无头测试量不出 pill 内文字的上边，未单独断言。SYNC 第 77 行。
- [x] 34. 决策与文档：D-125 改正 Windows 只换了书写/标题/数字三个角色；记录 Pricing 按钮 `Buy for $4.99` 的例外（D-127）；第 5 条措辞改正（卡内 `$4.99` 与 `3 free sessions` 仍各两次）；同步 `docs/ui-quality.md` Q-13/Q-22/Q-23/Q-34、`docs/wid-mac-behavior.md` 39/50、FirstLine AGENTS、writeitdown AGENTS、Windows SYNC 9/25/74/75。
- [x] 35. `qa-window.sh` 的警告句断言改为句子式（4 处），`bash -n` 通过；PLAN 里对脚本断言的描述同步。脚本本身要等 cua-driver 授权后才能实跑。

### G. 哥在字体画板上的决定（2026-11-28）

- [x] 36. （Gemini 第 1 轮打回 4 处漏改，已在下一提交修：mac.html、免费试用答案页正文与 JSON-LD、Q-28、README 发布第 2 步）下载页删掉 SHA-256、`shasum` 命令与两个 Copy 控件（D-128）；`release-check.mjs`、`journey.mjs`、`dmg-journey.sh`、`llms.txt`、README、AGENTS 同步；mac.spec 断言页面不含 `SHA-256`/`shasum`/复制控件（旧页面失败）。
- [x] 37. 等宽改用 Paper Mono（D-129，哥选定）：自托管 `fonts/paper-mono.woff2` 与 OFL，`--mono` token；`mac.html` 许可证 Key 与文档页 `code` 用它（原先 `.license-key code{font:inherit}` 让 Key 落在 Allo）；新测试在旧样式上失败；install 清单、test-install、DESIGN §12、Q-23、AGENTS 同步。写作与标题保持 Allo（哥选定）。

### H. Calm 配色（D-130，哥在画板第 3 轮选了参考 Incipit 的一套）

- [x] 38. D-130 决策记录：两种纸的结构不变，色值改为暖白 / 暖炭、降一档的墨、灰玫瑰红；纸上文字在最深 wash 上 ≥7:1，历史行按 D-092 目标重解。
- [x] 39. 网页按 D-130 改 token 与测试。
- [x] 40. Mac 按 D-130 改 Palette 与测试。
- [x] 41. Windows 重新生成 token，测试同步。
- [x] 42. 红色在 Calm 底色下重选（Thinker：`#9a5255` 色相偏冷粉、浅色小字 5.05:1）。画板第 4 轮 A 暖朱砂 `#9a3326`/`#ec8878`、B 柔赤陶 `#924138`/`#dd8b81`、C 现值；等哥 Submit 后三端换值，新决策取代 D-130 的红。
  - 哥选 A（第 4 轮）。D-131 落三端（92ef548），Gemini 审查通过。

