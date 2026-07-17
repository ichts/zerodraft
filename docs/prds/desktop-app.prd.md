# zerodraft Desktop — 写作焦虑者的第一步工具

**版本**: v0.2 | **日期**: 2026-04-20 | **状态**: 草稿

---

## 1. Overview

**Feature / Project Name:** zerodraft Desktop (macOS → Windows)

**Problem Statement:**
大量人有写作欲望，但被写作焦虑阻断——觉得自己写得不好，迟迟无法落笔。现有的网页版 zerodraft 解决了"强制写作"的核心机制，但非技术用户对网页 app 有本能的隐私顾虑（"我写的东西会不会被存到服务器？"），导致最需要这个工具的人反而不敢用它。

**Proposed Solution:**
将 zerodraft 打包为原生 macOS 桌面 app（后续扩展 Windows），所有写作数据完全本地存储。写完后提供 AI 总结功能：默认通过服务端 API 调用，同时提供"复制到 ChatGPT/Claude"的 fallback，让不同技术水平的用户都能获得 AI 辅助。

**AI Build Summary:**
> Build a macOS desktop app using Wails (Go + existing HTML/CSS/Datastar frontend). Core mechanic: append-only writing with 8-second danger timer (stop typing → text fades and clears). All session data stored locally in SQLite. After each session, offer AI summary: (1) call server-side API endpoint, or (2) copy text + pre-written prompt to clipboard for user to paste into their preferred chatbot. No cloud storage, no account required. Ship as macOS .dmg first, Windows installer later.

---

## 2. Goals & Success Metrics

**Primary Goal:** 让有写作焦虑的人能够完成第一次"不完美写作"，并把它变成可用的内容。

**Success Metrics:**
- 用户完成率（启动写作 → 成功结束会话）> 60%
- 非技术用户首次打开到开始写作 < 30 秒
- AI 总结功能使用率 > 40%（表明用户真的想要输出，不只是宣泄）

**Business Model:** 一次买断（iA Writer 模式）
- macOS：App Store 定价 ¥98 / $9.99（参考 iA Writer 定价策略）
- Windows：Phase 2，同等定价
- 无订阅、无内购、无广告
- AI 功能：用户填自己的 OpenAI / Anthropic API Key，从本地直接调用，开发者零服务端成本

**Anti-goals:**
- 不是全功能写作编辑器（不支持格式化、标题、段落结构）
- 不是协作工具（无分享、无评论）
- 不是云同步产品（无账号系统，买断即拥有）
- 不替代用户最终用来发布内容的工具（它是"原材料生产机"）
- 不托管用户 AI 费用（用户自带 API Key）

---

## 3. Scope & Constraints

**In scope (MVP):**
- macOS 原生桌面 app（.dmg 分发）
- 完整的 zerodraft 核心机制（danger timer、append-only、多时长选择）
- 本地 SQLite 存储（历史记录、当前会话）
- AI 总结：服务端 API 调用 + 复制 prompt 的 fallback
- 历史记录查看界面（网页版缺失的功能）

**Out of scope (MVP):**
- Windows 版本（Phase 2）
- 账号系统 / 云同步
- 自定义 AI provider / 本地模型
- Markdown 导出
- 多语言界面（先做中文/英文双语）
- iOS / iPadOS

**Technical constraints:**
- 平台: macOS 13+ (Ventura)，arm64 + x86_64 universal binary
- 离线优先: 核心写作功能完全离线可用
- 隐私: 零遥测，零分析，无需网络权限即可使用（AI 功能除外）
- 分发: 初期直接分发 .dmg（不通过 App Store，避免沙盒限制）
- 包体大小: < 20MB（不含 Webview，macOS 系统自带）

---

## 4. Jobs to Be Done (JTBD)

| 优先级 | Job Statement |
|--------|---------------|
| J1 | 当我想写点什么但脑子空白、下不了笔时，我想要一个强制我开始打字的工具，这样我能打破"第一句话"的心理障碍 |
| J2 | 当我在写私密的、未成型的想法时，我想要确信我的文字不会离开我的设备，这样我能放心地写真实的想法 |
| J3 | 当我写完一段乱糟糟的文字后，我想要有人帮我梳理出其中真正想说的东西，这样我能把原材料变成可用的内容 |
| J4 | 当我回头想看之前写过什么时，我想要能找到历史记录，这样我能追踪自己思想的变化 |

---

## 5. User Stories

| ID | Role | Action | Benefit | JTBD |
|----|------|--------|---------|------|
| US1 | 写作焦虑者 | 打开 app 就能立刻开始写，无需注册/登录 | 不被摩擦打断写作冲动 | J1 |
| US2 | 写作焦虑者 | 看到倒计时压力，被迫持续打字 | 无法拖延，强制进入心流 | J1 |
| US3 | 隐私敏感用户 | 确认 app 无网络请求（写作时） | 放心写私密内容 | J2 |
| US4 | 想要输出的用户 | 写完后一键获取 AI 总结 | 把乱糟糟的原材料变成可读内容 | J3 |
| US5 | 不懂技术的用户 | 不会用 AI 功能时，能复制 prompt 到 ChatGPT | 用自己熟悉的工具完成总结 | J3 |
| US6 | 习惯性用户 | 浏览过去的写作记录 | 回顾自己的思想轨迹 | J4 |

---

## 6. Proposed Experience

**Design Direction:**
延续网页版的"沉浸式、极简、有点紧张感"的调性。桌面版增加一层"这是你的私人空间"的安全感——通过无窗口边框、深色纸张质感、无任何外链/广告来传达。

**Key Screens / States:**

- **Idle（选择时长）**: 极简居中，时长选择器，大号数字 + 开始按钮。首次打开显示一句话说明。
- **Writing（写作中）**: 全屏沉浸。顶部细长进度条 + 倒计时。居中文字区，光标在约38%高度（黄金比例）。危险状态：轻微模糊 + 红色脉冲边框。
- **Success（完成）**: 显示完整写作内容 + 字数。底部两个按钮：「AI 总结」和「复制全文 + Prompt」。
- **Failed（失败）**: 文字已清空的提示。已保存内容可查看。「再试一次」按钮。
- **History（历史）**: 列表视图，每条记录显示日期、字数、时长、状态。点击展开全文。
- **Empty state（无历史）**: "你还没有完成过一次写作。现在开始？"

**主用户流:**
1. 打开 app → Idle 界面
2. 选择时长（默认10分钟）→ 点击「开始写作」
3. Writing 界面：持续打字，危险机制激活/解除
4. 计时结束 → Success 界面
5. 点击「AI 总结」→ 调用 API → 显示总结结果（可复制）
6. 或点击「复制全文 + Prompt」→ 剪贴板 → 用户去 ChatGPT 粘贴

**Accessibility:**
- 支持 `prefers-reduced-motion`（与网页版一致）
- 动态字体大小（跟随系统设置）
- 高对比模式支持

---

## 7. Component Inventory

| Component | Type | Description | Stories |
|-----------|------|-------------|---------|
| DurationPicker | Form | 时长选择下拉/步进器 | US1 |
| StartButton | Action | 大号开始按钮，主 CTA | US1 |
| WritingArea | Display | append-only textarea，块 Backspace/Delete | US2 |
| DangerTimer | Display | 倒计时进度条 + 危险状态视觉 | US2 |
| SessionProgress | Display | 顶部进度条，显示已用时间 | US2 |
| PrivacyBadge | Display | 首次启动时的"数据仅存本地"说明 | US3 |
| AISummaryButton | Action | 写完后的主 CTA | US4 |
| SummaryResult | Display | AI 返回的总结文本，可复制 | US4 |
| CopyPromptButton | Action | 复制全文+prompt 到剪贴板 | US5 |
| HistoryList | Display | 历史记录列表 | US6 |
| HistoryItem | Display | 单条记录：日期/字数/时长/状态 | US6 |
| HistoryDetail | Modal | 展开查看完整写作内容 | US6 |

---

## 8. Data Models

```typescript
// 本地 SQLite 存储
interface Session {
  id: string;           // UUID
  content: string;      // 完整写作内容（包含所有 savedContent）
  wordCount: number;    // 字数（按空格/中文字符计算）
  duration: number;     // 预设时长（秒）
  elapsed: number;      // 实际写作时长（秒）
  status: 'success' | 'failed';
  aiSummary?: string;   // AI 总结结果（可选，异步填入）
  completedAt: string;  // ISO8601
  createdAt: string;    // ISO8601
}

// app 配置（本地持久化）
interface AppConfig {
  defaultDuration: number;    // 默认时长，秒
  aiEnabled: boolean;         // 是否启用服务端 AI 功能
  theme: 'light' | 'dark' | 'system';
  fontSize: 'small' | 'medium' | 'large';
}
```

---

## 9. API / Integration Surface

**AI 总结（本地直接调用，无服务端）：**

用户在设置中填入自己的 API Key，app 直接从本地调用：

```
POST https://api.openai.com/v1/chat/completions
Authorization: Bearer {用户的 API Key}

{
  "model": "gpt-4o-mini",
  "messages": [
    { "role": "system", "content": "你是一位写作顾问..." },
    { "role": "user", "content": "帮我总结以下内容：\n\n{写作内容}" }
  ]
}
```

支持的 provider：OpenAI（默认）、Anthropic（可选配置）

**Copy-to-Chatbot Fallback（无 API Key 时）：**

复制到剪贴板的内容格式：
```
以下是我用"不停笔写作法"写的内容，请帮我总结其中真正想说的核心观点，用简洁清晰的语言重新表达：

---
{用户写作内容}
---
```

**Wails 桌面层（Go ↔ Frontend 通信）：**

| Go Function | 描述 |
|-------------|------|
| `SaveSession(session Session)` | 写作结束后保存到 SQLite |
| `GetSessions() []Session` | 获取历史记录（最近50条）|
| `GetSession(id string) Session` | 获取单条记录 |
| `RequestAISummary(content string) string` | 用用户 API Key 直接调用 OpenAI/Anthropic |
| `CopyToClipboard(text string)` | 复制 prompt 到系统剪贴板 |
| `GetConfig() AppConfig` | 读取应用配置 |
| `SaveConfig(config AppConfig)` | 保存配置 |

---

## 10. State Management Map

| State | Location | Persistence | Notes |
|-------|----------|-------------|-------|
| screen | Datastar signal（前端） | Session | idle/writing/danger/success/failed |
| content | Datastar signal（前端） | Session | append-only，写作中临时 |
| savedContent | Datastar signal（前端） | Session | 已完成段落累积 |
| sessionActive | Datastar signal（前端） | Session | 控制 timer |
| sessions | SQLite（Go 层） | Persistent | 历史记录，最多保留 200 条 |
| appConfig | SQLite（Go 层） | Persistent | 用户偏好设置 |
| apiKey | **macOS Keychain** | Persistent | API Key 加密存储，不进 SQLite |
| aiSummary | Datastar signal（前端） | Session | API 返回后填入 |

---

## 11. Tech Stack

| 层 | 选择 | 原因 |
|----|------|------|
| 桌面框架 | **Wails v2** | Go 后端 + 直接复用现有 HTML/CSS/Datastar 前端；无 Electron 的臃肿感；Go 符合用户偏好 |
| 前端 | **现有 Datastar + CSS** | 零迁移成本，直接复用 |
| 本地存储 | **SQLite（modernc/sqlite）** | 纯 Go，无 CGO，单文件，跨平台 |
| AI 调用 | **本地直接调用 OpenAI/Anthropic API** | 用户填自己的 Key，零服务端成本，强化隐私定位 |
| 分发 | **GitHub Releases + .dmg** | 最低摩擦，不需要 App Store 审核 |
| 代码签名 | Apple Developer ID（$99/年）| 避免"来自未知开发者"警告 |

---

## 12. File Structure

```
zerodraft/
├── main.go                    # Wails app entry point
├── app.go                     # Go backend：Session、Config、AI 调用
├── wails.json                 # Wails 配置
├── build/
│   ├── darwin/
│   │   ├── Info.plist
│   │   └── zerodraft.icns     # macOS icon
│   └── windows/               # Phase 2
├── frontend/
│   ├── index.html             # 现有 index.html（微调）
│   ├── src/
│   │   └── styles/
│   │       ├── global.css     # 现有（直接复用）
│   │       └── animations.css # 现有（直接复用）
│   └── datastar-pro.js        # 现有
├── internal/
│   └── db/
│       ├── migrations/        # SQLite schema
│       └── queries.go         # Session CRUD
└── docs/
    └── prds/
        └── desktop-app.prd.md # 本文档
```

---

## 13. Acceptance Criteria

**US1 — 打开即写，无摩擦启动**
- [ ] 从 .dmg 安装到首次看到 Idle 界面 < 30 秒
- [ ] 不需要注册/登录/任何账号
- [ ] 首次启动显示隐私说明（"所有内容仅存本机"），可永久关闭
- [ ] 点击「开始写作」后 < 100ms 进入 Writing 界面

**US2 — Danger 机制完整运行**
- [ ] 停止打字 5 秒触发 danger 状态（模糊 + 红色脉冲）
- [ ] danger 状态再持续 3 秒（共 8 秒）清空文字
- [ ] Backspace / Delete / Cut 全部无效
- [ ] 计时结束自动进入 Success 界面

**US3 — 隐私保证**
- [ ] 写作过程中 app 无任何网络请求（可用 macOS 防火墙验证）
- [ ] 历史记录存储路径用户可见（设置中显示数据文件位置）
- [ ] AI 功能调用前显示明确提示"此操作将发送内容到服务器"

**US4 — AI 总结**
- [ ] 设置界面可填入 OpenAI / Anthropic API Key（加密存储在本地 Keychain）
- [ ] 未填 API Key 时，「AI 总结」按钮替换为「复制全文 + Prompt」
- [ ] 填了 API Key 后，Success 界面显示「AI 总结」按钮
- [ ] 点击后显示 loading 状态（不阻塞界面）
- [ ] 返回总结文字，可一键复制
- [ ] 网络失败 / Key 无效时显示错误提示 + 引导用 copy fallback

**US5 — Copy-to-Chatbot Fallback**
- [ ] 「复制全文 + Prompt」按钮在 Success 界面始终可见
- [ ] 点击后剪贴板包含完整 prompt（中文指令 + 写作内容）
- [ ] 按钮显示「已复制！」反馈 2 秒

**US6 — 历史记录**
- [ ] 历史界面显示最近 50 条记录
- [ ] 每条显示：日期、字数、时长、状态（成功/失败）
- [ ] 点击展开全文
- [ ] 可删除单条记录

---

## 14. Open Questions & Risks

- **Q**: AI 总结服务端用什么模型，费用谁承担？— *Owner: 产品决策*
  - ✅ **已决策**：一次买断（iA Writer 模式），用户自带 API Key，开发者零服务端成本

- **Q**: macOS 代码签名——是否需要立即申请 Apple Developer 账号？— *Owner: 工程*
  - 没签名会触发"来自未知开发者"弹窗，非技术用户会被吓退

- **Risk**: Wails 的 Webview 在 macOS 上渲染可能与 Safari 有细微差异（CSS 动画）
  - *Mitigation*: 早期用 `wails dev` 实机测试所有动画

- **Risk**: 现有 Datastar 的 `data-on-interval` 在 Wails Webview 中行为未验证
  - *Mitigation*: Day 1 搭完框架立即测试 timer 机制

- **Tradeoff**: 不上 App Store → 安装门槛略高（需要在安全设置中允许），但避免了沙盒限制和审核延迟

---

## 15. Rollout & Next Steps

**MVP（macOS v0.1）：**
- 包含: US1, US2, US3, US5（copy fallback），US6（历史记录）
- 排除: AI 服务端 API（US4）——先用 copy fallback 验证用户是否真的需要 AI 总结

**Phase 2:**
- US4: 接入 AI 服务端
- Windows 版本
- 自动更新机制（Wails 支持）

**Phase 3:**
- App Store 版本（沙盒适配）
- 本地模型选项（Ollama 集成）
- Markdown / 纯文本导出

**立即的下一步：**
1. 验证 Wails + 现有 Datastar 前端可以正常运行（搭空壳，测 timer）— *Owner: 工程*
2. 决定 AI 总结商业模式（免费/付费）— *Owner: 产品*
3. 申请 Apple Developer 账号（如果还没有）— *Owner: 运营*

---

*核心价值主张：zerodraft 不是写作工具，是走出写作焦虑的第一步。桌面版让最需要它的人——那些对隐私敏感、不懂技术、写出来的是私密想法的人——终于可以放心用它。*
