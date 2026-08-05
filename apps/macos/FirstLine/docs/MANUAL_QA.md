# First Line MVP - Manual QA Checklist

Use this checklist before direct distribution.

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
- Confirm no new markdown file appears in Library.
- Return to Home and confirm the durable red aftermath line persists until the next session starts.

## Success path
- Complete a session countdown.
- Confirm Success screen appears.
- Confirm the primary `Copy full text` button receives focus.
- Confirm clicking Copy shows a `Copied.` feedback.
- Confirm markdown file exists in `~/Library/Application Support/First Line/Library/`.

## Settings
- Change theme.
- Confirm the duration row is informational only: `60 seconds. Fixed.` (no control).
- Change reduced motion override.
- Use Reveal Library Folder.

## Library
- Open Library.
- Confirm reverse chronological order.
- Open detail view.
- Verify Copy Text / Open in Default Editor / Reveal in Finder / Delete.
- Delete one item and verify file removal from disk.

## Manual QA Record

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
- L3 头部的 “检查 CLAUDE.md” 为旧约定（仓内无 CLAUDE.md）；按 GEB 协议应指向最近 AGENTS.md，留为 bounded follow-up（不在本次重写范围）。
