import Foundation
import Testing
@testable import FirstLine

struct PersistenceOnlyTests {
    @Test
    @MainActor
    func successfulSessionWritesMarkdownWithFrontMatter() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let service = PersistenceService(fileManager: fileManager, libraryDirectory: libraryDirectory)
        let engine = SessionEngine(now: { 100 })
        engine.start(duration: 300)
        engine.registerCommittedText("hello world")
        let url = try service.saveSuccessfulSession(from: engine)
        let content = try String(contentsOf: url)

        #expect(content.contains("---"))
        #expect(content.contains("duration_seconds: 300"))
        #expect(content.contains("word_count: 2"))
        #expect(content.contains("hello world"))
    }
}
