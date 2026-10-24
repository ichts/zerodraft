import AppKit
import Testing
@testable import WriteItDown

/// Cases 1-17 in docs/wid-mac-behavior.md. The editor's real NSTextInputClient
/// entry points are driven in the order an input method sends them; no guard is
/// re-implemented here. Apple Pinyin and WeType share the same NSTextInputClient
/// contract; the input source itself is selected in the signed-build recording.
@MainActor
struct PinyinInputTests {
    // MARK: - Apple Pinyin

    @Test func applePinyinTypeCommitsWithoutDenyOrScroll() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try typeAndCommit(fixture, committed: "你好")
    }

    @Test func applePinyinBackspaceWhileComposingIsNotADeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try backspaceWhileComposing(fixture, committed: "你好")
    }

    @Test func applePinyinSpaceCandidateCommitsWithoutDeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try candidateCommit(fixture, committed: "你好")
    }

    @Test func applePinyinDigitCandidateCommitsWithoutDeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try candidateCommit(fixture, committed: "你")
    }

    @Test func applePinyinEscapeCancelsWithoutDeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try escapeCancels(fixture)
    }

    // MARK: - WeChat WeType

    @Test func weTypeTypeCommitsWithoutDenyOrScroll() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try typeAndCommit(fixture, committed: "你好")
    }

    @Test func weTypeBackspaceWhileComposingIsNotADeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try backspaceWhileComposing(fixture, committed: "你好")
    }

    @Test func weTypeSpaceCandidateCommitsWithoutDeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try candidateCommit(fixture, committed: "你好")
    }

    @Test func weTypeDigitCandidateCommitsWithoutDeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try candidateCommit(fixture, committed: "你")
    }

    @Test func weTypeEscapeCancelsWithoutDeny() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try escapeCancels(fixture)
    }

    // MARK: - The two failure modes, separately

    @Test func committedTextDeletionStillDenies() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try typeAndCommit(fixture, committed: "你好")
        let committed = fixture.editor.string
        fixture.editor.deleteBackward(nil)
        #expect(fixture.engine.lastDenyAt != nil, "committed text must still trigger the deny treatment")
        #expect(fixture.editor.string == committed)
    }

    @Test func clearedMarkedRangeDeletionDenies() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let origin = fixture.origin
        fixture.editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.unmarkText()
        #expect(fixture.editor.string == "ni")
        let denied = fixture.room.textView(fixture.editor,
            doCommandBy: #selector(NSResponder.deleteBackward(_:)))
        #expect(denied)
        #expect(fixture.engine.lastDenyAt != nil, "deletion after the IME cleared its marked range is a user edit")
        #expect(fixture.origin == origin)
        #expect(fixture.editor.string == "ni")
        fixture.editor.insertText("n", replacementRange: NSRange(location: 0, length: 2))
        #expect(fixture.editor.string == "ni", "a stale composition range must not outlive the denied edit")
    }

    @Test func notFoundMarkedReplacementStaysInComposition() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let origin = fixture.origin
        fixture.editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.engine.lastDenyAt == nil)
        #expect(fixture.editor.hasMarkedText())
        #expect(fixture.editor.string == "n", "a .notFound replacement replaces the composition, not the draft")
        #expect(fixture.origin == origin)
    }

    @Test func replaceCharactersDuringCompositionIsAllowed() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.replaceCharacters(in: fixture.editor.markedRange(), with: "n")
        #expect(fixture.engine.lastDenyAt == nil, "marked-text bookkeeping is not a denied user edit")
    }

    @Test func commitAfterUnmarkInsideCompositionIsAllowed() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = fixture.editor.markedRange()
        fixture.editor.unmarkText()
        fixture.editor.insertText("你好", replacementRange: marked)
        #expect(fixture.engine.lastDenyAt == nil, "a commit targeting the composing range is not a deletion")
        #expect(fixture.editor.string == "你好")
        #expect(fixture.engine.text == "你好", "the engine must record the final composition, not the romanization")
        #expect(fixture.engine.wordCount == 2)
    }

    @Test func deniedCommandDuringCompositionKeepsTheCommit() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.editor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = fixture.editor.markedRange()
        #expect(marked.location == 3)

        #expect(fixture.room.textView(fixture.editor, doCommandBy: #selector(NSText.cut(_:))))
        let redirected = fixture.room.textView(fixture.editor,
            willChangeSelectionFromCharacterRange: fixture.editor.selectedRange(),
            toCharacterRange: NSRange(location: marked.location - 1, length: 0))
        #expect(redirected == NSRange(location: NSMaxRange(marked), length: 0))
        #expect(fixture.editor.hasMarkedText(), "a denied edit dropped the live composition")

        fixture.editor.unmarkText()
        fixture.editor.insertText("你好", replacementRange: marked)
        #expect(fixture.editor.string == "abc你好")
        #expect(fixture.engine.text == "abc你好")
    }

    @Test func shuangpinSequenceStaysCompositionSafe() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try typeAndCommit(fixture, committed: "你")
    }

    // MARK: - Sequences

    private func typeAndCommit(_ fixture: Fixture, committed: String) throws {
        let origin = fixture.origin
        for marked in ["n", "ni", "nih"] {
            fixture.editor.setMarkedText(marked,
                                         selectedRange: NSRange(location: (marked as NSString).length, length: 0),
                                         replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(fixture.engine.lastDenyAt == nil)
            #expect(fixture.origin == origin, "composition must not shift the viewport")
        }
        fixture.room.tick()
        #expect(fixture.origin == origin)
        fixture.editor.insertText(committed, replacementRange: fixture.editor.markedRange())
        #expect(fixture.engine.lastDenyAt == nil)
        #expect(fixture.editor.string == committed)
        #expect(fixture.engine.text == committed)
    }

    private func backspaceWhileComposing(_ fixture: Fixture, committed: String) throws {
        let origin = fixture.origin
        fixture.editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.deleteBackward(nil)
        #expect(fixture.engine.lastDenyAt == nil, "backspace while composing must not deny")
        #expect(fixture.origin == origin, "composition must not shift the viewport")
        fixture.room.tick()
        #expect(fixture.origin == origin)
        let replacement = NSRange(location: 0, length: (fixture.editor.string as NSString).length)
        fixture.editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                     replacementRange: replacement)
        fixture.editor.insertText(committed, replacementRange: fixture.editor.markedRange())
        #expect(fixture.engine.lastDenyAt == nil)
        #expect(fixture.editor.string == committed)
    }

    private func candidateCommit(_ fixture: Fixture, committed: String) throws {
        fixture.editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        let origin = fixture.origin
        #expect(fixture.origin == origin, "the composition itself must not shift the viewport")
        fixture.editor.insertText(committed, replacementRange: fixture.editor.markedRange())
        #expect(fixture.engine.lastDenyAt == nil, "candidate pick must not deny")
        #expect(fixture.editor.string == committed)
        #expect(fixture.engine.text == committed)
    }

    private func escapeCancels(_ fixture: Fixture) throws {
        fixture.editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
        let origin = fixture.origin
        fixture.editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
                                     replacementRange: fixture.editor.markedRange())
        fixture.editor.unmarkText()
        #expect(fixture.engine.lastDenyAt == nil, "Escape in the candidate window must not deny")
        #expect(fixture.editor.string.isEmpty)
        #expect(fixture.origin == origin)
    }

    // MARK: - Fixture

    @MainActor
    private final class Fixture {
        let room: SessionViewController
        let engine: SessionEngine
        let editor: AppendOnlyTextView
        let scrollView: NSScrollView
        let window: NSWindow

        init(room: SessionViewController, engine: SessionEngine,
             editor: AppendOnlyTextView, scrollView: NSScrollView, window: NSWindow) {
            self.room = room
            self.engine = engine
            self.editor = editor
            self.scrollView = scrollView
            self.window = window
        }

        var origin: NSPoint { scrollView.contentView.bounds.origin }

        func close() {
            room.viewWillDisappear()
            window.orderOut(nil)
        }
    }

    private final class Clock {
        var now: TimeInterval = 0
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = Clock()
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = room
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.makeKeyAndOrderFront(nil)
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.viewDidAppear()
        room.view.layoutSubtreeIfNeeded()
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let scrollView = try #require(editor.enclosingScrollView)
        return Fixture(room: room, engine: engine, editor: editor, scrollView: scrollView, window: window)
    }

    private func descendants<T: NSView>(of view: NSView, of type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, of: type)
        }
    }
}
