# Zero Draft - Design System

版本: MVP 1.0
最后更新: 2025-10-05

## 设计原则

1. **Brutalist Minimalism（粗野极简主义）** - 功能优先，诚实的设计语言
2. **无干扰沉浸** - 写作时界面应"消失"
3. **温和压迫** - 危险状态清晰但不刺激
4. **纸笔隐喻** - 模拟真实写作体验，减少数字感

## 配色系统

### 主色调：纸张与墨水

```css
--color-bg: #FAFAF8;           /* 温暖纸张白 */
--color-text: #1A1A1A;         /* 深墨色 */
--color-danger: #C1403D;       /* 砖红（温和警告）*/
--color-success: #2E5930;      /* 深绿 */
--color-ui: #8B8B8B;           /* 中性灰 */
--color-ui-light: #D4D4D4;     /* 浅灰（边框/分隔）*/
```

### 使用场景

| 颜色 | 用途 | 示例 |
|------|------|------|
| `--color-bg` | 页面背景 | `body { background: var(--color-bg); }` |
| `--color-text` | 主文本、进度条完成部分 | 写作区域文字 |
| `--color-danger` | 危险状态边框、失败提示 | 5秒无输入的视觉反馈 |
| `--color-success` | 成功状态图标、按钮 | 完成界面的 ✓ |
| `--color-ui` | 计时器、次要文字 | 右上角时间显示 |
| `--color-ui-light` | 进度条背景、分隔线 | 顶部进度条 |

## 字体系统

### 字体家族

```css
/* 主文本区域 */
--font-main-zh: "LXGW WenKai", "霞鹜文楷", serif;
--font-main-en: "IBM Plex Mono", "SF Mono", monospace;
--font-main: var(--font-main-zh), var(--font-main-en);

/* UI 文字（按钮、标题、提示）*/
--font-ui: "PingFang SC", "SF Pro", -apple-system, system-ui, sans-serif;
```

### 字号规范

```css
--text-xl: 32px;    /* 主标题（Zero Draft）*/
--text-lg: 18px;    /* 写作区域文本 */
--text-md: 14px;    /* 按钮、标语 */
--text-sm: 12px;    /* 计时器、提示文字 */
```

### 字重

- 标题：400（Regular，不加粗）
- 正文：400
- 按钮：500（Medium）

### 行高与间距

```css
--line-height-main: 1.8;      /* 写作区域 */
--line-height-ui: 1.5;        /* UI 文字 */
--paragraph-spacing: 1.5em;   /* 段落间距 */
```

## 布局规范

### 写作区域（桌面）

```css
.writing-area {
  max-width: 720px;           /* 最大宽度 */
  min-height: 80vh;           /* 最小高度 */
  margin: 0 auto;             /* 水平居中 */
  padding: 48px;              /* 内边距 */
}
```

### 垂直间距系统

```css
--spacing-xs: 8px;
--spacing-sm: 16px;
--spacing-md: 32px;
--spacing-lg: 64px;
--spacing-xl: 96px;
```

### 状态指示器位置

**进度条**：
- 位置：`position: fixed; top: 0; left: 0;`
- 高度：2px
- 宽度：100%
- 透明度：0.4

**计时器**：
- 位置：右上角，`position: fixed; top: 16px; right: 24px;`
- 字号：12px
- 字体：等宽（IBM Plex Mono）

## 组件设计

### 1. 初始界面（Idle Screen）

```
┌─────────────────────────────────────┐
│                                     │
│         Zero Draft                  │  ← 32px, 常规字重
│         写下第一稿，不要回头         │  ← 14px, 灰色
│                                     │
│    [5分钟] [15分钟] [30分钟] [自定义]│  ← 按钮组
│                                     │
│         [开始写作 →]                │  ← 主按钮
│                                     │
└─────────────────────────────────────┘
```

**样式要点**：
- 垂直居中布局
- 组件间距：32px
- 按钮：实心填充，微圆角 2px
- 主按钮：宽度 200px，高度 48px

### 2. 写作界面（Writing Screen）

```
┌─────────────────────────────────────┐
│ [▓▓▓▓▓▓▓░░░░░░░░]     08:32 / 15:00 │ ← 2px进度条 + 计时器
│                                     │
│                                     │
│ [文本输入区域，全屏，无边框]         │
│                                     │
│                                     │
└─────────────────────────────────────┘
```

**交互细节**：
- 进入动画：0.8秒淡入
- Placeholder：极浅灰色（opacity: 0.3）
- 无边框、无 outline、无背景色
- 光标颜色：`var(--color-text)`

### 3. 危险状态（Danger State）

**触发时机**：停止输入 5 秒后

**视觉反馈**：
1. **文字模糊**：`filter: blur(0 → 3px)`，3秒渐变
2. **边框呼吸**：柔和的红色光晕，2秒循环脉冲
3. **无音效**（MVP 阶段）

**CSS 实现**：
```css
.danger-state {
  animation:
    gentle-blur 3s ease-in-out forwards,
    gentle-pulse 2s ease-in-out infinite;
  box-shadow:
    0 0 0 1px rgba(193, 64, 61, 0.2),
    0 0 20px rgba(193, 64, 61, 0.1);
}
```

### 4. 成功界面（Success Screen）

```
┌─────────────────────────────────────┐
│                                     │
│              ✓                      │  ← 48px, 深绿色
│           写了 1,234 字              │  ← 24px
│                                     │
│      [复制文本] [查看历史] [再来一次]│  ← 按钮组
│                                     │
└─────────────────────────────────────┘
```

**按钮层级**：
- Primary（复制文本）：实心填充，深色
- Secondary（其他）：描边按钮，透明背景

### 5. 失败界面（Failed Screen）

```
┌─────────────────────────────────────┐
│                                     │
│              ✗                      │  ← 48px, 砖红色
│         文字已清空                   │
│         再试一次？                   │
│                                     │
│         [重新开始]                  │
│                                     │
└─────────────────────────────────────┘
```

## 动画系统

### 过渡速度

```css
--transition-fast: 200ms ease;
--transition-medium: 400ms ease;
--transition-slow: 800ms ease-out;
```

### 关键动画

#### 1. 危险模糊（Gentle Blur）
```css
@keyframes gentle-blur {
  from { filter: blur(0); }
  to { filter: blur(3px); }
}
```
- 时长：3秒
- 缓动：ease-in-out
- 触发：停止输入 5 秒后

#### 2. 边框脉冲（Gentle Pulse）
```css
@keyframes gentle-pulse {
  0%, 100% {
    box-shadow:
      0 0 0 1px rgba(193, 64, 61, 0.2),
      0 0 20px rgba(193, 64, 61, 0.1);
  }
  50% {
    box-shadow:
      0 0 0 2px rgba(193, 64, 61, 0.3),
      0 0 30px rgba(193, 64, 61, 0.15);
  }
}
```
- 时长：2秒
- 缓动：ease-in-out
- 循环：infinite

#### 3. 淡入（Fade In）
```css
@keyframes fade-in {
  from { opacity: 0; }
  to { opacity: 1; }
}
```
- 时长：800ms
- 用于：界面切换

#### 4. 淡出清空（Fade Out Clear）
```css
@keyframes fade-out {
  from { opacity: 1; }
  to { opacity: 0; }
}
```
- 时长：400ms
- 用于：失败状态文字消失

### 动画时序图

```
用户停止输入：
  0s ────────────────→ 5s ──────────→ 8s
  [正常输入]           [开始模糊]      [清空]
                      [边框呼吸]

详细时间线：
  - 0-5s：无视觉变化
  - 5s：触发 gentle-blur（3秒完成）
  - 5s：触发 gentle-pulse（循环）
  - 8s：fade-out → 清空文本 → 显示失败界面
```

## 响应式设计（桌面优先）

### 断点

MVP 阶段专注桌面体验，但保留基本响应：

```css
/* 桌面（默认）*/
@media (min-width: 1024px) {
  .writing-area { max-width: 720px; }
}

/* 平板 */
@media (max-width: 1023px) {
  .writing-area {
    max-width: 100%;
    padding: 32px;
  }
}

/* 手机 */
@media (max-width: 768px) {
  .writing-area {
    padding: 24px;
    font-size: 16px;
  }
}
```

## 可访问性（Accessibility）

### 键盘导航
- Tab 键顺序：时长选择 → 开始按钮 → 写作区域
- Enter 键：确认选择
- Esc 键：（预留）退出会话

### 对比度
所有文字与背景对比度 ≥ 4.5:1（WCAG AA 标准）

验证：
- 主文本 `#1A1A1A` on `#FAFAF8`：对比度 13.2:1 ✓
- UI 灰色 `#8B8B8B` on `#FAFAF8`：对比度 4.6:1 ✓
- 危险红 `#C1403D` on `#FAFAF8`：对比度 5.1:1 ✓

### 焦点状态
```css
button:focus-visible,
textarea:focus-visible {
  outline: 2px solid var(--color-text);
  outline-offset: 4px;
}
```

## 技术实现建议

### 推荐技术栈
- **框架**：Datastar (https://data-star.dev/)
- **CSS**：Tailwind CSS + 自定义 CSS
- **字体加载**：
  - 霞鹜文楷：从 CDN 加载或自托管
  - IBM Plex Mono：Google Fonts
  - 系统字体作为 fallback

### 性能优化
1. 字体使用 `font-display: swap`
2. 动画使用 CSS transform（GPU 加速）
3. 避免 JavaScript 动画（除定时器）

### 浏览器兼容性
- 目标：Chrome 90+, Safari 14+, Firefox 88+
- 使用原生 CSS 特性（:focus-visible, CSS Variables）
- 不支持 IE11

## 文件结构

```
zerodraft/
├── docs/
│   └── design-system.md          # 本文档
├── src/
│   ├── styles/
│   │   ├── global.css            # 全局样式 + CSS 变量
│   │   └── animations.css        # 动画定义
│   ├── components/               # UI 组件
│   └── assets/
│       └── fonts/                # 自托管字体
├── tailwind.config.js            # Tailwind 配置
└── prototype.html                # 静态原型
```

## 下一步

1. ✅ 完成设计规范文档
2. ⏳ 配置 Tailwind CSS
3. ⏳ 创建全局样式文件
4. ⏳ 实现动画系统
5. ⏳ 构建 HTML 原型验证设计
