/**
 * [INPUT]: 依赖 FileManager 提供用户 Application Support 目录
 * [OUTPUT]: 提供 writeitdown 的 config 路径；写作文本没有磁盘路径
 * [POS]: Infrastructure 路径规范层，统一文件落点
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation

enum AppPaths {
    private static let rootName = "WriteItDown"

    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(rootName, isDirectory: true)
    }

    static let configDirectory = applicationSupportRoot.appendingPathComponent("Config", isDirectory: true)
}
