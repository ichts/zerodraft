# writeitdown macOS module instructions

Parent instructions: `../AGENTS.md`

成员清单
Package.swift: `WriteItDown` Swift Package 可执行目标，支持 macOS 14+；源码路径仍为 `FirstLine`，先保证 `swift build` 与 `swift test` 通过。
docs/WRITEITDOWN_PLAN.md: 本应用改造为 writeitdown macOS app 的现行计划（产品规则映射、时长选择器、删除清单、分批验收、已定的签名 DMG 付费分发）；与下列历史 Zero Draft 文档冲突时以它为准。
docs/RELEASE_CHECKLIST.md: 直接分发签名/公证/DMG 发布清单。
docs/LAUNCH_PLAN.md: 历史 Zero Draft 发布规划；writeitdown 当前分发与视觉方向见 `docs/WRITEITDOWN_PLAN.md` 和 `writeitdown/AGENTS.md`。
docs/LICENSE_PAYMENT_SPEC.md: Dodo-first 支付、license entitlement、Mac 激活与支持页面规格。
docs/LAUNCH_TODO.md: Dodo 审核等待期到正式发布的可执行 TODO，给接手 agent 按阶段推进。
docs/MANUAL_QA.md: 历史检查清单与按批次记录的窗口 QA 结果；当前验收项目以 `docs/WRITEITDOWN_PLAN.md` 为准。
架构：纯 AppKit（无 SwiftUI；全仓 `grep import SwiftUI` = 0）。@main 是 NSApplication 入口，各 surface 是 NSViewController，经 RootContainerViewController 原地切换；编辑器与状态机复用。
Sources/FirstLine/App/FirstLineMain.swift: 纯 AppKit @main 入口；持有 AppState、构建菜单和窗口、激活应用；桥接新篇、整篇复制、关闭窗口等菜单动作与验证。
Sources/FirstLine/App/MainMenuBuilder.swift: NSApp.mainMenu 构建（Settings Cmd+,、新篇 Cmd+N、成稿复制 Cmd+C、关窗 Cmd+W）。
Sources/FirstLine/App/RootWindowController.swift: 主窗口 NSWindowController；窗口只 size 一次，contentViewController 是常驻 RootContainerViewController；观察 AppState.selectedSurface（切 surface）、settings.theme（窗口 appearance）；启用鼠标移动事件供专注模式悬停显示计时/字数，原生退出全屏时同步关闭写作中的专注偏好，导航导致的退出则保留偏好；所有会话相位留在同一个房间。
Sources/FirstLine/App/RootContainerViewController.swift: 常驻窗口内容控制器；各 surface 以子 VC 原地切换（addChild/removeFromParent + 视图 autoresize 填充），把窗口尺寸与 surface 解耦，避免每次换 contentViewController 触发的 0x0 fitting-size / 递归 layout。
Sources/FirstLine/App/AppState.swift: 顶层导航状态、会话启动与首输入 trial 计数、Info.plist 价格/HTTPS checkout 配置、license 激活/启动校验入口及产品 ID 门槛（@Observable，来自 Observation，非 SwiftUI）；所有会话正文只在内存。
Sources/FirstLine/App/HomeViewController.swift: 无营销文案的开写前选择面；五个时长按钮直接进入房间、三个静默时限单选；默认时长按钮获焦点。
Sources/FirstLine/Info.plist / Assets.xcassets/: 应用元数据与图标资源。
Sources/FirstLine/Editor/AppendOnlyTextView.swift: 自定义 NSTextView，append-only、IME 安全、zen 排印、caret 锚点；由 SessionViewController 直接以 NSScrollView 托管。
Sources/FirstLine/Editor/AppendOnlyInputPolicy.swift: append-only 输入守卫的单一可测来源（被屏蔽命令选择器 + UTF-16 末尾选区重定向），供 SessionViewController 的 NSTextViewDelegate 与 EditorFocusTests 共用。
Sources/FirstLine/Infrastructure/AppPaths.swift: Application Support/WriteItDown 配置路径规范；不导入旧 First Line 目录，草稿不落盘。
Sources/FirstLine/Infrastructure/SettingsStore.swift: 设置读写、五档时长/三档静默时限及专注/对齐/字号持久化、旧许可键只读迁移（v0.1 hasUnlockedFullAccess → v0.2 licenseStatus）、已接受激活的产品 ID 缓存，不再写旧许可键与沉浸模式。
Sources/FirstLine/Infrastructure/InstallIDStore.swift: 生成并持久化 stable install UUID，作为 Dodo activate 的 instance name。
Sources/FirstLine/Licensing/LicenseModels.swift: LicenseStatus、LicenseActivation、LicenseActivationError、LicenseValidationError，对照 Dodo 公开 license API 契约。
Sources/FirstLine/Licensing/LicenseClient.swift: LicenseClient protocol，覆盖 activate / validate / deactivate 三个公开 endpoint。
Sources/FirstLine/Licensing/MockLicenseClient.swift: LicenseClient actor 测试替身，不触达真实 Dodo 网络。
Sources/FirstLine/Licensing/DodoLicenseClient.swift: URLSession 实现 Dodo 公开许可端点；Debug 默认 test mode，Release 默认 live mode，无 developer API key；validate 仅返回有效性，不返回产品身份。测试以 URLProtocol 隔离请求。
Sources/FirstLine/Session/SessionEngine.swift: 可选时长和静默阈值的 danger / failure / success 状态机与单调时间规则；首输入启动时钟、绝对截止裁决、按 deadline 计算 unusedSeconds、Unicode 词数（纯 Foundation）；失败后重启须由 AppState 授权。
Sources/FirstLine/Session/RoomPresentation.swift: 与网站一致的时钟、擦除报告、保留收据、wash 强度、复制及拒绝反馈状态规则。
Sources/FirstLine/Session/SessionViewController.swift: 单一 Session 房间（AppKit）；托管 AppendOnlyTextView、首响应者、100ms tick、新 session ID 时清空旧视图、原房间 wipe/restart 与 kept/copy；NSTextViewDelegate 守卫用 AppendOnlyInputPolicy。
Sources/FirstLine/Upgrade/UpgradeViewController.swift: Mac trial 用尽后的许可入口，价格来自 WIDDisplayPrice；仅配置有效 WIDCheckoutURL 时允许外部浏览器结账；观察异步许可变化并原位更新反馈。
Sources/FirstLine/Settings/SettingsViewController.swift: Settings 界面，含 appearance、motion、focus、alignment、font size、Trial & License；观察异步许可变化并原位更新状态、不清除输入；时长和静默档只在 Home 选择，Done 返回进入前的 surface。
Sources/FirstLine/DesignSystem/Colors.swift: `writeitdown/site.css` 明暗色 token（NSColor dynamic provider），含 wash/deep 与 alarm。
Sources/FirstLine/DesignSystem/Typography.swift: 网站字号对应的字体 token（NSFont，Newsreader 主标题/正文 + IBM Plex Mono 小号标识/机器文案）。
Sources/FirstLine/DesignSystem/FirstLineButtons.swift: appearance-aware AppKit 主/次/链接按钮工厂；updateLayer 只改 layer 视觉属性，绝不在其中设 content 属性（避免 _NSViewLayoutFeedbackLoop 无限回环卡死）。
Sources/FirstLine/DesignSystem/FloodCanvasView.swift: appearance-aware wall/paper 背景 NSView；updateLayer 里重解析 dynamic NSColor.cgColor（避免静态 cgColor 在暗色下解析错）。
Sources/FirstLine/DesignSystem/WritingFontCandidate.swift: 固定写作字体定义与本地字体注册，英文 Newsreader + IBM Plex Mono，中文 Zhuque Fangsong，全部来自 package resources。
Sources/FirstLine/DesignSystem/Spacing.swift: 间距 token。
Tests/FirstLineTests/SessionEngineTests.swift: Session engine 状态流转与时长截止测试。
Tests/FirstLineTests/SilenceLimitTests.swift: 三档静默警告/删除、恢复及平局裁决。
Tests/FirstLineTests/BatchFiveTests.swift: 时长选择、设置持久化和键盘动作验收。
Tests/FirstLineTests/RoomTests.swift: 房间文案、时钟、wash、deny、复制与退出测试。
Tests/FirstLineTests/EditorFocusTests.swift: 编辑器焦点与会话启动回归测试。
Tests/FirstLineTests/SettingsStoreTests.swift: 设置持久化、默认值与 legacy 字段迁移测试。
Tests/FirstLineTests/SmokeFlowTests.swift: 端到端 smoke tests，覆盖成功与失败不落盘、菜单无 Library、导航、trial 计数与解锁。
Tests/FirstLineTests/LicenseFlowTests.swift: license 激活成功/失败路径、validate 7-day 离线宽限、active/revoked 与首输入 trial gate 交互。
Tests/FirstLineTests/DodoLicenseClientTests.swift: stub URLProtocol 验证公开 API 请求和错误映射，不触达外网。

验证命令
从本目录运行 `swift build` 和 `swift test`。界面、编辑器、键盘、IME 或发布流程变更还必须执行相关的 `docs/MANUAL_QA.md` 项目，并记录无法执行的检查。

对外暴露
可执行目标 `WriteItDown`

法则: 草稿只在内存中，许可与设置仍可持久化；许可 trial 在首输入计数，未输入的房间免费；开写前时长 1/5/10/20/30 分钟、静默清空 5/8/12 秒，写作中锁定两者；首输入启动倒计时，只有截止时间能成功，失败留在原房间且下次输入重启；保持 macOS native only；编辑器必须 append-only 且不破坏 IME；所有启动都进入同一个极简 Home，不提供单独 intro / warm-up onboarding；无侧边栏，单一写作房间承载 rest/typing/warn/wipe/kept，导航通过 AppState.selectedSurface 路由；kept 阶段仅允许复制、重来或退出，不暴露 Library / 文件操作；失败即失去当前段落，不提供恢复或 fossil；不扩大到 AI / 同步 / WebView；license 激活只走 Dodo 公开 endpoint，Mac app 永不嵌入 developer API key；checkout URL 在外部浏览器打开，不内嵌 WebView；danger 契约：清空前最后三秒出现 wash 与倒计时，选定阈值清空草稿并显示房间内报告，警告色使用 `writeitdown/site.css` 的 alarm token

[PROTOCOL]: 目录结构或核心约束变化时更新本文件，并检查 `../AGENTS.md` 与根目录 `AGENTS.md` 是否仍准确。
