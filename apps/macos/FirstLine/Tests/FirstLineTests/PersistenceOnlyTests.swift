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
    @MainActor
    @Test
    func saveTwiceWithinSameSecondProducesDistinctURLs() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = PersistenceService(fileManager: fm, libraryDirectory: dir)
        let engine = SessionEngine(now: { 0 })
        engine.start(duration: 60)
        engine.registerCommittedText("one")
        let engine2 = SessionEngine(now: { 0 })
        engine2.start(duration: 60)
        engine2.registerCommittedText("two")
        let a = try service.saveSuccessfulSession(from: engine)
        let b = try service.saveSuccessfulSession(from: engine2)
        #expect(a != b)
        #expect(fm.fileExists(atPath: a.path))
        #expect(fm.fileExists(atPath: b.path))
    }

}
