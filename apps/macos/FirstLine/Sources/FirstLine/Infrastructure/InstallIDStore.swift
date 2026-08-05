/**
 * [INPUT]: 依赖 AppPaths.configDirectory 与 FileManager
 * [OUTPUT]: InstallIDStore + InstallID，生成并持久化稳定的本机 install UUID
 * [POS]: Infrastructure 身份层；给 Dodo `/licenses/activate` 提供非侵入式的 instance 标识
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 *
 * 设计取舍：
 * - 不使用硬件序列号 / IOPlatformUUID 等侵入式设备指纹。
 * - 仅在 Application Support 内保存一个随机 UUID；用户清掉目录就视为新设备。
 * - 这对 Dodo 的 2-Mac 限制足够，且不收集可识别个人信息。
 */

import Foundation

struct InstallID: Codable, Equatable, Sendable {
    /// 稳定的随机标识，例如 "abcd1234-eff5-6789-abcd-1234567890ab"。
    let uuid: UUID
    /// 首次生成时间，仅记录用途。
    let createdAt: Date

    /// 返回 "First Line Mac abcd1234" 形式的短名，用作 Dodo activate 的 `name` 字段。
    var shortName: String {
        let short = String(uuid.uuidString.prefix(8))
        return "First Line Mac \(short)"
    }
}

struct InstallIDStore {
    private let fileManager: FileManager
    private let configDirectory: URL
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        configDirectory: URL = AppPaths.configDirectory,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.configDirectory = configDirectory
        self.now = now
    }

    private var installIDFileURL: URL {
        configDirectory.appendingPathComponent("install-id.json")
    }

    /// 读已有的 install-id.json；不存在则生成新的并落盘。
    /// 不会抛错给调用方：失败时回退到内存 UUID，保证 app 仍能启动。
    func loadOrCreate() -> InstallID {
        if let existing = try? load() {
            return existing
        }
        let fresh = InstallID(uuid: UUID(), createdAt: now())
        try? persist(fresh)
        return fresh
    }

    private func load() throws -> InstallID {
        guard fileManager.fileExists(atPath: installIDFileURL.path) else {
            throw NSError(domain: "InstallIDStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "not found"])
        }
        let data = try Data(contentsOf: installIDFileURL)
        return try JSONDecoder().decode(InstallID.self, from: data)
    }

    private func persist(_ id: InstallID) throws {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(id)
        try data.write(to: installIDFileURL, options: .atomic)
    }
}
