# Flutter 网络请求模式约束

AI 在写 Flutter 网络相关代码时加载此文件。

## HTTP 客户端

- **推荐**: `Dio`。功能强大，支持拦截器、请求取消、文件上传/下载。
- **配置**:
    - `BaseOptions`: 统一设置 `baseUrl`, `connectTimeout`, `receiveTimeout`。
    - 避免在每个请求中重复配置。

## 拦截器 (Interceptors)

- **认证拦截器 (AuthInterceptor)**:
    - 自动为请求添加 `Authorization` header (e.g., Bearer Token)。
    - 处理 Token 过期刷新逻辑。
- **错误拦截器 (ErrorInterceptor)**:
    - 统一处理 HTTP 状态码 (401, 403, 404, 500 等)。
    - 统一处理网络异常 (无网络连接、超时)。
    - 转换为应用层友好的错误类型 (e.g., `AppException`)。
- **日志拦截器 (LogInterceptor)**:
    - 仅在开发/调试环境启用，记录请求/响应详情。
    - 生产环境禁用，避免敏感信息泄露和性能开销。

## 数据模型

- **序列化/反序列化**: 使用 `json_serializable` + `build_runner` 自动生成 `fromJson`/`toJson` 方法。
- **不可变性**: 推荐使用 `freezed` 或 `equatable` 创建不可变数据模型，提高数据一致性。

## API 服务封装

- **模块化**: 每个功能模块或业务领域对应一个 `ApiService` 类。
- **返回类型**: 统一使用 `Either<Failure, Success>` 或 `Result` 类型封装 API 响应，明确区分成功数据和错误信息。
- **Repository 模式**: 在 `data` 层实现 `Repository` 接口，封装数据源（API, 缓存等）的细节。

## 安全实践

- **敏感数据**: 敏感信息（如 API Key, Token）绝不能硬编码。
- **存储**: 使用 `flutter_secure_storage` 安全存储用户凭证和 Token。
- **HTTPS**: 强制所有网络请求使用 HTTPS。

[PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
