# macOS manual QA record

Use the batch-specific window checks in `WRITEITDOWN_PLAN.md` for current acceptance. The checklist below records the historical Zero Draft baseline and is not a release gate; dated records follow it.

## First launch
- Delete `~/Library/Application Support/First Line/Config/settings.json`.
- Launch the app.
- Confirm Home appears directly, with no Intro or warm-up screen.
- Confirm Home says `The first draft only moves forward.`
- Confirm Home says `Stop for 8 seconds and the page clears.`
- Confirm the primary action says `Give it sixty seconds.`.
- Confirm the microcopy says `No delete. No paste. No undo.`

## Returning launch
- Relaunch the app.
- Confirm the app opens on the same Home screen.
- Confirm Home has NO duration selection (fixed 60s), shows the core 8-second rule, and the primary action says `Give it sixty seconds.`.

## Keyboard navigation
- Press `⌘1` and confirm the app returns to Writing mode.
- Press `⌘0` and confirm Home opens.
- Press `⌘,` and confirm Settings opens only when no writing session is active.

## English keyboard
- Start session from Home.
- Type plain English text.
- Confirm input stays in the editor.
- Confirm Backspace / Delete / Paste / Undo do not rewrite prior text.

## Session feel
- Confirm the session ground is bone canvas with fossils visible in the gutters.
- Confirm the writing surface is a white paper column (stroked/shadowed, ~720pt) centered on the bone ground.
- Confirm top chrome uses a subtle progress line plus small timer text.
- Confirm multiline text still weakens older lines (zen rendering).
- Confirm danger turns the fossil layer red (opacity unchanged, color-only transition).
- Under reduced motion, confirm no fossil animation plays.

## Chinese IME
- Switch to Chinese IME.
- Compose pinyin, open candidate list, confirm a candidate.
- Confirm composition does not prematurely trigger failure.
- Confirm committed Chinese text remains in the editor.

## Failure path
- Start a session.
- Type at least one line, then stop typing for 8 seconds.
- Confirm Failure screen appears.
- Confirm the narrator line reads `Draft deleted. it joined the pile.` in red.
- Confirm no new draft text or draft file appears under `~/Library/Application Support/First Line/`.
- Return to Home and confirm the durable red aftermath line persists until the next session starts.

## Success path
- Complete a session countdown.
- Confirm Success screen appears.
- Confirm the primary `Copy full text` button receives focus.
- Confirm clicking Copy shows a `Copied.` feedback.
- Confirm no new draft text or draft file appears under `~/Library/Application Support/First Line/` after success.

## Settings
- Change theme.
- Confirm the duration row is informational only: `60 seconds. Fixed.` (no control).
- Change reduced motion override.
- With an active license, confirm Trial & License shows only the status line and metadata (no key field, no Activate button, no buy link, no prefilled key).
- With an inactive license, confirm the trial status, explanation, empty key field, Activate, and Open Buy page.

## Manual QA Record

### 2026-09-24 - writeitdown batch 3, brand and tokens

- `swift build` exit 0; `swift test` exit 0 (105 Swift Testing tests, 7 suites). Five batch-3 named filters and all 12 batch-2 named filters individually exit 0. The inherited storage-reference `! rg`, early-Finish `! rg`, and batch-3 brand/color `! rg` each exit 0 with no matches. `bash -n scripts/qa-window.sh` exits 0.
- The package target and executable are `WriteItDown`; the source path remains `FirstLine`. `Info.plist` carries the bundle metadata for the future packaged app. Dynamic light/dark colors and the site-derived placeholder icon are covered by token tests and assets, not by an installed-app screenshot.
- **Window QA pending independent Computer Use acceptance**: this background session cannot capture the screen or use System Events. `scripts/qa-window.sh 3` now describes start and room in light appearance, Settings in light, then Settings, start, and room in dark; it was not run here. A fresh graphical session must inspect those states and record screenshots and pass/fail. Finder identity, packaged About identity, and actual icon rendering remain batch-7 checks.
- Physical IME and frame-level feedback are not verified here; neither interaction changes in batch 3.

### 2026-09-24 - writeitdown batch 2, engine parity

- `swift build` exit 0; `swift test` exit 0 (93 tests in 5 suites). All 12 named batch-2 filters individually exited 0. The inherited storage-reference and price-literal `! rg` gates exited 0. Window QA is **pending independent Computer Use acceptance**; this background session has no screen capture or System Events permission and did not run `scripts/qa-window.sh 2`.
- The scripted window flow now clicks the primary start button, waits three seconds to capture the unchanged clock, then captures typing, warning, in-room wipe, restart, kept, and the missing early Finish button. Independent acceptance must inspect each image and confirm the wipe's unused time derives from deadlines rather than delayed sampling.
- Physical IME candidate selection and exact feedback frames remain not verified here.

### 2026-08-02

Debug build (`./.build/debug/FirstLine`)，light theme，真窗 1920x1054，ABC + Pinyin 输入源。截图存 `/tmp/flqa3/`。

- [x] Session: bone canvas ground、白纸 paper 列（720pt 居中、stroke + shadow）、zen 渲染可见（截图 03/20/21）。
- [x] Danger: fossil 层变红（纯颜色、opacity 不变）、veil 加强、倒计时 3 + `KEEP TYPING` 文案 + 红色 top hairline（截图 21）。
- [x] Deny 阻断: Cmd+z undo 与 Backspace 均被阻、文本不变（截图 22/23）。红色 narrator/shake/hairline 的状态驱动有单测覆盖（`EditorFocusTests`）；90ms/1.2s 视觉瞬时未用合成事件捕获（合成事件无权限点不到 90ms 窗口），留真机复核。
- [x] Failure: 8s 停笔 wipe + FailureView（`Draft deleted.`）+ wiped 文本进 fossil（截图 09/11）；返回 Home 后红色持久行 `Draft deleted. it joined the pile.` + fossil 保持（截图 10）。
- [x] Success: Cmd+Enter 完成 -> Success 卡（5 words + 预览 + 三动作 + Discard，主 Copy 聚焦蓝色 focus ring）；Copy full text 后 `pbpaste` 实测 = 原文（`deny check draft stays intact`）；markdown 已落盘 `~/Library/Application Support/First Line/Library/`（含 created_at/completed_at/duration/word_count 元数据）；`Copied.` 标签切换未直接观察（AX 按钮名为泛化 `button`，1.2s 窗口未捕获），留真机复核。
- [x] IME（拼音）: 真实组合 `上` 提交落字成功，marked text 渲染正常（截图 08）；组合期不误触发 failure。
- [x] 空 session: 60s 空文本到期 -> idle -> 自动回 Home（M-B2 修复实测）；截止瞬间迟到首输入正确裁决为 idle（无卡死 Session 面）。
- [ ] Reduced motion 视觉项: 未执行（留空）。
- [ ] Paste/Cut deny: 未执行（留空）。
- [ ] 980pt 最小宽度 fossil gutter 目测: 未执行（留空）。

#### Notes

- 合成 AX `click at` 无法聚焦编辑器（点 scroll area 后 `AXFocusedUIElement` 仍为 `AXWindow`）；`set focused of text area` 可正常聚焦。真机硬件点击需复核是否自动聚焦编辑器（AppKit NSTextView 在 ScrollView 内点击通常聚焦，但合成事件路径不等价）。
- session 开始时编辑器不自动聚焦（`AXFocusedUIElement=AXWindow`）。当前 UI 隐藏空草稿 Finish（wordCount > 0 门控），不影响功能；但作为「开场即写」体验，自动聚焦是后续候选改进（audit minor-deferred #3 已记录）。
- 长 keystroke 字符串在 System Events 下会丢空格（`keystroke "long string"`）；逐 key code 输入（key code 49 = space）正常。这是合成输入的已知限制，非产品缺陷。

### 2026-09-24 - writeitdown batch 1, storage removal

- Debug build: `swift build` exited 0; `swift test` exited 0 with 88 tests in 5 suites. All four named batch-1 filters exited 0, one test each. The expanded `! rg` storage-reference gate exited 0.
- Real-window QA: **not verified in this background session**. `scripts/qa-window.sh 1` built and launched the binary but System Events timed out (-1712) before the first capture. A direct `screencapture -x` returned `could not create image from display` (exit 1). No window screenshot was produced here. A fresh independent session subsequently accepted Batch 1 through authorized Computer Use in a graphical session; see the record below.
- Physical IME and exact deny feedback were not tested; neither changes in this batch.

### Independent acceptance - Batch 1 (2026-09-24, 118bc0e1db78ca04e6d59cb4a4510197a22c3420)

- PASS: `swift build` exit 0; `swift test` exit 0 (88 tests, 5 suites). Each of the four Batch 1 named filters exited 0 with one passing test. The negative `rg` check printed nothing (`rg` exit 1, negated exit 0).
- PASS: Computer Use real-window start (`shots/start.png`) and typed draft (`shots/typed.png`). The start page has no Library entry. An immediate Cmd+2 check within 455.496 ms kept the editor and text in place (`shots/command-two-immediate.png`). The earlier `shots/command-two.png` records an eight-second idle wipe during a slower call, not a shortcut failure.
- PASS: A fresh real-time 60-second run reached kept with only the Copy full text action (shown as `Copied.`) and Discard; no Copy for AI or Download .md (`shots/kept.png`). Discard then Cmd+, opened Settings, which has no Storage section and retains the trial/license controls (`shots/settings.png`, `Mac trial: 2 of 3 sessions used`).
- PASS: The isolated user home contained only `Config/settings.json`; no draft files or synthetic draft text were found after wipe and kept. The named kept/wiped tests also check that their isolated flows do not modify the real user root.
- NOT VERIFIED: Live license activation/revocation, physical IME, and a before/after runtime snapshot of the real user root. These are not Batch 1 window acceptance requirements.
- QA SCRIPT ISSUE: `scripts/qa-window.sh` assumes Return opens the room, but this version has no Return binding on Home. The authorized Computer Use acceptance used a click on the primary button instead. The script also uses System Events and screencapture, so it was not run in this Mini Computer Use session. Fix this acceptance harness separately; no Batch 1 product regression was observed.

Screenshot paths above are relative to `/Users/ichts/firstmate-homes/first-line/data/zd-wid-mac-b1-accept/` and the full independent report is `report.md` in that directory.

### 2026-08-05  -  Pure-AppKit rewrite

整个 app 从 SwiftUI 壳重写为纯 AppKit（SwiftUI 彻底退役，全仓 `grep import SwiftUI` = 0）；SessionEngine / AppendOnlyTextView / Infrastructure / Licensing / 全部 95 测试复用。Debug build，light theme，真窗。各态经守门狗启动（硬 12s auto-kill）+ 截图多模态目验，每态后查 CPU 无 loop。

- [x] **beep 根治（原核心痛点）**：进 session 后 `AXFocusedUIElement` 角色 = **AXTextArea**（不再是 AXWindow），打字落字、不再 NSBeep。修法：SessionViewController 在 viewDidAppear 稳健重试 makeFirstResponder（校验 firstResponder===textView 才停）+ didBecomeKey 兜底。
- [x] **卡死循环修复**：曾有一个 `_NSViewLayoutFeedbackLoop` 无限回环（FirstLineButton.updateLayer 在布局 pass 内设 contentTintColor）把机器 CPU 打到 98% 卡死；采样热栈定位后把 tint 移出 updateLayer，CPU 降到 <1%。教训：updateLayer() 绝不能设 content 属性。
- [x] **Session zen**：文字在白纸内、当前行锚 ~35%、前行淡、不溢出纸顶（单行 + 多行均验）。
- [x] **Fossils**：左右 gutter 宽短语（flipped NSView draw）；danger 时变红。
- [x] **Danger**：红 veil + 大倒计时 + `KEEP TYPING OR THE DRAFT IS DELETED` + 红 timer。
- [x] **Failure**：`Draft deleted.` + `You stopped for eight seconds. It joined the pile.` + Try Again / Back to Home + joined fossil。
- [x] **Success**：词数 + 草稿预览 + Copy full text / Copy for AI / Download .md / Discard；相位切换不再 0x0/残留（常驻容器 + 子 VC 切换）。
- [x] **Home**：fresh（标题/tagline/规则/License active/按钮）+ aftermath（红线 + margin fossil）。
- [x] **Settings**：Appearance/Session/Trial & License/Storage/About + Done。
- [x] **Upgrade**：trial 用尽 -> upsell + license 输入 + 激活 + 禁用 Buy + Back to Home。
- [x] **Library**：Cmd+2 -> 分栏列表（时间倒序）+ 详情 + Copy/Open/Reveal/Delete；持久化 session 可见。
- [x] `swift build` + `swift test` **95/8 全绿**贯穿每个重写阶段。

#### Notes

- 合成 keystroke 在应用获焦后可能被系统切回上次输入法（Pinyin）导致脏字；为干净自测在会话聚焦后强切 ABC（`TISSelectInputSource`）。这是自动化假象，非产品缺陷。
- SmokeFlowTests 里两个 wall-clock 重试测试（failedSaveRetries / concurrentFailingSaves）在机器重压下会 flake（已观察：并发启动多个 app 实例 + 编译时）；空闲重跑 0.05s 秒过。可改进：像 SessionEngine 那样注入时钟/scheduler 以去 wall-clock 依赖（既有小债，非本次引入）。
- 真机硬件点击、真 macOS IME 候选窗、reduced-motion 视觉项未用合成事件穷举，留真机复核。
- L3 头部的 “检查 CLAUDE.md” 旧约定已在 review round 1 清扫：23 个 Swift 头部统一改指 AGENTS.md（仓内仍无 CLAUDE.md）。

### 2026-08-05  -  Review round 1 (fix loop)

Reviewer 复审 pure-AppKit 重写后接受 1 个 BLOCKER + 4 个 FIX-NOW。Debug build，light theme，守门狗启动 + 截图多模态目验。修复提交：357a37f（BLOCKER + 描边）、280343d（Library + Settings + FirstLineMain 头部）。

- [x] **活动 session 草稿恢复（BLOCKER）**：Writing 中打字 -> Home -> 返回 Writing，草稿完整保留、与 engine 不分叉（截图 /tmp/restore-after-home.png）。修法：AppendOnlyTextView.loadRestoredText() 受控恢复入口（isRestoringProgrammatically + defer 复位），SessionViewController 仅在 engine 有稿且 editor 空时调用；用户 append-only 守卫语义不变（新测试验证恢复后 paste / cut / replaceCharacters 仍 deny）。
- [x] **描边 appearance-aware**：Session 白纸与 Finish 描边从一次性 cgColor 改为 FloodCanvasView updateLayer 重解析 + viewDidAppear 重设，浅 / 深主题切换正确。
- [x] **Library 布局**：正文顶对齐（FlippedDocumentView），不再沉底；操作栏 Copy Text + More 菜单（Open / Reveal / Delete），980pt 最小宽无裁切（截图 /tmp/lib-fix.png、/tmp/lib-more.png）。
- [x] **Settings license 状态**：active 仅显示 `License active.` + 元数据，无 key 输入框 / Activate / 明文（截图 /tmp/settings-active.png）；inactive 显示 trial 状态 + 说明 + 空 key 框 + Activate + Open Buy page（截图 /tmp/settings-inactive.png）。
- [x] **GEB 文档漂移**：apps/macos/AGENTS.md 改述纯 AppKit；FirstLineMain / SessionViewController 头部更新到当前职责；23 个 Swift 头部 CLAUDE.md 引用统一改指 AGENTS.md。
- [x] `swift build` + `swift test` 98/8 全绿（95 -> 98，新增恢复入口 + 守卫未削弱 + 空恢复 no-op 三测试）。

### Independent acceptance - Batch 2 (2026-09-24, 3f3fd31683b66a071b138028a8d9d1d8bc3c19b6)

- PASS: `swift build` exit 0; `swift test` exit 0 (93 tests, 5 suites). All 12 named Batch 2/deadline filters exited 0, each with one passing test. The inherited removed-symbol `! rg` and the additional early-Finish `! rg` both exited 0 with no matches. Logs: `logs/` alongside the independent report.
- PASS: On the Mini, Codex Computer Use targeted only the temporary FirstLine.app window. Clicking the start button entered the room; the clock stayed at `01:00` after three idle seconds (`shots/rest-entry.jpg`, `shots/rest-three-seconds.jpg`). First input started it (`shots/typed.jpg`, `00:58`). After 5.57 seconds idle the warning showed `3` (`shots/warn.jpg`); after 8.56 seconds the same room showed an empty editor and `DRAFT WIPED - 0:52 UNUSED. TYPE TO RESTART.` (`shots/wiped.jpg`). Typing restarted a fresh minute (`shots/restarted.jpg`).
- PASS: No Finish button was present. Cmd+Return did not complete an active session (`shots/command-return.jpg`). A full real-time minute with inputs less than five seconds apart reached kept with the complete 17-word draft and only `Copy full text` and `Discard` (`shots/kept.jpg`). The app was then quit via Computer Use.
- NOT VERIFIED: Physical IME candidate UI, a real 60-minute window, and signed Finder packaging. Their engine rules are covered by named tests where applicable. This is a temporary debug bundle, not a distribution build.
- HARNESS NOTE: `scripts/qa-window.sh 2` was not run because its System Events/screencapture capture route conflicts with the mandated authorized Mini Computer Use path. An equivalent real-window flow and screenshots were captured via Computer Use. The dark system appearance and legacy fossil treatment await the visual batches.

### Independent acceptance - Batch 2 (2026-09-24, 36943c795394dbfcf983ef03c21d87015d9ec7ae)

- PASS: `swift build` exit 0; `swift test` exit 0 (100 Swift Testing tests, 5 suites). All 12 Batch 2 named filters and seven additional targeted regression filters exited 0, one test each. The negative removed-symbol `rg` gate exited 0 with no matches. Evidence: `data/zd-wid-mac-b2-reaccept/logs/`.
- PASS: On the Mini, Codex Computer Use captured the FirstLine window only. The clock stayed at `01:00` after 3.054 seconds idle (`shots/rest-three-seconds.jpg`), started on first input (`shots/typed.jpg`), showed the warning at 5.579 seconds (`shots/warn.jpg`), and wiped in the same room at 8.569 seconds with `0:52 UNUSED` and 0 words (`shots/wiped.jpg`). Typing `new draft` restarted at 2 words (`shots/restarted.jpg`); Cmd+Return did not finish and no Finish button appeared (`shots/command-return.jpg`). A real 60-second run reached the kept screen with 21 words, Copy full text and Discard (`shots/kept.jpg`). An exhausted isolated trial reached Upgrade rather than bypassing the gate (`shots/mixed-restart.jpg`). Relative screenshot paths resolve under `data/zd-wid-mac-b2-reaccept/`.
- NOT VERIFIED: Physical Chinese IME marked-text warning/wipe, caret movement inside composition and blocking after commit. The available Computer Use typing submitted Latin text instead of creating candidates; the matching named filters passed. The live website counted `Hello 世界 こんにちは friend.` as 5 words (`shots/web-mixed.png`), but native Computer Use entered only `Hello friend.` (`shots/mixed-count.jpg`); same-sentence visual parity remains unverified. Engine Unicode word-count and reset filters passed.
- HARNESS NOTE: The original `scripts/qa-window.sh 2` uses System Events and screencapture and was not run because this acceptance required Mini Computer Use. An initial ephemeral Computer Use call was denied; a normal `gpt-5.6-sol` invocation completed the window QA. No background screenshot was used.

### Independent acceptance - Batch 3 (2026-09-24, 3b1694406b8ef0bedc30dc7a9cb467b2cbd4aff8)

- PASS: `swift build` exit 0; `swift test` exit 0 (106 tests, 7 suites). All five Batch 3 named filters passed separately (one test each). The negated legacy-brand/red `rg` check exited 0 with no matches. Logs are adjacent to this report.
- PASS: Real-window Computer Use captures in both appearances: light start `shots/01-light-start.jpg`, room `shots/08-light-room.jpg`, Settings `shots/03-light-settings.jpg`; dark start `shots/04-dark-start.jpg`, room `shots/05-dark-room.jpg`, Settings `shots/06-dark-settings.jpg`. The start screen has the WRITE_IT_DOWN mark, Newsreader headline, site deck, and `Give it sixty seconds.`; window and About display Write It Down. Settings explicitly reads Light or Dark in the respective captures. No visible old brand or legacy red in these states.
- PASS: Upgrade displays one-time `$4.99` (`shots/07-upgrade-4.99.jpg`). Light warning shows the site's alarm-colored numeral rather than the legacy red (`shots/09-light-warn.jpg`); exact light and dark token values are covered by named tests. Live website 1440x900 references: `shots/web-light.png` and `shots/web-dark.png`.
- NOT VERIFIED: Finder installation, packaged icon and bundle identity, notarization, physical IME, dark warning animation, and real checkout. These are not Batch 3 gates. Existing fossil/Abandon room details belong to Batch 4. `scripts/qa-window.sh 3` was not run because its System Events/screencapture route conflicts with the required Mini Computer Use route; equivalent six-state real-window QA was performed using Computer Use. System appearance was not changed. The temporary bundle and isolated homes were removed after the app quit.
