# writeitdown macOS module instructions

Parent instructions: `../AGENTS.md`

成员清单
Package.swift: `WriteItDown` Swift Package 可执行目标，支持 macOS 14+；源码路径仍为 `FirstLine`，先保证 `swift build` 与 `swift test` 通过；精确锁定 Sparkle 2.10.0 并为二进制目标加 `@executable_path/../Frameworks` rpath，`Package.resolved` 入库。
scripts/package-app.sh: universal SwiftPM release `.app` 打包器；用 `ditto` 把 Sparkle.framework 装进 `Contents/Frameworks` 并校验 rpath、`Updater.app` 与 universal 架构；把解析出的 Sparkle MIT LICENSE 复制为 `Contents/Resources/Sparkle-LICENSE.txt`（缺失即失败）；支持 ad-hoc 和 unsigned 模式，具体构建与签名契约见脚本头。
scripts/sign-nested.sh: package-app.sh 与 release-dmg.sh 共用的 inside-out 签名：先签每个普通 Mach-O（Sparkle 的 Autoupdate），再由深到浅签 bundle，最后签 app，并校验 `codesign --verify --deep --strict`；Developer ID 模式还要求每个可执行文件的 TeamIdentifier 与 app 一致（公证前的失败门槛）。
packaging/VolumeIcon.icns: DMG 卷图标，深色圆盘加骨白纸面和墨色 split-W；品牌与尺寸规则见 `../../../design/DESIGN.md` §11。
scripts/release-dmg.sh: Developer ID 签名、公证及 DMG 打包器；正式发布拒绝空或不完整的许可配置，也拒绝占位更新签名公钥、非 HTTPS appcast、false/缺失的 `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction`、非 0 的 `SUSignedFeedFailureExpirationInterval`、缺失/不可读/不是单一整数的 `last-build.txt` 或未递增的 CFBundleVersion；公证+staple 之后用同一个 app 生成 `dist/updates/WriteItDown-<version>-<build>.zip` 更新载荷并记录 `last-build.txt`（staging 既不产 ZIP 也不记 build，因此也不受递增门槛约束）。TEST/LIVE 共用 Info.plist 中服务地址、产品及公钥。发布检查见 `docs/RELEASE_CHECKLIST.md`，契约见脚本头。
scripts/plist-value.py: 发布脚本读取 Info.plist 字段的唯一入口，用 `plistlib` 而非 `/usr/libexec/PlistBuddy`，因为 `scripts/test-release-config.py` 在 Linux CI runner 上执行这些门槛，那里没有 PlistBuddy。
scripts/update-payload-name.sh: 更新载荷文件名的唯一定义（`WriteItDown-<version>-<build>.zip`），发布打包器写入与 appcast 生成器查找共用；名字必须随字节变化，否则 immutable 缓存会把旧载荷发给已安装副本。
scripts/sparkle-key.py: 更新签名密钥与 `SUPublicEDKey` 是否同一对的唯一证明（Keychain 走 `generate_keys -p`；密钥文件在 openssl 支持 Ed25519 时把种子包成 PKCS#8 交给 `openssl pkey`，macOS 自带 LibreSSL 不支持时打印告警并改用内置 RFC 8032 推导，该安全敏感回退由 RFC 向量测试覆盖并需盲审）；`generate_appcast` 对不匹配只告警、`sign_update --verify` 自签自验，都不能替代它。
scripts/publish-appcast.sh: 先用 `sparkle-key.py` 证明密钥对，再用 Sparkle 的 generate_appcast 生成带内嵌签名的 appcast 与 delta，并机械校验（新 build 唯一一条、有 minimumSystemVersion、无 hardwareRequirements、enclosure 签名与 feed 内嵌签名都 `sign_update --verify` 通过）；工具只来自 `.build/artifacts/sparkle/Sparkle/bin`（必要时 `swift package resolve`）或 `WID_SPARKLE_BIN` 指向的 Sparkle 2.10.0 归档，不使用宿主机 /Applications 副本；脚本本身不上传，上传顺序与 curl 验证步骤只由 `writeitdown/README.md` 拥有。
scripts/test-release-config.py: 沙箱执行 release-dmg.sh 与 publish-appcast.sh 的门槛，验证正式包拒绝缺项、非 HTTPS 地址、无效公钥、占位/无效更新公钥、未开启的 signed-feed 策略、unsafe appcast、缺失/非整数 `last-build.txt` 或非递增 build number，staging 不得带销售配置且不受 `last-build.txt` 约束，以及签名密钥不匹配时在 generate_appcast 之前就失败；不构建、不签名，供网页 QA 单次调用。
scripts/release-dmg.sh: Developer ID 签名、公证及 DMG 打包器；正式发布拒绝空或不完整的许可配置，TEST/LIVE 共用 Info.plist 中服务地址、产品及公钥。发布检查见 `docs/RELEASE_CHECKLIST.md`，具体契约见脚本头。
scripts/test-release-config.py: 沙箱执行 release-dmg.sh 的配置门槛，验证正式包拒绝缺项、非 HTTPS 地址和无效公钥；不构建、不签名，供网页 QA 单次调用。
scripts/test-vm-rig.py: 录制验收 rig 共享边界的可执行检查（模型答复按阶段与镜头身份校验、必需六视角按名点齐、标记片段的时间原点、分析器丢帧失败、报告录制元数据来源、被跟踪的字节码产物、prepare-guest 与 launchd 垫片的加载契约）；字节码检查读整个仓库索引（`git ls-files` 在仓库根执行），不是 rig 子目录，任何子树的 `__pycache__` 或 `*.pyc` 都会让它失败；直接调用真实脚本与 git 并断言其输出，含已知破例（旧时间原点、丢掉的截图、旧 jq 过滤器、非镜头 JSON、截断的回合、同一份答复冒充六个视角、被跟踪的 __pycache__、垫片缺失）。
scripts/dmg-journey.sh: 真实发布 DMG 的签名、安装副本和三次试用 AX 验收；执行与证据契约见 `../../../writeitdown/README.md` 的 "Shipped Mac journey"。禁止在 Mini 屏幕运行 GUI journey。
scripts/vm-journey.sh: 在 Mini 的 Tart macOS 虚拟机里执行录制式验收（GUI 永不出现在 Mini 自己的屏幕上）：克隆 wid-golden、在 guest 内装入 DMG（传 .app 时改跑持证启动证明）、用真实 HID 输入驱动、以全帧率帧流合成一段连续 screen.mov，并在同一 evidence bundle 内跑完 design-panel.sh 的六视角评审（按名校验 Rams、Norman、Spiekermann、Kare、Matas、Vignelli，短列表或改名都不能签核）；退出码：0 干净通过、1 拒绝、78 已声明缺陷复现（不是通过）、79 六视角评审未完成（不能签核）、2 rig 配置错误；已声明缺陷按 sha256 加断言 id 精确匹配，缺陷不再复现即判失败。宿主脚本经 vm/launchd-host.sh 以 launchd job 运行，绕过 macOS 本地网络隐私对未授权 app 的阻断。契约见脚本头。
scripts/design-panel.sh: 录制包的分析与评审阶段，作为 vm-journey.sh 的最后一阶段运行（也可对已有 bundle 单独补跑）：先跑 vm/analyse-recording.py 的确定性检测（判据来源，可让运行失败），再对标记窗口取短片段交模型评审并做 before/after 视觉校验，最后六视角（Rams、Norman、Spiekermann、Kare、Matas、Vignelli）各出一份按严重度排序的意见，汇总成自包含 report.html。短片段以录制首帧时间戳为时间原点，报告头部的录制数字取自 recording.tsv；所有模型答复经 vm/panel-lib.py 按阶段校验（必须正常结束、带该阶段字段，镜头答复还必须声明被询问的那个镜头），否则记为 unavailable 并附确切原因；模型路由不可用记为已声明能力缺口，不静默跳过。契约见脚本头。
scripts/qa-window.sh: cua-driver 真实窗口验收，自行打包并隔离用户配置；WID_QA_LICENSE_ONLY=1 从无配置首次启动检查三次试用、末次擦除报告及耗尽重启、签名 fixture 激活、离线及退款；不证明真实购买。scripts/qa-license-fixture.go 是仅 loopback 的临时签名服务。
docs/WRITEITDOWN_PLAN.md: 本应用改造为 writeitdown macOS app 的现行计划（产品规则映射、时长选择器、删除清单、分批验收、已定的签名 DMG 付费分发）；与下列历史 Zero Draft 文档冲突时以它为准。
docs/RELEASE_CHECKLIST.md: 直接分发签名/公证/DMG 发布清单，含 Updates（Sparkle）一节：build number 递增、signed-feed 策略、ZIP 载荷、密钥对与 feed/签名校验、先载荷后 feed、feed 200 与缺失文件 404、下载页发布说明版本、universal 与真实窗口证据。
docs/RELEASE_KEY.md: 船长在发布 Mac 上创建、备份更新签名私钥的完整步骤（generate_keys、公钥进 Info.plist、导出后存 1Password 再删除、绝不入库），以及签名 feed 后该密钥即为永久信任锚、不存在“换钥恢复”路径的契约。
docs/LAUNCH_PLAN.md: 历史 Zero Draft 发布规划；writeitdown 当前分发与视觉方向见 `docs/WRITEITDOWN_PLAN.md` 和 `writeitdown/AGENTS.md`。
docs/LICENSE_PAYMENT_SPEC.md: 签名许可服务、Mac 激活及真实订单发布门槛；支付适配器契约见 `services/license/README.md`。
docs/LAUNCH_TODO.md、docs/POLAR_PRODUCT_CHECKLIST.md、docs/POLAR_OWNER_STEPS.md: 历史 Dodo/Polar 发布材料，不适用于当前签名许可服务。
docs/MANUAL_QA.md: 历史检查清单与按批次记录的窗口 QA 结果；行为验收以 `../../../docs/wid-mac-behavior.md` 为准，视觉验收以 `docs/WRITEITDOWN_PLAN.md` 第 6 节为准。
架构：纯 AppKit（无 SwiftUI；全仓 `grep import SwiftUI` = 0）。@main 是 NSApplication 入口，各 surface 是 NSViewController，经 RootContainerViewController 原地切换；编辑器与状态机复用。
Sources/FirstLine/App/FirstLineMain.swift: 纯 AppKit @main 入口；持有 AppState、构建菜单和窗口、激活应用；桥接新篇、整篇复制、关闭窗口、检查更新等菜单动作与验证；只在真实 .app 内启动 UpdateController，并把更新开关注入窗口。
Sources/FirstLine/App/MainMenuBuilder.swift: NSApp.mainMenu 构建（Settings Cmd+,、新篇 Cmd+N、成稿复制 Cmd+C、关窗 Cmd+W、真实更新器存在时才有的 Check for Updates…）。
Sources/FirstLine/App/RootWindowController.swift: 主窗口 NSWindowController（把 UpdateSettings 透传给内容容器）；窗口只 size 一次，contentViewController 是常驻 RootContainerViewController；观察 AppState.selectedSurface（切 surface）、settings.theme（窗口 appearance）；启用鼠标移动事件供专注模式悬停显示计时/字数，原生退出全屏时同步关闭写作中的专注偏好，导航导致的退出则保留偏好；所有会话相位留在同一个房间。
Sources/FirstLine/App/RootContainerViewController.swift: 常驻窗口内容控制器；各 surface 以子 VC 原地切换（addChild/removeFromParent + 视图 autoresize 填充），把窗口尺寸与 surface 解耦，避免每次换 contentViewController 触发的 0x0 fitting-size / 递归 layout；把 UpdateSettings 转交给按需新建的 Settings surface。
Sources/FirstLine/App/AppState.swift: 顶层导航与 `isWritingSessionActive`（更新界面时机的唯一判据：整个 Session surface，或离开房间后仍在其他 surface 上继续走的会话）、三次会话首个非空输入持久扣次、试用耗尽后会话启动及首输入签名许可门槛（拒绝启动先清空会话再进激活页）、Info.plist 价格/版本/HTTPS checkout 配置、license 激活/启动校验入口及签名 token 访问门槛（契约见 `docs/LICENSE_PAYMENT_SPEC.md#entitlement-and-persisted-state`；@Observable，来自 Observation，非 SwiftUI）；所有会话正文只在内存。
Sources/FirstLine/App/HomeViewController.swift: 无营销文案的开写前“How long?”白卡片；顶部为 split-W lockup，右上角一个小而安静的“?”打开规则页；五个时长分段按钮 + 三个静默分段只做选择并持久化，单个 Begin 启动选中时长；无副标题；默认 Begin 获焦点；通过 Observation 更新异步许可状态与试用计数。
Sources/FirstLine/App/RulesViewController.swift: 由选择器“?”打开的规则 sheet；复用 landing “How it works”的文案与顺序（No way back / Eight seconds of silence / Reach zero, keep it），Done 或 Return 关闭，Esc 取消，明暗皆用 After 卡片。
Sources/FirstLine/Info.plist / Assets.xcassets/: 应用元数据与图标资源；含 Sparkle 的 `SUFeedURL`、`SUPublicEDKey`（船长的更新签名公钥，私钥只在 Mac mini login Keychain）、`SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction`（成对开启，app 必须拒绝被改写的 feed）、`SUSignedFeedFailureExpirationInterval=0`（没有 20 天安全模式宽限）、`SUEnableAutomaticChecks=false`（默认不检查、也不弹许可提示）与 `SUScheduledCheckInterval=86400`；AppIcon 使用 A split-W 标记，AppIcon `.icns` 只含浅色稿，图标内不出现红色；尺寸与配色规则见 `../../../design/DESIGN.md` §11。
Sources/FirstLine/Editor/AppendOnlyTextView.swift: 自定义 NSTextView，append-only、IME 安全（wipe 时丢弃 input context 的 marked 组合；过期替换范围忽略）、非空输入前试用授权、居中 zen 排版、当前行固定在纸张 35% 锚点、固定 1.6 行距（中文/英文/混排一致）、逐行不透明度（当前 100%/上一行 22%/再上一行 7%，更早隐藏）、caret 锚点；由 SessionViewController 直接以 NSScrollView 托管。
Sources/FirstLine/Editor/AppendOnlyInputPolicy.swift: append-only 输入守卫的单一可测来源（被屏蔽命令选择器 + UTF-16 末尾选区重定向），供 SessionViewController 的 NSTextViewDelegate 与 EditorFocusTests 共用。
Sources/FirstLine/Infrastructure/AppPaths.swift: Application Support/WriteItDown 配置路径规范；不导入旧 First Line 目录，草稿不落盘。
Sources/FirstLine/Infrastructure/SettingsStore.swift: 设置读写、写作偏好与许可缓存；保留无 key 的许可记录以阻止回退试用，损坏试用计数独立耗尽，不丢弃可解码许可；统一 ASCII SPACE/TAB/CR/LF 凭据裁剪与空值判断；许可门槛见 `docs/LICENSE_PAYMENT_SPEC.md`。
Sources/FirstLine/Infrastructure/InstallIDStore.swift: 生成并持久化 stable install UUID，以完整 UUID 作为 service activate 的 installLabel。
Sources/FirstLine/Licensing/LicenseModels.swift: LicenseStatus、LicenseActivation 及激活/校验错误；订单号沿用持久化 licenseKey 字段。
Sources/FirstLine/Licensing/LicenseClient.swift: activate / token validate / deactivate 及本地 token 校验边界。
Sources/FirstLine/Licensing/LicenseTokenVerifier.swift: CryptoKit Ed25519 签名及产品/完整设备 UUID/七天有效期校验。
Sources/FirstLine/Licensing/WaffoLicenseClient.swift: 无状态 URLSession service 客户端，拒绝 redirect；请求及响应见 `docs/LICENSE_PAYMENT_SPEC.md`。
Sources/FirstLine/Licensing/CheckoutClient.swift: 无状态 POST /api/v1/checkout 客户端，只接受 https checkout.stripe.com 目标，拒绝 redirect；错误交给 AppState 回退；不记录 URL/买家凭据。
Sources/FirstLine/Session/SessionEngine.swift: 可选时长和静默阈值的 danger / failure / success 状态机与单调时间规则；首输入启动时钟、绝对截止裁决、按 deadline 计算 unusedSeconds 和删除时已过秒数、Unicode 词数（纯 Foundation）；失败后重启须由 AppState 授权。
Sources/FirstLine/Session/RoomPresentation.swift: 时钟、按未用尽时间与剩余试用/许可分流的擦除句（live 原文）、字数与 `N MINUTES. N WORDS.` kept 小型大写收据（与失败收据同格式）、wash 强度、复制、两步退出确认计时及拒绝反馈状态规则。
Sources/FirstLine/Session/SessionKeptView.swift: 成稿布局：`You wrote it down.` 标题 + 小型大写 `5 MINUTES. 63 WORDS.` 收据 + COPY TEXT（贴标签宽度的 ink pill）/ RUN IT AGAIN（48 pt 细描边次按钮），两标签在行的光学中心；正文可滚动、固定顶部动作，每次尺寸变化自重排居中。
Sources/FirstLine/Session/SessionViewController.swift: 单一 Session 房间（AppKit）的 After 白纸：page/sheet、clock/count、居中 zen 书写（当前行固定在纸张 35%，逐行不透明度 100/22/7，更早隐藏）、wash/numeral、空态 C（光标只在书写线，count 槽 `Type to start`）；失败屏为成稿屏的对应面：`You stopped.` 标题、48 pt 细描边 `Begin again`（Return 触发）、下方红色 DRAFT DELETED 收据，输入仍可重开；成稿屏 `You wrote it down.` + `N MINUTES. N WORDS.`；无顶部 pill、仅顶部 2pt 会话条（无底部静默条）；两步 Esc/点击退出提示（2 秒窗口，输入即取消）；托管 AppendOnlyTextView、首响应者、100ms tick、新 session ID / wipe / 拒绝重启时清空编辑器；NSTextViewDelegate 守卫用 AppendOnlyInputPolicy。
Sources/FirstLine/Upgrade/UpgradeViewController.swift: After 白卡片激活面；订单号/激活码、Activate、Buy、价格/网页试用；Buy 通过 AppState 调用 CheckoutClient，契约见 `docs/LICENSE_PAYMENT_SPEC.md#in-app-checkout`；观察异步许可与 checkoutInFlight 并原位更新；active 状态显示 Start writing。
Sources/FirstLine/Settings/SettingsViewController.swift: After 白卡片 Settings，含 appearance、Updates（仅有真实更新器时显示 `Check for updates automatically`）、motion、focus、alignment、font size、License；popup 与 focus switch 使用 FirstLineInkPopUpButton/FirstLineInkFocusButton，文本字段保留系统焦点环；观察异步许可与 checkout 变化并原位更新状态、不清除输入；时长和静默档只在 Home 选择，Done 返回进入前的 surface。
Sources/FirstLine/DesignSystem/Colors.swift: writeitdown tokens.css v2（background A + 暗色同名角色）的 NSColor dynamic provider：page/sheet/ink/mute/chrome/hair/red/tag/on-ink/wash；无并行 palette。
Sources/FirstLine/DesignSystem/Typography.swift: 系统无衬线 UI/标题字号 + bundled Newsreader 书写、kept 标题（Roman-Medium）和警告数字 token；不再把 IBM Plex Mono 用于界面 chrome。
Sources/FirstLine/DesignSystem/FirstLineButtons.swift: After 语言主按钮（48 ink pill）、次按钮（outline pill，默认 44，成稿重开 48）和 quiet link；ink 主按钮的焦点是贴在药丸边缘的一圈浅色环（无外侧深色边），次按钮保留外侧 ink 焦点环；房间主按钮有 160ms live hover/press 反馈与 reduced-motion；updateLayer 只改 layer 视觉属性，绝不在其中设 content 属性（避免 _NSViewLayoutFeedbackLoop 无限回环卡死）。
Sources/FirstLine/DesignSystem/InkFocus.swift: 共享 ink focus ring 安装器与可测协议；按钮、分段、popup 和 checkbox 共用一圈贴控件的焦点环，主 ink pill 用贴边浅色环，禁用系统蓝环。
Sources/FirstLine/DesignSystem/FloodCanvasView.swift: appearance-aware wall/paper 背景 NSView；updateLayer 里重解析 dynamic NSColor.cgColor（避免静态 cgColor 在暗色下解析错）。
Sources/FirstLine/DesignSystem/WritingFontCandidate.swift: 固定写作字体定义与本地字体注册，英文 Newsreader + IBM Plex Mono，中文 Zhuque Fangsong；打包应用优先从 `Contents/Resources` 中的 SwiftPM bundle 读取，裸二进制使用 `Bundle.module`。
Sources/FirstLine/DesignSystem/Spacing.swift: 4-pt 间距与 ctl/sheet/card/stage 圆角 token。
Sources/FirstLine/DesignSystem/SurfaceViews.swift: FirstLineShadowView（sheet-shadow 的 ring + 多层 ink/black 阴影）与 FirstLineCardView（白/暗 sheet + shadow + content insets）。
Sources/FirstLine/DesignSystem/Controls.swift: After 语言 seg control、status 和 fill bar；原生可聚焦按钮与 appearance-aware 颜色。
Sources/FirstLine/DesignSystem/BundledResources.swift: 统一的 SwiftPM/打包应用资源 bundle 入口；字体注册与 split-W lockup 共用，避免重复 bundle 名与回退逻辑。
Sources/FirstLine/Resources/write-it-down-lockup.svg: 开写前选择面使用的 wordmark-only split-W lockup，是 Mac 自己的副本；不要与 Web 的两层掩膜同步（`writeitdown/logo/write-it-down-lockup.svg` 现在是 chip W 加词标的 glyph 层），否则开始屏会出现重复的 W。模板着色为应用 ink token。
Tests/FirstLineTests/SessionEngineTests.swift: Session engine 状态流转与时长截止测试。
Tests/FirstLineTests/SilenceLimitTests.swift: 三档静默警告/删除、恢复及平局裁决。
Tests/FirstLineTests/BatchFiveTests.swift: 时长选择、设置持久化和键盘动作验收。
Sources/FirstLine/Update/UpdatePolicy.swift: 更新界面的时机真相源（纯 Swift，无 Sparkle 类型）：写作会话活跃时（房间任何阶段，或从房间进 Settings 后仍在走的会话）永不展示更新 UI，菜单命令只在有更新器且写作会话不活跃时可用，`UpdateDeferralPolicy` 记录被推迟的更新并至多请回一次。
Sources/FirstLine/Update/UpdateUserDriver.swift: `SPUStandardUserDriverDelegate` 的 gentle reminder 实现（定时更新一律由 delegate 决定展示时机），以及继承 `SPUStandardUserDriver` 的写作闸门：每个展示入口都在展示前检查写作会话是否活跃，活跃时取消检查/下载、回复 dismiss 已出现的窗口、只留下待办标记；不保存 appcast item。
Sources/FirstLine/Update/UpdateController.swift: Sparkle 标准更新器入口（仅在真实 .app 内启动，直接构造 `SPUUpdater` 以使用写作闸门）；Settings 开关写 `updater.automaticallyChecksForUpdates`，菜单动作是唯一手动检查入口；观察 `isWritingSessionActive` 与应用激活，会话一活跃就结束已有更新窗口，会话结束或回到前台时把推迟的更新请回。`UpdateSettings` 是 Settings 面依赖的最小接口。
Tests/FirstLineTests/RoomTests.swift: 房间 live 文案、无 pill、时钟、wash 恢复/cut 收尾/减少动态效果、deny、复制状态跨 tick/hover/字体刷新与新会话重置、居中 kept 与两步退出（含 2 秒过期和输入取消）、真实 NSTextInputClient 组合/删除序列、wipe 后用真实 Apple Pinyin input context 验证首键、失败屏标题/Begin again/Return/红收据、kept 无滚动条但可滚动、复制按钮焦点/反馈测试。
Tests/FirstLineTests/BrandTests.swift: 开始屏 split-W lockup、“?”规则页的 landing 文案/顺序/Done/Return/Esc，开始屏无副标题。
Tests/FirstLineTests/CheckoutClientTests.swift: 本地 URLProtocol fixture 验证 POST 格式、hosted URL、非 Stripe/重定向/错误拒绝，以及 AppState 成功打开 hosted URL、失败回退 mac.html。
Tests/FirstLineTests/CheckoutFixtures.swift: CheckoutClientTests 的测试替身（MockCheckoutClient）；仅测试目标，不建真实会话、不扣款。
Tests/FirstLineTests/DesignTokenTests.swift: background A 与暗色 role 的颜色解析、system-sans 界面与 Newsreader 书写字体断言。
Tests/FirstLineTests/SnapshotTests.swift: 真实 AppKit surface 在 1040x720 的 light/dark（含 typing fade、exit hint、reduced warning、focus、active/entry 状态、带更新开关的 Settings）PNG 快照与 page/sheet/kept 焦点像素断言；WID_SNAPSHOT_DIR 写证据，不开窗口捕获。
Tests/FirstLineTests/EditorFocusTests.swift: 编辑器焦点与会话启动回归测试。
Tests/FirstLineTests/PinyinInputTests.swift: NSTextInputClient 入口的 Apple Pinyin/WeType/双拼组合、候选键、unmark-then-replace 记账与拒绝边界测试。
Tests/FirstLineTests/ReviewRoundTests.swift: 评审回归：空态与擦除后光标、kept 动作光学中心与长稿、窗口 resize 重排、规则页鼠标命中、kept 重启、设置/激活卡布局与警告 wash 像素。
Tests/FirstLineTests/RoundThreeTests.swift: 第三轮 hands-on 回归：卡片对齐、空态 caret/count、纸张几何、单条会话条动画（含 wipe 后重开）、警告/收据 ink 位置、退出行基线与组合安全。
Tests/FirstLineTests/SettingsStoreTests.swift: 设置持久化、默认值与 legacy 字段迁移测试。
Tests/FirstLineTests/SmokeFlowTests.swift: 端到端 smoke tests，覆盖成功与失败不落盘、菜单无 Library、已激活导航、退款后的 restart 拒绝与无 key 拦截。
Tests/FirstLineTests/LicenseFlowTests.swift: license 激活成功/失败路径、validate 7-day 离线宽限、active/revoked 与首输入许可 gate 交互。
Tests/FirstLineTests/LicenseEntitlementTests.swift: 试用耗尽激活页、网页链接、菜单绕过、旧解锁标记无效、合法激活及重启回归。
Tests/FirstLineTests/TrialReleaseTests.swift: 三次试用、首输入及 IME 扣次、失败重启、末次成稿、读写失败关闭访问、激活和退款不恢复次数。
Tests/FirstLineTests/UpdateTests.swift: 更新时机策略、Session surface 闸门、推迟待办策略、标准 driver 在房间内的取消/acknowledge 行为、Info.plist 更新契约（默认不检查、HTTPS feed、32 字节公钥、signed-feed 策略成对开启、正整数 build）、Settings 更新开关（替身实现 UpdateSettings）与菜单项位置/可用性。
Tests/FirstLineTests/WaffoLicenseClientTests.swift: URLProtocol HTTP 合约、真实 Ed25519 签名失败、token 续期、持久化旧缓存、首次未激活拦截、退款和精确七天边界；不触外网。
Tests/FirstLineTests/MockLicenseClient.swift: 仅测试目标的状态机替身，不随应用发布，不证明真实签名或购买。
Tests/FirstLineTests/LicensedTestState.swift: 编辑器/导航测试的显式 mock 许可 fixture；许可测试直接构造 AppState，不使用此快捷设置。

验证命令
从本目录运行 `swift build` 和 `swift test`。界面、编辑器、键盘、IME 或发布流程变更还必须执行相关的 `docs/MANUAL_QA.md` 项目，并记录无法执行的检查。

对外暴露
可执行目标 `WriteItDown`

法则: After 视觉契约见 `docs/WRITEITDOWN_PLAN.md` 第 6 节；草稿只在内存中，许可与设置仍可持久化；Mac 前三次会话免费，之后 USD $4.99 一次付费，2 Macs，14-day refund；首个非空输入（含组字）前持久扣次，读写失败关闭试用；已有许可记录不可回退试用；耗尽后呈现许可入口及完整网页试用链接；开写前时长 1/5/10/20/30 分钟、静默清空 5/8/12 秒，写作中锁定两者；Begin 启动选中时长；首输入启动倒计时，只有截止时间能成功，失败留在原房间且下次输入重启；房间无顶部时长 pill，Esc 或 ESC - EXIT 首次只显示 2 秒内再次确认的提示，输入即取消；保持 macOS native only；编辑器必须 append-only 且不破坏 IME；有试用余次或激活/启动校验通过后可进入极简 Home（门槛见 `docs/LICENSE_PAYMENT_SPEC.md#entitlement-and-persisted-state`）；末次试用可完成及复制，下一会话才设门槛；无余次且无许可不允许 Home/Settings/房间或菜单绕过，不提供 intro / warm-up onboarding；无侧边栏，单一写作房间承载 rest/typing/warn/wipe/kept，导航通过 AppState.selectedSurface 路由；kept 阶段仅允许复制、重来或退出，不暴露 Library / 文件操作；失败即失去当前段落，不提供恢复或 fossil；不扩大到 AI / 同步 / WebView；更新只走 Sparkle 2.10.0 且默认不检查（`SUEnableAutomaticChecks=false`），只有 Settings 开关或 `Check for Updates…` 菜单会发起检查，Session 房间（空、写作、警告、失败、成稿）显示期间绝不展示更新窗口（用户发起的检查与所有展示路径都拒绝或推迟，已出现的窗口在进房间时结束并留下待办），私钥只属于船长且不入库；license 激活只走 `docs/LICENSE_PAYMENT_SPEC.md` 定义的签名许可服务，Mac app 只内置 Ed25519 公钥，不含 merchant/developer API key；无订单号或无合法签名 token 的旧状态不能解锁；真实 TEST 订单和已安装发布 DMG 的窗口激活通过前不得开启 LIVE 收款；购买页、密钥交付和 TEST-to-LIVE 门槛见 `../../../writeitdown/README.md`；in-app Buy 与回退的契约见 `docs/LICENSE_PAYMENT_SPEC.md#in-app-checkout`；danger 契约：清空前最后三秒出现 wash 与倒计时，选定阈值清空草稿并显示房间内报告，警告色使用 `writeitdown/tokens.css` 的 red token

[PROTOCOL]: 目录结构或核心约束变化时更新本文件，并检查 `../AGENTS.md` 与根目录 `AGENTS.md` 是否仍准确。

## Maintaining this file

只保留未来会话普遍需要的模块知识。优先指向权威文件和验收命令，不复制代码细节；更新时优先改写或删减既有条目，保持简洁。
