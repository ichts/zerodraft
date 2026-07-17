/**
 * [INPUT]: 依赖 SessionEngine、AppPaths 和 markdown 文件
 * [OUTPUT]: 提供成功 session 的保存、读取、删除能力
 * [POS]: Infrastructure 持久化层，负责 library markdown 文件的完整生命周期
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

struct LibrarySession: Identifiable, Equatable {
    let id: String
    let fileURL: URL
    let createdAt: Date
    let completedAt: Date
    let durationSeconds: Int
    let wordCount: Int
    let appVersion: String
    let snippet: String
    let body: String
}

struct PersistenceService {
    private let fileManager: FileManager
    private let appVersion: String
    private let libraryDirectory: URL

    init(
        fileManager: FileManager = .default,
        appVersion: String = "0.1.0",
        libraryDirectory: URL = AppPaths.libraryDirectory
    ) {
        self.fileManager = fileManager
        self.appVersion = appVersion
        self.libraryDirectory = libraryDirectory
    }

    private var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    @MainActor
    func saveSuccessfulSession(from engine: SessionEngine) throws -> URL {
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let completedAt = Date()
        let createdAt = completedAt.addingTimeInterval(-engine.elapsed)
        let formatter = formatter
        let timestamp = formatter.string(from: completedAt).replacingOccurrences(of: ":", with: "-")
        let fileURL = libraryDirectory.appendingPathComponent("\(timestamp)-first-line.md")

        let frontMatter = """
        ---
        id: \(UUID().uuidString)
        created_at: \(formatter.string(from: createdAt))
        completed_at: \(formatter.string(from: completedAt))
        duration_seconds: \(Int(engine.duration))
        word_count: \(engine.wordCount)
        app_version: \(appVersion)
        ---

        \(engine.text)
        """

        try frontMatter.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func loadLibrary() throws -> [LibrarySession] {
        guard fileManager.fileExists(atPath: libraryDirectory.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }

        let sessions = try files.map(loadSession)
        return sessions.sorted { $0.completedAt > $1.completedAt }
    }

    func loadSession(from url: URL) throws -> LibrarySession {
        let content = try String(contentsOf: url, encoding: .utf8)
        let parts = content.components(separatedBy: "---\n")
        guard parts.count >= 3 else {
            throw NSError(domain: "PersistenceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid front matter"])
        }

        let metadata = parts[1]
        let body = parts[2...].joined(separator: "---\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var values: [String: String] = [:]
        for rawLine in metadata.split(separator: "\n") {
            let pieces = rawLine.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            values[pieces[0].trimmingCharacters(in: .whitespaces)] = pieces[1].trimmingCharacters(in: .whitespaces)
        }

        guard
            let id = values["id"],
            let createdAtString = values["created_at"],
            let completedAtString = values["completed_at"],
            let duration = values["duration_seconds"].flatMap(Int.init),
            let wordCount = values["word_count"].flatMap(Int.init),
            let appVersion = values["app_version"],
            let createdAt = formatter.date(from: createdAtString),
            let completedAt = formatter.date(from: completedAtString)
        else {
            throw NSError(domain: "PersistenceService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing front matter fields"])
        }

        let firstLine = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let snippet = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : firstLine.trimmingCharacters(in: .whitespacesAndNewlines)

        return LibrarySession(
            id: id,
            fileURL: url,
            createdAt: createdAt,
            completedAt: completedAt,
            durationSeconds: duration,
            wordCount: wordCount,
            appVersion: appVersion,
            snippet: snippet,
            body: body
        )
    }

    func deleteSession(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
