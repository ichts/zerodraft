# Flutter 开发模式约束

AI 在写 Flutter 相关代码时加载此文件。

## 架构原则

- **薄客户端**: UI 仅负责展示数据和用户交互，所有业务逻辑、数据处理、状态管理均在后端或通过 Riverpod 集中处理。
- **分层**: 推荐 `feature/data/provider/presentation` 或类似清晰分层，避免 God Object。
- **单一真相源**: 每个状态只由一个 Provider 管理，避免数据不一致。

## UI/UX 规范

- **设计指南**: 遵循 Material Design (Android) 或 Cupertino Design (iOS) 规范。
- **响应式**: 使用 `MediaQuery` 或 `LayoutBuilder` 处理不同屏幕尺寸和方向。
- **动画**: 简洁、流畅优先，避免过度复杂的动画，尊重 `prefers-reduced-motion`。

## 依赖管理

- **pubspec.yaml**: 严格锁定依赖版本，避免使用 `any`。
- **核心库**:
    - `flutter_secure_storage`: 用于敏感数据（如 token）的安全存储。
    - `dio`: 强大的 HTTP 客户端，支持拦截器。
    - `riverpod`: 推荐的状态管理方案。
    - `json_serializable` + `build_runner`: 数据模型序列化/反序列化。

## 代码规范

- **格式化**: 强制执行 `dart format`。
- **函数**: 短小精悍，单一职责，不超过 20 行。
- **缩进**: 避免深层嵌套，不超过 3 层。
- **命名**: 清晰、直白，符合 Dart 规范。

## 测试策略

- **单元测试**: 覆盖业务逻辑、数据处理。
- **Widget 测试**: 验证 UI 组件的渲染和交互。
- **集成测试**: 模拟用户流程，验证端到端功能。
- **覆盖率**: 设定合理的测试覆盖率目标。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
