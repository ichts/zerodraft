# First Line macOS module instructions

Parent instructions: `../AGENTS.md`

成员清单
Package.swift: Swift Package 入口，支持 macOS 14+，先保证 `swift build` 与 `swift test` 通过。
docs/RELEASE_CHECKLIST.md: 直接分发签名/公证/DMG 发布清单。
docs/LAUNCH_PLAN.md: 历史发布规划参考；其中 Mole-style 网站方向已被根目录 `AGENTS.md` 的 Kami 规则取代。
docs/LICENSE_PAYMENT_SPEC.md: Dodo-first 支付、license entitlement、Mac 激活与支持页面规格。
docs/LAUNCH_TODO.md: Dodo 审核等待期到正式发布的可执行 TODO，给接手 agent 按阶段推进。
docs/MANUAL_QA.md: MVP 手动验证清单与结果记录模板。
build/darwin/Info.plist: 预置的 macOS 应用元数据骨架。
build/darwin/AppIcon/README.md: 图标导出占位说明。
架构：纯 AppKit（无 SwiftUI；全仓 `grep import SwiftUI` = 0）。@main 是 NSApplication 入口，各 surface 是 NSViewController，经 RootContainerViewController 原地切换；编辑器与状态机复用。
Sources/FirstLine/App/FirstLineMain.swift: 纯 AppKit @main 入口（NSApplication + FirstLineAppDelegate）；持有 AppState、构建主菜单、创建并显示 RootWindowController、激活应用；含菜单动作（openWriting/goHome/openSettings/openLibrary）与 validateMenuItem 启用规则。
Sources/FirstLine/App/MainMenuBuilder.swift: NSApp.mainMenu 构建（App 菜单：Settings Cmd+, / Quit；Navigate 菜单：Writing Cmd+1 / Home Cmd+0 / Library Cmd+2）。
Sources/FirstLine/App/RootWindowController.swift: 主窗口 NSWindowController；窗口只 size 一次，contentViewController 是常驻 RootContainerViewController；观察 AppState.selectedSurface（切 surface）、sessionEngine.phase（failure/success 写回 selectedSurface）、settings.theme（窗口 appearance）。
Sources/FirstLine/App/RootContainerViewController.swift: 常驻窗口内容控制器；各 surface 以子 VC 原地切换（addChild/removeFromParent + 视图 autoresize 填充），把窗口尺寸与 surface 解耦，避免每次换 contentViewController 触发的 0x0 fitting-size / 递归 layout。
Sources/FirstLine/App/AppState.swift: 顶层导航状态、3-session trial gate 与 license 激活/校验入口（@Observable，来自 Observation，非 SwiftUI）。
Sources/FirstLine/App/HomeViewController.swift: Home 启动界面（Flood 居中标题/tagline/规则/trial 状态 + 固定 60 秒 "Give it sixty seconds." 按钮）；最近一次 wipe 后携带持久红线 “Draft deleted. it joined the pile.” 与一条丢失草稿的 margin fossil，直至下一场 session。
Sources/FirstLine/Info.plist / Assets.xcassets/: 应用元数据与图标资源。
Sources/FirstLine/Editor/AppendOnlyTextView.swift: 自定义 NSTextView，append-only、IME 安全、zen 排印、caret 锚点；由 SessionViewController 直接以 NSScrollView 托管。
Sources/FirstLine/Editor/AppendOnlyInputPolicy.swift: append-only 输入守卫的单一可测来源（被屏蔽命令选择器 + UTF-16 末尾选区重定向），供 SessionViewController 的 NSTextViewDelegate 与 EditorFocusTests 共用。
Sources/FirstLine/Infrastructure/AppPaths.swift: Application Support 路径规范。
Sources/FirstLine/Infrastructure/PersistenceService.swift: 成功 session 的 markdown 存储。
Sources/FirstLine/Infrastructure/SettingsStore.swift: 设置读写、默认值与 license 字段迁移（v0.1 hasUnlockedFullAccess → v0.2 licenseStatus）。
Sources/FirstLine/Infrastructure/InstallIDStore.swift: 生成并持久化 stable install UUID，作为 Dodo activate 的 instance name。
Sources/FirstLine/Licensing/LicenseModels.swift: LicenseStatus、LicenseActivation、LicenseActivationError、LicenseValidationError，对照 Dodo 公开 license API 契约。
Sources/FirstLine/Licensing/LicenseClient.swift: LicenseClient protocol，覆盖 activate / validate / deactivate 三个公开 endpoint。
Sources/FirstLine/Licensing/MockLicenseClient.swift: LicenseClient actor 替身，不触达真实 Dodo 网络。
Sources/FirstLine/Session/SessionEngine.swift: danger / failure / success 状态机与单调时间规则；集中式截止裁决在 tick / registerCommittedText / registerMarkedTextActivity / finish 入口先于活动应用，空文本永不 success（纯 Foundation）。
Sources/FirstLine/Session/SessionViewController.swift: Session 主界面（AppKit）；托管 AppendOnlyTextView、稳健 first-responder 获取（viewDidAppear 重试 + didBecomeKey 兜底）、100ms tick、Flood 环境（bone ground + 720 白纸列 + FossilLayerView + danger veil/倒计时 + narrator + deny 抖动/红 hairline）；NSTextViewDelegate 守卫用 AppendOnlyInputPolicy。
Sources/FirstLine/Session/FailureViewController.swift: Failure 界面（Draft deleted 文案 + Try Again / Back to Home + joined fossil）。
Sources/FirstLine/Session/SuccessViewController.swift: Success 界面，提供词数 + 草稿预览 + Copy full text / Copy for AI / Download .md / Discard；Copy for AI 使用 web-canonical cleanup prompt，Copy 主按钮显示 “Copied.” 回显。
Sources/FirstLine/Session/SuccessText.swift: 纯逻辑 success 文案与 copy-for-AI payload（web-canonical cleanup prompt），供 SuccessViewController 与 SuccessSurfaceTests 共用。
Sources/FirstLine/Upgrade/UpgradeViewController.swift: Mac trial 用尽后的 upgrade 界面，含 license key 输入、激活全部状态、禁用的 Buy 占位与 Back to Home。
Sources/FirstLine/Library/LibraryViewController.swift: Library 分栏（列表按时间倒序 + 详情正文/元数据）与 Copy / Open in Default Editor / Reveal in Finder / Delete。
Sources/FirstLine/Settings/SettingsViewController.swift: Settings 界面，含 Appearance（theme / reduced motion）、Session（固定 60 秒）、Trial & License、Storage（Reveal Library Folder）、About 与 Done 返回 Home。
Sources/FirstLine/DesignSystem/Colors.swift: Flood 颜色 token（NSColor dynamic provider，明暗自适应）。
Sources/FirstLine/DesignSystem/Typography.swift: 字体与字号 token（NSFont，Newsreader + IBM Plex Mono）。
Sources/FirstLine/DesignSystem/FirstLineButtons.swift: appearance-aware AppKit 主/次/链接按钮工厂；updateLayer 只改 layer 视觉属性，绝不在其中设 content 属性（避免 _NSViewLayoutFeedbackLoop 无限回环卡死）。
Sources/FirstLine/DesignSystem/FloodCanvasView.swift: appearance-aware bone/paper 背景 NSView；updateLayer 里重解析 dynamic NSColor.cgColor（避免静态 cgColor 在暗色下解析错）。
Sources/FirstLine/DesignSystem/FossilLayerView.swift: Flood 静态 fossil 纹理层（flipped NSView draw）；bone canvas 左右 margin（paper 列以外）seeded 放置犹豫草稿 fossil，danger 时仅变红，几何变化重算。
Sources/FirstLine/DesignSystem/WritingFontCandidate.swift: 固定写作字体定义与本地字体注册，英文 Newsreader + IBM Plex Mono，中文 Zhuque Fangsong，全部来自 package resources。
Sources/FirstLine/DesignSystem/Spacing.swift: 间距 token。
Tests/FirstLineTests/SessionEngineTests.swift: Session engine 状态流转测试。
Tests/FirstLineTests/EditorFocusTests.swift: 编辑器焦点与会话启动回归测试。
Tests/FirstLineTests/PersistenceOnlyTests.swift: 成功存储测试。
Tests/FirstLineTests/LibraryPersistenceTests.swift: Library 读取、解析、删除测试。
Tests/FirstLineTests/SettingsStoreTests.swift: 设置持久化、默认值与 legacy 字段迁移测试。
Tests/FirstLineTests/SmokeFlowTests.swift: 端到端 smoke tests，覆盖 happy path、failure path、首次/回访启动、键盘导航切换、success 阶段导航拦截、trial 计数与解锁。
Tests/FirstLineTests/SuccessSurfaceTests.swift: Success 面板行为测试，覆盖 web-canonical cleanup prompt 常量、copy-for-AI payload 拼接格式与 trim 语义。
Tests/FirstLineTests/LicenseFlowTests.swift: license 激活成功/失败路径、validate 7-day 离线宽限、active/revoked 与 trial gate 交互。

验证命令
从本目录运行 `swift build` 和 `swift test`。界面、编辑器、键盘、IME 或发布流程变更还必须执行相关的 `docs/MANUAL_QA.md` 项目，并记录无法执行的检查。

对外暴露
可执行目标 `FirstLine`

法则: 保持 macOS native only；编辑器必须 append-only 且不破坏 IME；所有启动都进入同一个极简 Home，不提供单独 intro / warm-up onboarding；无侧边栏，单一写作界面，导航通过 AppState.selectedSurface 路由；success 阶段仅允许复制或丢弃，不暴露 Library / 文件操作；失败即失去当前段落，不提供恢复；不扩大到 AI / 同步 / WebView；license 激活只走 Dodo 公开 endpoint，Mac app 永不嵌入 developer API key；checkout URL 在外部浏览器打开，不内嵌 WebView；danger 契约：沉默 5 秒触发红色 veil 与倒计时，8 秒清空草稿、留下持久文案 "Draft deleted. it joined the pile." 与一条丢失草稿的 fossil，红色 #c8392f 仅保留给 danger

[PROTOCOL]: 目录结构或核心约束变化时更新本文件，并检查 `../AGENTS.md` 与根目录 `AGENTS.md` 是否仍准确。
