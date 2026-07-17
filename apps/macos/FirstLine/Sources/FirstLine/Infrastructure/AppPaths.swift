/**
 * [INPUT]: 依赖 FileManager 提供用户 Application Support 目录
 * [OUTPUT]: 提供 First Line 的 library / recovery / config 路径
 * [POS]: Infrastructure 路径规范层，统一文件落点
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

enum AppPaths {
    private static let rootName = "First Line"

    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(rootName, isDirectory: true)
    }

    static let libraryDirectory = applicationSupportRoot.appendingPathComponent("Library", isDirectory: true)
    static let recoveryDirectory = applicationSupportRoot.appendingPathComponent("Recovery", isDirectory: true)
    static let configDirectory = applicationSupportRoot.appendingPathComponent("Config", isDirectory: true)
}
