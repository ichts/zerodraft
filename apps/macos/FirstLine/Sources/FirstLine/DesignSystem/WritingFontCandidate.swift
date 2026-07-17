/**
 * [INPUT]: 依赖本地 tmp/font-candidates 中的测试字体文件
 * [OUTPUT]: 提供写作编辑器固定中英文字体与本地字体注册
 * [POS]: FirstLine 写作字体层，固定英文 Pitch Light 与中文 Zhuque Fangsong
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppKit
import CoreText
import Foundation

enum WritingFontCandidate: String, CaseIterable, Identifiable, Hashable {
    case pitchLight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pitchLight:
            "Pitch Light"
        }
    }

    @MainActor
    var isAvailable: Bool {
        return font(size: 12) != nil
    }

    @MainActor
    func font(size: CGFloat) -> NSFont? {
        return LocalFontRegistry.font(at: relativePath, size: size)
    }

    @MainActor
    func punctuationFont(size: CGFloat) -> NSFont? {
        font(size: size)
    }

    private var relativePath: String {
        switch self {
        case .pitchLight:
            pitchPath("TestPitch-Light.otf")
        }
    }

    private func pitchPath(_ filename: String) -> String {
        "tmp/font-candidates/english/Klim-Pitch/extracted/Test desktop fonts (Static, OTF)/Test Pitch Collection/Test Pitch/\(filename)"
    }

}

enum ChineseFontCandidate: String, CaseIterable, Identifiable, Hashable {
    case zhuqueFangsong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zhuqueFangsong:
            "Zhuque Fangsong"
        }
    }

    @MainActor
    var isAvailable: Bool {
        return font(size: 12) != nil
    }

    @MainActor
    func font(size: CGFloat) -> NSFont? {
        return LocalFontRegistry.font(at: relativePath, size: size)
    }

    private var relativePath: String {
        switch self {
        case .zhuqueFangsong:
            "tmp/font-candidates/chinese/Zhuque/extracted/ZhuqueFangsong-Regular.ttf"
        }
    }
}

@MainActor
private enum LocalFontRegistry {
    private static var cachedPostScriptNames: [String: String] = [:]

    static func font(at relativePath: String, size: CGFloat) -> NSFont? {
        guard let url = resolveFontURL(relativePath) else { return nil }

        if let postScriptName = cachedPostScriptNames[url.path],
           let font = exactFont(named: postScriptName, size: size) {
            return font
        }

        guard let postScriptName = postScriptName(from: url) else { return nil }
        if let font = exactFont(named: postScriptName, size: size) {
            cachedPostScriptNames[url.path] = postScriptName
            return font
        }

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        guard registered || exactFont(named: postScriptName, size: size) != nil else {
            return nil
        }

        cachedPostScriptNames[url.path] = postScriptName
        return exactFont(named: postScriptName, size: size)
    }

    private static func exactFont(named postScriptName: String, size: CGFloat) -> NSFont? {
        guard let font = NSFont(name: postScriptName, size: size), font.fontName == postScriptName else {
            return nil
        }

        return font
    }

    private static func postScriptName(from url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }

        return CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    }

    private static func resolveFontURL(_ relativePath: String) -> URL? {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let directCandidates = [
            currentDirectory.appendingPathComponent(relativePath),
            currentDirectory.appendingPathComponent("../../../").appendingPathComponent(relativePath),
        ]

        if let url = directCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return url
        }

        var sourceAncestor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = sourceAncestor.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            sourceAncestor.deleteLastPathComponent()
        }

        return nil
    }
}
