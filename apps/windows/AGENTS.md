# Windows app module instructions

Parent instructions: `../../AGENTS.md`

成员清单
cmd/wid: Windows 应用入口；`flavour_release.go` 是生产配置（服务地址、产品、公钥由 Mac `Info.plist` 生成，没有任何环境变量、文件或开关能改），`flavour_qa.go`（`-tags widqa`）只连本机 TEST 服务。
app/: Home、规则、激活、设置四个屏、路由与后台网络调用；试用与许可的状态只来自 `licence/` 的 Manager。
room/: 写作房间的状态、绘制与几何（Mac `SessionViewController` 的对应物）；`room.Config.Admit` 是试用扣次的唯一入口。
ime/: 前向只写的 `ui.TextInputClient`（Windows IMM32）；输入法行为只由真机 `scripts/ime-suite.sh` 证明。
session/: 纯会话时钟与字数（`SessionEngine.swift` 的移植），截止与擦除按绝对时刻竞争，平局归擦除。
paper/: Wheat 纸面纹理（`PaperField` 的移植）。
licence/: licence service 的 Windows 客户端（token 验证、activate/validate/deactivate、checkout、试用、离线宽限、撤销）；token、订单号、状态与试用计数只存 Windows Credential Manager，绝不落文件；`fakeservice/` 只供无头单测。
tokens/: 由 `scripts/gen_tokens.py` 从 `../macos` 源码生成的颜色、间距、常量与文案，禁止手改。
fonts/: Mac 应用字体文件的逐字节拷贝（`go:embed` 不能越出模块），`scripts/check_tokens.sh` 校验一致。
cmd/qaserver、cmd/drv、cmd/imecheck、cmd/papershot: QA 与真机验收工具，不进发布包。
packaging/: MSIX 清单、素材与签名/安装脚本；`STORE.md` 是 Store 身份表。
scripts/: 生成器、漂移门槛与 vivobook-1 真机脚本（IME 套件、截图度量、端到端）。
SYNC.md: Mac 到 Windows 的对等账本，每个 Mac 行为、token、文案一行；Mac 改动后在同一 PR 里更新对应行。
README.md: 构建、测试、漂移门槛、CrychicUI 钉版、真机脚本。

对外暴露
Windows 可执行文件（`mygo build` / MSIX）；与 Mac 同价、同许可池，通过 `services/license` 的 HTTP 契约激活，不改该服务。

法则
- 价格、许可、两台设备与 14 天退款与 Mac 一致；`platform: "windows"` 是服务已接受的取值。
- Mac 源码是 token 与文案的唯一来源：`tokens/tokens_gen.go` 与 Mac 不同步时 CI 失败（`scripts/check_tokens.sh`），先重新生成、跑 `go test ./...`、再改 `SYNC.md`。
- 不依赖未入库的 CrychicUI 本地副本：`go.mod` 钉提交伪版本；不 vendoring。
- 测试只连 `licence/fakeservice` 或 `cmd/qaserver` 的 loopback 假 Stripe，任何位置都不放真实或 live 密钥。
- 草稿文本只在内存；不写统计、历史或 localStorage 类持久化。
- 真机 IME 套件、截图度量和端到端脚本不是 CI；发布前必须在 Windows 真机上跑（见 README）。

[PROTOCOL]: When this directory's structure or invariants change, update this file and `SYNC.md`, and verify `../../AGENTS.md` remains accurate.
