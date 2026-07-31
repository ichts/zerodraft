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
Sources/FirstLine/FirstLineApp.swift: SwiftUI App 入口。
Sources/FirstLine/Info.plist: Swift Package 目标使用的应用元数据。
Sources/FirstLine/Assets.xcassets/: 应用图标资源。
Sources/FirstLine/App/AppState.swift: 顶层导航状态、3-session trial gate 与 license 激活/校验入口。
Sources/FirstLine/App/RootView.swift: 主导航、session phase 与 upgrade surface 容器。
Sources/FirstLine/App/HomeView.swift: Home 极简启动入口，固定 60 秒、无时长选择，启动按钮文案 "Give it sixty seconds."，并显示 trial 状态。
Sources/FirstLine/Editor/AppendOnlyTextView.swift: 自定义 NSTextView，负责 append-only 和 IME 活动桥接。
Sources/FirstLine/Editor/EditorViewRepresentable.swift: SwiftUI ↔ AppKit 编辑器桥。
Sources/FirstLine/Infrastructure/AppPaths.swift: Application Support 路径规范。
Sources/FirstLine/Infrastructure/PersistenceService.swift: 成功 session 的 markdown 存储。
Sources/FirstLine/Infrastructure/SettingsStore.swift: 设置读写、默认值与 license 字段迁移（v0.1 hasUnlockedFullAccess → v0.2 licenseStatus）。
Sources/FirstLine/Infrastructure/InstallIDStore.swift: 生成并持久化 stable install UUID，作为 Dodo activate 的 instance name。
Sources/FirstLine/Licensing/LicenseModels.swift: LicenseStatus、LicenseActivation、LicenseActivationError、LicenseValidationError，对照 Dodo 公开 license API 契约。
Sources/FirstLine/Licensing/LicenseClient.swift: LicenseClient protocol，覆盖 activate / validate / deactivate 三个公开 endpoint。
Sources/FirstLine/Licensing/MockLicenseClient.swift: LicenseClient actor 替身，Phase 3 期间不触达真实 Dodo 网络。
Sources/FirstLine/Session/SessionEngine.swift: danger / failure / success 状态机与单调时间规则。
Sources/FirstLine/Session/SessionView.swift: Session 主界面，驱动编辑器和会话循环。
Sources/FirstLine/Session/FailureView.swift: Failure 界面。
Sources/FirstLine/Session/SuccessView.swift: Success 界面，提供 Copy full text / Copy for AI / Download .md / Discard。
Sources/FirstLine/Upgrade/UpgradeView.swift: Mac trial 用尽后的 upgrade 引导界面，含 license key 输入、激活全部状态与禁用的 Buy 占位。
Sources/FirstLine/Library/LibraryView.swift: Library 列表与详情界面。
Sources/FirstLine/Settings/SettingsView.swift: Settings 界面，含 theme/duration/immersive/reduced motion、Trial & License section 与 library reveal。
Sources/FirstLine/DesignSystem/Colors.swift: 颜色 token。
Sources/FirstLine/DesignSystem/Typography.swift: 字体与字号 token。
Sources/FirstLine/DesignSystem/WritingFontCandidate.swift: 固定写作字体定义与本地字体注册，英文 Newsreader + IBM Plex Mono，中文 Zhuque Fangsong，全部来自 package resources。
Sources/FirstLine/DesignSystem/Spacing.swift: 间距 token。
Sources/FirstLine/DesignSystem/ButtonStyles.swift: 按钮层级样式 token。
Tests/FirstLineTests/SessionEngineTests.swift: Session engine 状态流转测试。
Tests/FirstLineTests/EditorFocusTests.swift: 编辑器焦点与会话启动回归测试。
Tests/FirstLineTests/PersistenceOnlyTests.swift: 成功存储测试。
Tests/FirstLineTests/LibraryPersistenceTests.swift: Library 读取、解析、删除测试。
Tests/FirstLineTests/SettingsStoreTests.swift: 设置持久化、默认值与 legacy 字段迁移测试。
Tests/FirstLineTests/SmokeFlowTests.swift: 端到端 smoke tests，覆盖 happy path、failure path、首次/回访启动、键盘导航切换、success 阶段导航拦截、trial 计数与解锁。
Tests/FirstLineTests/LicenseFlowTests.swift: license 激活成功/失败路径、validate 7-day 离线宽限、active/revoked 与 trial gate 交互。

验证命令
从本目录运行 `swift build` 和 `swift test`。界面、编辑器、键盘、IME 或发布流程变更还必须执行相关的 `docs/MANUAL_QA.md` 项目，并记录无法执行的检查。

对外暴露
可执行目标 `FirstLine`

法则: 保持 macOS native only；编辑器必须 append-only 且不破坏 IME；所有启动都进入同一个极简 Home，不提供单独 intro / warm-up onboarding；无侧边栏，单一写作界面，导航通过 AppState.selectedSurface 路由；success 阶段仅允许复制或丢弃，不暴露 Library / 文件操作；失败即失去当前段落，不提供恢复；不扩大到 AI / 同步 / WebView；license 激活只走 Dodo 公开 endpoint，Mac app 永不嵌入 developer API key；checkout URL 在外部浏览器打开，不内嵌 WebView；danger 契约：沉默 5 秒触发红色 veil 与倒计时，8 秒清空草稿、留下持久文案 "Draft deleted. it joined the pile." 与一条丢失草稿的 fossil，红色 #c8392f 仅保留给 danger

[PROTOCOL]: 目录结构或核心约束变化时更新本文件，并检查 `../AGENTS.md` 与根目录 `AGENTS.md` 是否仍准确。
