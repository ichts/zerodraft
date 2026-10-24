# macOS manual QA record

Use the batch-specific window checks in `WRITEITDOWN_PLAN.md` for current acceptance. The checklist below records the historical Zero Draft baseline and is not a release gate; dated records follow it.

## 2026-10-23: Configured purchase build, no real-window acceptance

- `swift build && swift test`: exit 0, 198 tests in 16 suites. Existing signed Ed25519 fixtures exercise activation, product/device binding, expiry, persistence and revocation through the unchanged token verifier and HTTP client. The exhausted-trial Buy test now clicks the enabled control through an injected URL opener and verifies the public purchase page; it never opens a real checkout.
- `scripts/release-dmg.sh`: exit 0. The app and DMG are Developer ID signed, notarized, stapled and accepted by `spctl`. A read-only mount confirms the service URL, product ID, deployed public key, purchase URL and $4.99 price inside the image. DMG SHA-256: `714822ee9a5a80807c6ca42461fc12100e04892bf7a821c59c7bb011534f819a`.
- `python3 scripts/test-release-config.py`: exit 0; executes the packager in a sandbox, proving empty/incomplete/unsafe release configuration is refused before building or signing.
- This delivery is the integration. Installed-DMG TEST acceptance is pending and assigned to the maintainer, who deploys from another machine and then runs the real TEST card journey on the live site with a real installed DMG before LIVE. No GUI capture, screen-recording permission change, Finder installation, real payment or deployment was attempted here. Maintainer acceptance includes the returned key, clean-login Finder install/first launch, three-session exhaustion, real-window activation, second/third-Mac limits and refund revocation. Local signed-token tests do not establish that purchase loop. Keep LIVE disabled until it passes. TEST and LIVE must keep the same signing key and signed-token product ID so no new DMG is needed.

## 2026-10-22: Last-trial abandon, idle editor clear, and full-tree wipe wait

This revalidates the three-session native trial after review closed the last-trial activation gate. Exhausted or revoked restart now abandons the charged session before Upgrade, so Settings and writing menus stay locked. The room editor clears on idle or denied prepare, so a late keystroke cannot keep the wiped draft. Wipe waits in `scripts/qa-window.sh` poll the full AX tree; a no-match driver query had returned an empty tree and stalled the last-trial snapshot even though the room had already deleted the draft. The site, checkout configuration, and signed-license predicates are unchanged.

- `swift build && swift test`: passed, 198 tests in 16 suites (`swift test --list-tests`). Coverage includes last-trial nonempty restart to Upgrade with `phase == .idle`, idle/denied editor clear, and revocation blocking both a late keystroke and IME after wipe.
- `WID_QA_LICENSE_ONLY=1 WID_QA_THEME=light scripts/qa-window.sh <output>`: passed, 42 captured stages. The same command with `WID_QA_THEME=dark`: passed, 42 stages. Both package an ad-hoc app, use an isolated home and a disposable loopback signing fixture, and prove an empty room costs nothing, three real-input sessions spend the budget (Home 3/3, 2/3, then 1/3), the last wipe stays in-room with `DRAFT DELETED AT 0:08. ACTIVATE TO KEEP WRITING.`, the next keystroke and a restart open the existing activation screen with the full web-trial link, fixture activation opens the editor, offline validation retains access, and an explicit refund returns to activation without restoring the budget. They do not prove a genuine Waffo purchase. Evidence is local under `~/.no-mistakes/evidence/01M5HP1Q4R8NH7MXKFP8MQVY14/qa-license-light/` and `qa-license-dark/`.
- Inspected the light and dark screenshots for fresh Home, empty/unspent room, trial 1/2/3 Home and input, last wipe, exhausted activation, licensed Home, paid editor, offline Home/room, and refunded activation. Copy fits the existing AppKit layout; native focus remains visible on the duration `1` button and the order field. Checkout stays closed (`Checkout is not available yet.`). The scripted `a` can show a spelling or composition underline and `0 WORDS`; the session is still spent, matching first-input IME activity. Escape is not used to leave a room that may have active composition; the script clicks `ESC - EXIT`. This is not a Japanese IME acceptance result.
- `shellcheck scripts/qa-window.sh`, `bash -n scripts/qa-window.sh`, `go vet scripts/qa-license-fixture.go`, `plutil -lint Sources/FirstLine/Info.plist` and `git diff --check`: passed.
- Unverified release prerequisites remain: real Waffo test purchase, signed callback, buyer-visible credential activation and refund trace. Checkout URL, service URL, product ID and public key remain empty. No DMG build, upload, deployment or merge was performed. Full timing-sensitive real-window warn/recovery/wipe/kept-copy and Settings inspection were not run in this license-only pass; deterministic engine and AppKit view tests cover those paths but are not independent real-window acceptance.

Bounded follow-ups, not claimed fixed here:

- [ ] Reproduce and classify the prior RC report's 5/1077 per-key frame-match misses using an independent native capture run.
- [ ] Run real Japanese IME candidate selection, commit, cancellation, first-input trial charge, warning recovery and wipe/restart in a signed app. Direct `setMarkedText` tests and synthetic key delivery do not prove this.

## 2026-10-21: Mac-only three-session trial before signed activation

This supersedes the paid-only policy below. The site is unchanged. Only Mac trial behavior and the typing-origin/wipe-reset fix were ported from the free-trial branch; no release-mode switch, trial-ended controller, icon, DMG or website redesign was carried.

- Smallest safe design: `AppState` shares one trial-or-license gate across navigation, menus and first input. `SettingsStore` saves one of three usages before accepting the first nonempty committed text or IME activity, once per session. Empty rooms and blocked actions do not spend a session. Failed persistence rejects input with a visible error. Existing license records cannot fall back to a trial. `hasFullAccess`, the Waffo client, signed-token verification, activation rollback and refund handling are unchanged. The existing activation controller follows exhaustion; no second payment path was introduced.
- `swift build && swift test`: passed, 195 tests in 16 suites. Added real AppKit editor coverage for trial consumption, composition, exhaustion/restart, last-session danger recovery and completion, Settings round trips across the final wipe/completion, persistence failure, corrupt usage, activation and refund denial. Imported geometry tests first failed against the baseline's moving/centered writing origin, then passed with the fixed left origin and bottom-edge scrolling. The wipe clock and input hint now rearm in the same room.
- `WID_QA_LICENSE_ONLY=1 WID_QA_THEME=light scripts/qa-window.sh <output>`: passed, 28 captured stages. The same command with `WID_QA_THEME=dark`: passed, 28 stages. Both package an ad-hoc app, use an isolated home and a disposable loopback signing fixture, and prove an empty room costs nothing, three real-input sessions spend the budget, exhaustion survives restart, fixture activation opens the editor, offline validation retains access and an explicit refund blocks access without restoring the budget. They do not prove a genuine Waffo purchase. Evidence is local and ignored under `dist/mac-trial-pr/final-license-light/` and `dist/mac-trial-pr/final-license-dark/`.
- All captured light/dark screenshots were inspected. Trial counts, exhausted activation, licensed Home/editor, offline and refunded states fit the existing native layout; focus remains visible. On the first light run, Escape cancelled active composition rather than exiting, so the scripted trial uses the explicit EXIT button. This is not a Japanese IME acceptance result.
- `shellcheck scripts/qa-window.sh`, `bash -n scripts/qa-window.sh`, `go vet scripts/qa-license-fixture.go`, `plutil -lint Sources/FirstLine/Info.plist` and `git diff --check`: passed. Existing selector-construction warnings also occur in the untouched baseline; no new compiler error or test failure remains.
- User-visible changes are present: Home and Settings show trial sessions remaining, trial exhaustion opens the existing activation page with post-trial copy, paper width labels read Narrow/Wide paper, and the writing origin/wipe reset are corrected. This is not a no-UI-change merge candidate.
- Unverified release prerequisites: real Waffo test purchase, signed callback, buyer-visible credential activation and refund trace. Checkout URL, service URL, product ID and public key remain empty. No DMG build, upload, deployment or merge was performed. Full timing-sensitive real-window warn/recovery/wipe/kept-copy and Settings inspection were not run in this license-only pass; deterministic engine and AppKit view tests cover those paths but are not independent real-window acceptance.

Bounded follow-ups, not claimed fixed here:

- [ ] Reproduce and classify the prior RC report's 5/1077 per-key frame-match misses using an independent native capture run. This port does not remeasure or claim to eliminate those misses.
- [ ] Run real Japanese IME candidate selection, commit, cancellation, first-input trial charge, warning recovery and wipe/restart in a signed app. Direct `setMarkedText` tests and synthetic key delivery do not prove this.

## 2026-10-18 UTC: activation-first, paid-only reversal (historical)

This supersedes the native three-session trial in the earlier record below. Price remains USD $4.99 once; signature checks, two installations and seven-day offline grace are unchanged.

- `swift build && swift test`: passed, 183 tests in 15 suites. Trial-consumption tests were replaced by fresh-install, menu, direct-input/IME and persisted-legacy denial tests. Editor and session tests now use an explicit test-only licensed fixture; production still defaults to the real Waffo client.
- `WID_QA_LICENSE_ONLY=1 WID_QA_THEME=light scripts/qa-window.sh <output>` and the same command with `WID_QA_THEME=dark`: passed, 13 captured stages in light and 14 in dark, against isolated unactivated preferences and a disposable loopback signing service. The license-only flow checks the activation screen, full web-trial link, signed activation, real editor input, offline restart and direct return to activation after a refund. It also verifies the persisted file has no native trial counter. Evidence: ignored `tmp/waffo-mac/qa-paid-final-light/` and `qa-paid-final-dark/`.
- Initial window captures exposed an empty activation error triggered by focus changes. `activationFieldFocusChangesDoNotSubmitEmptyCredentials` reproduced it before the fix. The credential field now submits on the explicit action/Return, not on end-editing; the test passes.
- Light and dark activation, focus, activated and refunded states were inspected. Text fits the existing AppKit layout; there is no native trial or Home escape on the unactivated screen. The opaque credential tests verify raw UTF-8 transport/persistence and reject Unicode-equivalent aliases when deciding whether to reuse a cached activation.
- The full browser-trial target is checked through the actual link button's action with an injected external-URL opener. No browser checkout or real purchase was performed. The loopback order is synthetic and does not prove Waffo receipt/code interoperability.
- Full timing-sensitive window motion acceptance remains separate. The focused engine/room timing tests pass; no animation timing changes were made in this reversal.
- Real Waffo TEST checkout, signed callback, order/code-to-app activation, refund trace and verified production inputs remain uncompleted release prerequisites. No production DMG, public sale or deployment was performed.

## 2026-10-18: Waffo-backed Mac client, historical synthetic trial acceptance

- `swift build && swift test`: passed, 188 tests in 15 suites. The new real-client HTTP tests cover order-number requests, token signature/product/device/instance checks, signed renewal, legacy cache denial, first-input revocation, refunds and the exact seven-day expiry. Existing tests retain three-session consumption, IME, concurrency and activation rollback coverage.
- `WID_QA_LICENSE_ONLY=1 scripts/qa-window.sh <evidence-directory>`: passed with 14 captured stages. This packages a universal ad-hoc app, copies it into an isolated home, installs a fresh fixture public key only into that copy and uses a loopback service. Trial usage is deliberately seeded at three. The real window proved fourth-start denial, entered-order activation, real editor input without another trial charge, offline restart with access, then explicit refund rejection on restart. This is not a genuine Waffo order or payment test.
- Inspected the exhausted Upgrade, activated Upgrade, paid editor, offline Home and refunded Upgrade screenshots: text is not clipped, the order field and feedback remain aligned, native focus is visible. Local evidence lives under the ignored `tmp/waffo-mac/qa-license-head/` directory. The Settings layout was not independently inspected in a real window; automated view tests cover its changed copy and asynchronous feedback.
- Window QA exposed Home's stale `Checking license...` caption after asynchronous validation. Both active and revoked cases failed a focused view test before the Observation fix and pass afterward. A separate regression proved an opened empty room could accept input after revocation; first input now rechecks the existing trial/entitlement gate.
- Full motion-window QA did not pass: its Relaxed warn bounds used an obsolete percentage rather than the final three seconds, then screenshot/input latency let recovery arrive after the 12-second wipe. The bounds now match the fixed-three-second contract. Per the acceptance decision, license-window QA is separate from animation; deterministic `SilenceLimitTests` and `RoomTests` pass, but the full timing-sensitive window choreography remains pending independent acceptance.
- `go vet scripts/qa-license-fixture.go`, `shellcheck scripts/qa-window.sh scripts/release-dmg.sh`, `bash -n scripts/qa-window.sh scripts/release-dmg.sh`, `plutil -lint Sources/FirstLine/Info.plist` and `git diff --check` passed. Existing append-only selector-construction compiler warnings remain; they also occur in the untouched baseline.
- Not performed: genuine Waffo test purchase/callback/receipt verification, real-order activation/refund, production configuration, signing/notarization, public sale or deployment. These remain release blockers, not evidence supplied by mocks.


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

### 2026-09-24 - writeitdown batch 4, room parity

- `swift build` exit 0; `swift test` exit 0 (113 tests, 8 suites). All nine Batch 4 named filters and all twelve Batch 2 named filters separately exit 0. The inherited storage-symbol, brand/color and early-Finish negated `rg` gates exit 0; `bash -n scripts/qa-window.sh` exits 0. Command exit codes and logs: `/tmp/wid-b4-accept/results.txt` and adjacent logs (ephemeral build evidence).
- **Window QA pending independent Computer Use acceptance.** This background session cannot capture the macOS screen and did not grant screen permissions or run System Events/screencapture. `scripts/qa-window.sh 4` describes the light rest, typing, deny, warn, recovery, wipe, restart, real minute, copy, run again, and Escape flow. A separate graphical session must capture and inspect the stable states, observe deny feedback directly, check `pbpaste` against the exact draft, plus dark rest/warn/kept and reduced motion. The script does not capture the transient deny frame; physical IME candidate selection and exact 280 ms frames remain unverified.
- Live website was opened at `https://writeitdown.app/#trial` at 1440x900 with chrome-devtools-axi; its accessible room showed `1:00`, `0 WORDS`, and after idle `DRAFT WIPED - 0:52 UNUSED. TYPE TO RESTART.` The browser tool reported screenshots for rest/warn/wipe, but those paths were not available to this worker for inspection. The kept capture timed out. Fresh comparable web references and visual comparison remain pending independent acceptance; no visual pass is claimed here.

### 2026-09-24 - writeitdown batch 3, brand and tokens

- `swift build` exit 0; `swift test` exit 0 (105 Swift Testing tests, 7 suites). Five batch-3 named filters and all 12 batch-2 named filters individually exit 0. The inherited storage-reference `! rg`, early-Finish `! rg`, and batch-3 brand/color `! rg` each exit 0 with no matches. `bash -n scripts/qa-window.sh` exits 0.
- The package target and executable are `WriteItDown`; the source path remains `FirstLine`. `Info.plist` carries the bundle metadata for the future packaged app. Dynamic light/dark colors and the site-derived placeholder icon are covered by token tests and assets, not by an installed-app screenshot.
- **Window QA pending independent Computer Use acceptance**: this background session cannot capture the screen or use System Events. `scripts/qa-window.sh 3` now describes start and room in light appearance, Settings in light, then Settings, start, and room in dark; it was not run here. A fresh graphical session must inspect those states and record screenshots and pass/fail. Finder identity, packaged About identity, and actual icon rendering remain batch-7 checks.
- Physical IME and frame-level feedback are not verified here; neither interaction changes in batch 3.

### 2026-09-24 - writeitdown batch 2, engine parity

- `swift build` exit 0; `swift test` exit 0 (93 tests in 5 suites). All 12 named batch-2 filters individually exited 0. The inherited storage-reference and price-literal `! rg` gates exited 0. Window QA is **pending independent Computer Use acceptance**; this background session has no screen capture or System Events permission and did not run `scripts/qa-window.sh 2`.
- The scripted window flow now clicks the primary start button, waits three seconds to capture the unchanged clock, then captures typing, warning, in-room wipe, restart, kept, and the missing early Finish button. Independent acceptance must inspect each image and confirm the deletion time is elapsed time at the deadline, not remaining time or delayed sampling.
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

### Independent acceptance - Batch 4 (2026-09-25, ad083cce78590a15e740a218953af59fcd29c6f8)

- FAIL (evidence incomplete): `swift build` exit 0; `swift test` exit 0 (114 tests / 8 suites); all nine `RoomTests/<named test>` filters exit 0, one test each. Batch 1 and Batch 3 negative rg gates and the Batch 4 removed-symbol gate exit 0 with no hits. See `build.log`, `test.log`, `filter-*.log`, `b1-gate.log`, `b3-gate.log`, `b4-gate.log` beside this record's acceptance report.
- PASS: Authorized Codex Computer Use targeted only `app.writeitdown.mac` launched through LaunchServices with isolated `CFFIXED_USER_HOME`. Rest, typing, Backspace alarm outline, warn at about 5.5 s, recovery, and in-room wipe were captured (`shots/light-rest.png`, `shots/typing.png`, `shots/light-deny.png`, `shots/light-warn.png`, `shots/recovery.png`, `shots/light-wipe.png`). Recovery was captured in dark, not light. The first dark deny screenshot did not capture the outline.
- PASS: A full real-time 60-second kept run reached 32 words (`shots/kept.png`); COPY TEXT changed to COPIED (`shots/copied.png`), and `pbpaste` exactly matched the 227-byte typed `draft.txt`. RUN IT AGAIN and Escape returned to the room and Home (`shots/run-again.png`, `shots/exit.png`). A separate Light 3180-character / 480-word run reached kept after 62.89 real seconds; `shots/light-kept.png` and `shots/light-kept-scroll.png` show chunk01 at the top and chunk30 at the bottom after scrolling.
- PASS: Dark rest, warn, and kept screenshots are `shots/rest.png`, `shots/warn.png`, `shots/kept.png`. Fresh live light web 1440x900 references are `shots/web-rest.png`, `shots/web-warn.png`, `shots/web-wipe.png`, `shots/web-kept.png`; comparable copy, layout and phase states were visually inspected.
- NOT VERIFIED: `shots/settings-reduced.png` shows Always Reduce and `shots/reduced-deny.png` shows no visible paper displacement against `shots/light-reduced-rest.png`, but the alarm outline was not captured in that deny frame, so the complete reduced-motion deny contract is not proven. No exact 200 ms cut frame, 280 ms movement trace, audible VoiceOver announcement, physical IME candidate interaction, or Light recovery screenshot. Do not count isolated snapshots as proof of transient motion.
- HARNESS DEVIATION: `scripts/qa-window.sh 4` was not run: it relies on System Events and `screencapture`, both prohibited for this Mini acceptance. Computer Use drove real app windows and captured evidence instead. No App crash was observed; trial gate after three isolated session starts is expected at this stage.
- MERGE AUTHORIZATION: Captain approved merging Batch 4 on these screenshots despite the NOT VERIFIED evidence above; those lines remain unresolved, not reclassified as pass.

### Trial writing-line position (2026-09-25)

- PENDING real-window Computer Use on the Mini: compare empty and four-line rooms against the web at 1440x900 and 390x844, in centered narrow and left wide alignment and fullscreen Focus Mode. No Mac window screenshot was captured in this background session. The AppKit viewport test covers both alignments; `swift build` and `swift test` pass (145 tests).

### Batch 5 implementation window QA (2026-09-25)

- PENDING independent Computer Use acceptance. This background session has no display access and did not run `scripts/qa-window.sh 5`, System Events, or `screencapture`; no real-window screenshot is claimed. A fresh graphical session must capture all three warning/recovery/wipe tiers, light/dark start and kept screens, keyboard-only and clipboard flow, duration persistence, fullscreen focus hover and keyboard/VoiceOver status access, alignment and three font sizes, and system appearance. Physical IME, transient frames, and audible VoiceOver remain NOT VERIFIED until separately observed.
- `scripts/qa-window.sh` only offers Batch 5; historical batches 1-4 are unavailable after the Home and room redesign. The Batch 5 flow begins by clicking the 1-minute duration button, captures all three silence tiers in isolated trial starts, and explicitly leaves longer real-time kept/visual settings checks for independent Computer Use.
- Deterministic implementation gate (2026-09-25, from `apps/macos/FirstLine/`): `swift build` exit 0; `swift test` exit 0 (137 tests / 12 suites). Each of the 22 Batch 5 named filters, 12 Batch 2 named/deadline filters, and four Batch 1 filters exited 0 individually; four Batch 1/2/3/4 `! rg` removed-symbol checks exited 0 with no hits. Logs under `/tmp/wid-b5-accept/` on the build host. A timed guarded-input test appended 15,750 characters through `AppendOnlyTextView` (1.764 s for 150 chunks on this host); this is not a substitute for window typing QA.

### Independent acceptance - Batch 5 (2026-09-25, 8baa24f725bf55c043cc3570ee8fa7552a6284cd)

- FAIL overall: `swift build` and `swift test` exited 0 (143 tests, 12 suites); all 22 Batch 5 named filters exited 0 with one passing test each. The supplemental removed-symbol negative rg check exited 0 with no matches.
- PASS: App-targeted Codex Computer Use on a temporary SwiftPM debug bundle showed a clean start with five direct-start buttons and Standard silence by default (`shots/start.png`). The 5-minute choice survived an app relaunch (`shots/room-five-rest.png`, `shots/relaunch-five.png`). The clock held at 5:00 before typing.
- PASS: Actual Strict, Standard, and Relaxed warning/recovery/wipe runs captured at approximately 2/5, 5/8, and 9/12 seconds respectively (`shots/strict-warn.png`, `shots/strict-recovery.png`, `shots/strict-wipe.png`, `shots/standard-warn.png`, `shots/standard-recovery.png`, `shots/standard-wipe.png`, `shots/relaxed-warn.png`, `shots/relaxed-recovery.png`, `shots/relaxed-wipe.png`).
- PASS: Settings contained System appearance, Focus Mode, alignment, and three font sizes, but no duration or silence controls (`shots/settings-default.png`, `shots/settings-in-room.png`, `shots/settings-small.png`, `shots/settings-large.png`). Light and dark start states were inspected (`shots/start-light.png`, `shots/start-dark.png`). Fullscreen Focus Mode hid the clock and count until pointer hover (`shots/focus-hidden.png`, `shots/focus-clock-hover.png`, `shots/focus-count-hover.png`).
- PASS: A real uninterrupted 60.934-second run reached `0:00 - 31 WORDS KEPT.` without a promotional heading (`shots/kept-real.png`). Cmd+C changed to COPIED and the clipboard exactly matched the 155-character kept draft (`shots/kept-copied-real.png`). Cmd+W closed the app window.
- FAIL: After that kept session, Cmd+N showed 1:00 and 0 WORDS but left the previous full draft visibly in the new editor and its accessibility value (`shots/cmd-new-real.png`, independently recaptured as `shots/cmd-new-confirm.png`). Fix before merge and add a view-level regression for kept-to-new and active-to-new transitions.
- NOT VERIFIED: Physical IME, actual VoiceOver announcement and keyboard retrieval of hidden Focus Mode chrome, changing visual settings with a live nonempty timed draft, and large-draft typing performance. The legacy `scripts/qa-window.sh 5` was not run because it drives System Events and screencapture, prohibited for this Mini acceptance; the application-window-only Computer Use path was used instead.

### Independent acceptance - Batch 5 recheck (2026-09-25, 86329d3de4b9857e0b818662538ebd62dd650b11)

- PASS: `swift build` and `swift test` exited 0 (144 tests, 12 suites); each of the 22 Batch 5 named filters exited 0 with one passing test. The shared removed-symbol negative rg check exited 0 with no matches.
- PASS: App-targeted Sol Computer Use on a temporary SwiftPM debug bundle showed the five direct-start lengths and Standard 8s default (`shots/01-fresh-start-standard-8s.png`). A real one-minute run reached kept (`shots/02-kept-after-full-minute.png`); Cmd+C clipboard text exactly matched the editor accessibility value.
- PASS: Cmd+N from kept cleared both visible editor and accessibility value, displaying 1:00 / 0 WORDS (`shots/03-cmd-n-from-kept-blank.png`). Cmd+N during active writing did the same (`shots/04-cmd-n-while-active-blank.png`). The next new input contained only the new phrase (`shots/05-fresh-phrase-only.png`). This independently resolves the visible stale-draft failure seen on 8baa24f.
- PASS: On a fresh isolated home, Standard warning at 5252 ms (`shots/11-standard-warn-clean.png`) and wipe at 8401 ms (`shots/12-standard-wipe-clean.png`) were followed by typing in the same room: the editor AX value was exactly `restart phoenix new`, and the window showed 1:00 / 3 WORDS with no old text (`shots/13-standard-restart-clean.png`). Cmd+W closed the app. Two earlier attempts exhausted their separate trial homes through automation timing misses; these were test setup errors, not product failures.
- NOT RE-RUN: The prior Batch 5 independent report covers the other silence limits, settings, focus and light/dark screenshots. Physical IME, actual VoiceOver access and large-draft typing performance remain unverified. The legacy `scripts/qa-window.sh 5` was not executed because its System Events and screencapture path is disallowed for this Mini Computer Use acceptance.

### Batch 6 window QA (2026-09-25)

- PENDING independent Computer Use acceptance. This background build session has no screen access; `scripts/qa-window.sh 6` now encodes three first-input trials and the fourth-start Upgrade route, but was not run here. No screen permission was granted and no `screencapture` or System Events operation was attempted.
- NOT VERIFIED in a window: configured checkout opening in the default browser; Settings displaying `License active.` after activation. `WIDCheckoutURL` is empty pending the owner-created Dodo product, and no Dodo test-mode key was supplied. These steps must be recorded separately by the independent acceptance session; no live API call was made.
- Deterministic batch 6 build-session gate (2026-09-25, before implementation commit): from `apps/macos/FirstLine/`, `swift build` exit 0; `swift test` exit 0 (152 tests / 13 suites). Each `swift test --filter <Suite>/<function>` exited 0 for Batch 6: `LicenseFlowTests/{trialIsConsumedOnFirstKeystrokeNotOnEntry,untouchedRoomDoesNotConsumeTrial,exhaustedTrialRoutesToUpgrade,checkoutURLComesFromInfoPlist,displayPriceComesFromInfoPlist}` and `DodoLicenseClientTests/{activateBuildsPublicRequestWithoutAuthHeader,errorCodesMapToLicenseActivationError}`. Each Batch 2 named filter exited 0: `SessionEngineTests/{clockStartsOnFirstInputNotOnStart,markedTextStartsTheClock,whitespaceOnlyDraftAtDeadlineWipes,wipeReportsUnusedSeconds,keystrokeAfterWipeStartsFreshSessionWithSameDuration,wordCountMatchesWebCases,fiveAndEightSecondRulesHoldForSixtyMinuteSession,exactDeadlineTieResolvesToFailure,bothDeadlinesPassedWithSilenceEarlierResolvesToFailure,lateActivityAfterWipeDeadlineIsRejectedAndPhaseIsFailure}`, `SettingsStoreTests/invalidStoredDurationFallsBackToSixtySeconds`, `EditorFocusTests/movementCommandsDenyAndKeepCaretAtEnd`. The Batch 1 removed-symbol, Batch 3 old-brand, and Batch 6 Swift-price `! rg` gates all exited 0 with zero matches. Dodo client tests injected a stub URLProtocol; no real API request was made.

### Batch 7 pre-release package QA (2026-09-28)

- PASS deterministic: `swift build` exit 0; `swift test` exit 0 (177 tests / 13 suites); `scripts/package-app.sh --adhoc` exit 0 and `codesign --verify --deep --strict` passed. `cd writeitdown && npm test` exit 0 (52 passed, 4 skipped). Logs under `/var/tmp/2026-09-28-zd-wid-mac-b7/`.
- PENDING Developer ID release: `scripts/release-dmg.sh` exits 1 with a clear missing-identity error. The Apple certificates API returned a 403 Account Holder-only error. No signed, notarized DMG, staple validation, Gatekeeper check or SHA-256 release artifact is claimed yet. Dodo live verification failed: submitted `https://firstline.page` times out from this Mini (`curl -sI` HTTP 000, 15 seconds); the submitted social URL `https://x.com/iansublates` returned HTTP 200. Live checkout/product ID remain empty.
- PASS Dodo test mode: created the one-time USD $4.99 product `pdt_0NobQfCR3EMaJJnJ4v36M` with a non-expiring license entitlement limited to two activations, and a manually issued sandbox key held only at `~/.config/writeitdown/dodo.env` (0600). `WID_DODO_E2E=1 swift test --filter LiveDodoAcceptanceTests` exit 0: the real AppState + DodoLicenseClient activated the key and a mismatched configured product ID was refused. Log: `/var/tmp/2026-09-28-zd-wid-mac-b7/live-dodo-test.log` (no key printed). Test mode is not proof of a live checkout or customer delivery email.
- PENDING packaged-app window QA: launched the ad-hoc `.app` with a fresh `CFFIXED_USER_HOME`, but two app-targeted Codex Computer Use attempts were refused with `Computer Use was not approved to use Write It Down`. No screenshot or observation of Finder name, About identifier, icon, fonts, room, Upgrade, or Settings is claimed. Retry once approval is granted on the final Developer ID signed app; do not treat a successful `open` command as visual acceptance.

### Polar provider change and signing retry (2026-09-29)

- PASS deterministic: `swift build` exit 0; `swift test` exit 0 (177 tests / 14 suites), including stubbed public Polar activation, benefit scoping, third-device/refunded denial, and offline error behavior. `cd writeitdown && npm test` exit 0 (52 passed, 4 skipped). Logs under `/var/tmp/2026-09-29-zd-wid-mac-b7/`.
- PENDING Polar sandbox: the separately isolated `https://sandbox.polar.sh/` opens a login page; owner sign-in and a sandbox organization, benefit, and license key are still needed. `LivePolarAcceptanceTests` is disabled by default and has not made a network request. No real Polar key activation is claimed.
- PENDING signing: the Account Holder-installed Developer ID Application identity is visible in `security find-identity`, but `scripts/release-dmg.sh --staging` timed out after 180 seconds at `codesign ... --options runtime --timestamp` immediately after `replacing existing signature`. No DMG, notarization, staple, Gatekeeper verdict or release checksum exists. An interactive keychain authorization prompt or private-key access policy must be resolved in the GUI; do not claim signing acceptance from the ad-hoc package.

### Signing record correction (2026-10-05)

- CORRECTION (resolves the stale PENDING line above): later on 2026-09-29 the same `scripts/release-dmg.sh --staging` was re-run to completion on the Mini; log `/var/tmp/2026-09-29-zd-wid-mac-b7/release-dmg.log`. The hardened-runtime Developer ID signature applied and verified (`valid on disk`, `satisfies its Designated Requirement`), `Write-It-Down-1.0-staging.dmg` was created, notary submission `e8ea2814-f490-4bc3-91a8-d741a9e8c40b` was reported `Accepted`, `stapler staple` and `stapler validate` both succeeded, `spctl -a -t open` returned `accepted (source=Notarized Developer ID)`, and the `.sha256` sidecar was written. That DMG and the disposable worktree that produced it are no longer on disk, so nothing from that run survives as an artifact; it proves the staging pipeline works end to end, not that a distributable DMG exists.
- PASS real-window QA via the rewritten `scripts/qa-window.sh` (2026-10-05, cua-driver daemon route, no Computer Use): the ad-hoc universal app under a fresh `CFFIXED_USER_HOME` passed home budget text, five duration buttons, Standard 8s room entry, typed `hello world` (2 WORDS), blocked Backspace, warn wash with the numeral in AX, single-key recovery, literal `DRAFT WIPED - UNUSED. TYPE TO RESTART.` report, fresh restart input, Escape to Home, and `trialSessionsUsed` billing truth (2 first-inputs). Screenshots and AX snapshots: `/var/tmp/2026-10-05-zd-wid-mac-buildtools/qa-window-run2/`. The 280 ms deny hairline and 120 ms recovery snap single frames remain NOT VERIFIED at CLI latency, consistent with the tooling limits recorded above.

### Split-W logo assets (2026-10-24, 9854d18 + de37775)

- PASS: static asset inspection of the shipped `AppIcon.appiconset`. The 16/16@2x and 32/32@2x entries are the optical split-W drawings on the bone plate; 128 and above use the master. The ink-plate/bone-W alternate remains the dark-appearance source and is not compiled into the `.icns`.
- PASS: `packaging/VolumeIcon.icns` contains 16, 32, 64, 128, 256, 512, and 1024 px entries; the 128 and 1024 renders show the bone sheet and the ink split W on the dark disc.
- PASS: the web favicon set uses the split W. `favicon-16.png` and `favicon-32.png` reuse the app optical drawing; `favicon.svg`, `favicon-dark.svg`, and `apple-touch-icon.png` use the master split W. The light and dark favicons were inspected at 16 and 32, the SVG masters, and the apple-touch icon at 180.
- NOT VERIFIED: real Dock and Finder captures on light and dark. Static asset inspection is the evidence for the icon assets in this change. The start-screen brand change is recorded separately below; the Batch 3 "no visible old brand" record refers to the old WID/red mark, not the mono logotype.

### Mac start-screen lockup and mac.html header (2026-10-24, worktree after de37775)

- PASS deterministic: `swift build` exit 0; `swift test` exit 0 (198 tests across 16 suites). The new `BrandTests` assertion finds exactly one start-screen image with the `Write It Down` accessibility label and no mono `WRITE_IT_DOWN` label; the existing start-screen focus and trial tests pass.
- PASS real-window start screen: `docs/logo-evidence/start-window-light.png` and `start-window-dark.png` captured from the debug executable with a fresh `CFFIXED_USER_HOME`; the split-W lockup is visible at 21 px type above the duration picker, tinted with the app ink token in both appearances. The capture used `screencapture -x -l <windowid>` on the debug window, not the packaged app.
- PASS web: the `mac.html` header uses the same `.brand` lockup at 21 px desktop / 19 px mobile; `qa/mac.spec.mjs` covers its keyboard focus ring and theme toggle across all eight browser projects (16 checks passed).
- ACCEPTED: the real-window start-screen captures and the static icon inspection are the evidence for this change. Dock and Finder captures remain release-gate evidence and are not claimed here.
- NOT VERIFIED: Dock and Finder captures on light and dark.
- NOT VERIFIED: `scripts/package-app.sh --adhoc` exits 1 in this worktree because `/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild` is unavailable; no universal release app was assembled here. The SwiftPM debug resource bundle contains `write-it-down-lockup.svg`.
- The cua-driver daemon is not running (`cua-driver permissions status` reports `daemon_running: false`), so `scripts/qa-window.sh` was not used; the start-screen captures above came from a direct debug-window launch and `screencapture`.
- The Batch 3 record above describes the historical mono start screen; this record supersedes it for the current tree.
