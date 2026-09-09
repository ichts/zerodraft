import Foundation
import Testing
@testable import FirstLine

struct LibraryPersistenceTests {
    @Test
    @MainActor
    func loadLibraryParsesAndSortsSessions() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        try fm.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory)

        // 旧命名文件（-first-line.md）必须保持可读：改名前的历史库不能丢。
        let older = libraryDirectory.appendingPathComponent("2026-04-20T10-00-00Z-first-line.md")
        let newer = libraryDirectory.appendingPathComponent("2026-04-20T11-00-00Z-zero-draft.md")

        try sampleMarkdown(id: "1", completedAt: "2026-04-20T10:00:00Z", body: "older line").write(to: older, atomically: true, encoding: .utf8)
        try sampleMarkdown(id: "2", completedAt: "2026-04-20T11:00:00Z", body: "newer line").write(to: newer, atomically: true, encoding: .utf8)

        let sessions = try service.loadLibrary()
        #expect(sessions.count == 2)
        #expect(sessions.first?.id == "2")
        #expect(sessions.first?.snippet == "newer line")
    }

    @Test
    func deleteSessionRemovesFile() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        try fm.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory)

        let file = libraryDirectory.appendingPathComponent("delete-me.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(fm.fileExists(atPath: file.path))

        try service.deleteSession(at: file)
        #expect(fm.fileExists(atPath: file.path) == false)
    }

    private func sampleMarkdown(id: String, completedAt: String, body: String) -> String {
        """
        ---
        id: \(id)
        created_at: 2026-04-20T09:55:00Z
        completed_at: \(completedAt)
        duration_seconds: 300
        word_count: 2
        app_version: 0.1.0
        ---

        \(body)
        """
    }
}
