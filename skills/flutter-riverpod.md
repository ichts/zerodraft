# Flutter Riverpod 状态管理模式约束

AI 在写 Flutter Riverpod 相关代码时加载此文件。

## 基本概念

- **Provider**: 声明式地定义和访问状态。
- **Provider 类型**:
    - `Provider`: 简单值或对象。
    - `StateProvider`: 可变状态，适用于简单 UI 状态。
    - `StateNotifierProvider`: 复杂状态逻辑，推荐用于业务状态。
    - `FutureProvider`: 异步操作结果 (Future)。
    - `StreamProvider`: 异步数据流 (Stream)。
- **Widget 交互**:
    - `ConsumerWidget`: 推荐，只在需要 `ref` 时使用。
    - `ConsumerStatefulWidget`: 适用于需要 `State` 生命周期和 `ref` 的场景。
    - `ref.watch`: 监听 Provider 变化并重建 Widget。
    - `ref.read`: 一次性读取 Provider 值，不监听。
    - `ref.listen`: 监听 Provider 变化并执行副作用 (e.g., 导航、显示 SnackBar)。

## Provider 组织与优化

- **模块化**: 按功能或领域组织 Provider，提高可维护性。
- **autoDispose**: 默认使用 `autoDispose` 优化资源，Provider 不再被监听时自动销毁。
- **family**: 使用 `family` 修饰符处理需要动态参数的 Provider。
- **keepAlive**: 仅在需要全局持久化状态时使用 `keepAlive`。

## 状态管理模式

- **StateNotifier + State**:
    - 推荐用于管理复杂的业务逻辑和状态。
    - `StateNotifier` 负责业务逻辑，`State` 类表示不可变状态。
    - 状态更新通过创建新的 `State` 实例实现。
- **AsyncValue**:
    - `FutureProvider` 和 `StreamProvider` 自动返回 `AsyncValue<T>`。
    - 统一处理异步状态的 `loading`, `error`, `data` 状态，简化 UI 逻辑。

## 测试

- **ProviderContainer**: 使用 `ProviderContainer` 进行 Provider 的单元测试。
- **override**: 利用 `override` 机制模拟依赖，隔离测试范围。

## 最佳实践

- **UI 职责**: UI 层只负责展示和用户交互，不包含业务逻辑。
- **单一职责**: Provider 应该只关注一个特定的状态或业务逻辑。
- **避免全局 ref.read**: 优先使用 `ref.watch` 或 `ref.listen`，避免在 Widget 的 `build` 方法中滥用 `ref.read`。
- **不可变状态**: 始终创建新的状态实例来更新 `StateNotifier` 的状态，而不是直接修改现有状态。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
