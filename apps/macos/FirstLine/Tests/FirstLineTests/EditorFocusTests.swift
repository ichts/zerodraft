import AppKit
import Testing
@testable import FirstLine

@MainActor
struct EditorFocusTests {
    @Test
    func focusTypographyBlursPreviousParagraphAndKeepsCurrentClear() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "old thought\ncurrent thought"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        try #require(storage.length > 0)
        #expect(storage.attribute(.shadow, at: 0, effectiveRange: nil) is NSShadow)
        #expect(storage.attribute(.shadow, at: textView.string.count - 1, effectiveRange: nil) == nil)
    }

    @Test
    func focusTypographyBlursPreviousParagraphAfterNewline() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "old thought\n"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        try #require(storage.length > 0)
        #expect(storage.attribute(.shadow, at: 0, effectiveRange: nil) is NSShadow)
    }

    @Test
    func focusTypographyHidesEverythingBeforePreviousParagraph() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "first\nsecond\ncurrent"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        let firstColor = try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(firstColor.alphaComponent == 0)
        #expect(storage.attribute(.shadow, at: 6, effectiveRange: nil) is NSShadow)
        #expect(storage.attribute(.shadow, at: textView.string.count - 1, effectiveRange: nil) == nil)
    }

    @Test
    func focusTypographyAfterNewlineShowsOnlyPreviousParagraph() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "first\nsecond\n"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        let firstColor = try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(firstColor.alphaComponent == 0)
        #expect(storage.attribute(.shadow, at: 6, effectiveRange: nil) is NSShadow)
    }

    @Test
    func punctuationCharactersUsePitchLightAtSmallerSize() throws {
        guard WritingFontCandidate.pitchLight.isAvailable else {
            return
        }

        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "hello, world."))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        let wordFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let commaFont = try #require(storage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        let periodFont = try #require(storage.attribute(.font, at: 12, effectiveRange: nil) as? NSFont)
        let wordColor = try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let commaColor = try #require(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor)

        #expect(commaFont.fontName == wordFont.fontName)
        #expect(commaFont.fontName == periodFont.fontName)
        #expect(commaFont.fontName.localizedCaseInsensitiveContains("Newsreader"))
        #expect(commaFont.pointSize < wordFont.pointSize)
        #expect(commaColor.alphaComponent == wordColor.alphaComponent)
    }

    @Test
    func zhuqueFontIsAppliedAsCJKFallback() throws {
        guard ChineseFontCandidate.zhuqueFangsong.isAvailable else {
            return
        }

        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "我们 write."))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        if font.fontName == "ZhuqueFangsong-Regular" {
            return
        }

        let cascadeList = try #require(font.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor])
        let firstFallback = try #require(cascadeList.first)
        #expect(firstFallback.postscriptName == "ZhuqueFangsong-Regular")
    }

    @Test
    func markedPinyinCaretAlignsToLatinGlyphBounds() throws {
        guard WritingFontCandidate.pitchLight.isAvailable else {
            return
        }

        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "我们是共产"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.setMarkedText(
            "zhu'yi",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(textView.hasMarkedText())

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            Issue.record("Missing TextKit layout objects")
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: max(textView.selectedRange().location - 1, 0))
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        let defaultCaretY = lineRect.minY + (lineRect.height - 28) / 2
        
        let adjusted = textView.adjustedCaretRectForCurrentInsertionPoint(
            from: NSRect(x: lineRect.maxX, y: lineRect.minY, width: 2, height: lineRect.height)
        )

        #expect(adjusted.minY > defaultCaretY)
        #expect(adjusted.height >= 26)
        #expect(adjusted.height <= 30)
    }

    @Test
    func markedPinyinCaretStaysOnCurrentLineAfterNewline() throws {
        guard WritingFontCandidate.pitchLight.isAvailable else {
            return
        }

        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "第一行\n第二行"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.setMarkedText(
            "zhuyi",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            Issue.record("Missing TextKit layout objects")
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: max(textView.selectedRange().location - 1, 0))
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        let firstLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: 0,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        let adjusted = textView.adjustedCaretRectForCurrentInsertionPoint(
            from: NSRect(x: lineRect.maxX, y: lineRect.minY, width: 2, height: lineRect.height)
        )

        #expect(adjusted.midY > firstLineRect.maxY)
    }

    @Test
    func committedLatinCaretAfterChineseKeepsReadableHeight() throws {
        guard WritingFontCandidate.pitchLight.isAvailable else {
            return
        }

        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "爱人民xianyan"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.applyFocusTypographyToExistingText()

        let adjusted = try caretRect(for: textView)

        #expect(adjusted.height >= 26)
        #expect(adjusted.height <= 30)
    }

    @Test
    func committedSpaceCaretAfterChineseKeepsReadableHeight() throws {
        guard WritingFontCandidate.pitchLight.isAvailable else {
            return
        }

        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "爱人民 "))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.applyFocusTypographyToExistingText()

        let adjusted = try caretRect(for: textView)

        #expect(adjusted.height >= 26)
        #expect(adjusted.height <= 30)
    }

    @Test
    func caretAfterTrailingNewlineMovesToEmptyNextLine() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "集成革命\n"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.applyFocusTypographyToExistingText()

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            Issue.record("Missing TextKit layout objects")
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let previousGlyphIndex = layoutManager.glyphIndexForCharacter(at: max(textView.string.count - 2, 0))
        let previousLine = layoutManager.lineFragmentRect(
            forGlyphAt: previousGlyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        let extraLine = layoutManager.extraLineFragmentRect
        let adjusted = textView.adjustedCaretRectForCurrentInsertionPoint(
            from: NSRect(x: extraLine.maxX, y: extraLine.minY, width: 2, height: extraLine.height)
        )

        #expect(adjusted.midY > previousLine.maxY)
        #expect(adjusted.midY > extraLine.minY)
        #expect(adjusted.height >= 26)
        #expect(adjusted.height <= 30)
    }

    @Test
    func mixedChineseLatinBoundaryUsesKerningWithoutInsertedSpace() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "爱人民xianyan"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        let boundaryKern = storage.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat

        #expect(textView.string == "爱人民xianyan")
        if let boundaryKern {
            #expect(boundaryKern > -2)
        }
    }

    @Test
    func explicitSpaceBetweenLatinAndChineseIsVisuallyCompressed() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "飘扬在qianxiong 不怕"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applyFocusTypographyToExistingText()

        let storage = try #require(textView.textStorage)
        let boundaryKern = try #require(storage.attribute(.kern, at: 11, effectiveRange: nil) as? CGFloat)

        #expect(textView.string == "飘扬在qianxiong 不怕")
        #expect(boundaryKern < 0)
    }

    @Test
    func markedPinyinKeepsExistingChineseBaselineStable() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "一个"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.applyFocusTypographyToExistingText()

        let before = try glyphBaselineY(in: textView, characterIndex: 0)
        textView.setMarkedText(
            "r",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let after = try glyphBaselineY(in: textView, characterIndex: 0)

        #expect(abs(before - after) < 0.5)
    }

    @Test
    func blockedEditingCommandsAreNotValidated() {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))

        let blockedSelectors: [Selector] = [
            #selector(NSResponder.deleteWordBackward(_:)),
            #selector(NSResponder.deleteWordForward(_:)),
            #selector(NSResponder.deleteToBeginningOfLine(_:)),
            #selector(NSResponder.deleteToEndOfLine(_:)),
            #selector(NSResponder.deleteToBeginningOfParagraph(_:)),
            #selector(NSResponder.deleteToEndOfParagraph(_:)),
            #selector(NSResponder.yank(_:)),
            #selector(NSResponder.transpose(_:)),
            #selector(NSResponder.deleteBackward(_:)),
            #selector(NSResponder.deleteForward(_:)),
            #selector(UndoManager.undo),
            Selector(("redo:")),
            #selector(NSText.cut(_:)),
            #selector(NSText.paste(_:)),
        ]

        for selector in blockedSelectors {
            let item = NSMenuItem(title: "test", action: selector, keyEquivalent: "")
            #expect(textView.validateUserInterfaceItem(item) == false,
                    "Expected \(NSStringFromSelector(selector)) to be blocked")
        }
    }

    @Test
    func deleteBackwardWithoutMarkedTextDeniesViaClosure() {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        #expect(textView.hasMarkedText() == false)

        var denied = false
        textView.onDeny = { denied = true }
        textView.deleteBackward(nil)

        #expect(denied)
    }

    @Test
    func deleteBackwardDuringCompositionDoesNotDeny() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.setMarkedText(
            "abc",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        try #require(textView.hasMarkedText())

        var denied = false
        textView.onDeny = { denied = true }
        textView.deleteBackward(nil)

        #expect(denied == false)
    }

    @Test
    func readSelectionFromPasteboardRefusesAndDenies() {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var denied = false
        textView.onDeny = { denied = true }

        let pboard = NSPasteboard(name: NSPasteboard.Name("fl-editor-test"))
        let accepted = textView.readSelection(from: pboard)

        #expect(accepted == false)
        #expect(denied)
    }

    // MARK: - UTF-16 offsets (Fix 2)

    @Test
    func selectionRedirectUsesUTF16LengthForFlagEmoji() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        // 🇯🇵 is one grapheme but four UTF-16 code units; "🇯🇵hi" = 6 UTF-16, 3 graphemes.
        textView.textStorage?.setAttributedString(NSAttributedString(string: "🇯🇵hi"))
        let engine = SessionEngine()

        // 守卫判定已抽到 AppendOnlyInputPolicy；重定向时 SessionViewController 的 delegate 会 registerDeny。
        let redirected = AppendOnlyInputPolicy.redirectedSelection(
            proposed: NSRange(location: 1, length: 0),
            fullLength: (textView.string as NSString).length,
            hasMarkedText: textView.hasMarkedText()
        )
        if redirected != nil { engine.registerDeny() }

        let utf16End = (textView.string as NSString).length
        #expect(utf16End == 6)
        #expect(utf16End != textView.string.count)
        #expect(redirected?.location == utf16End)
        #expect(redirected?.length == 0)
        #expect(engine.lastDenyAt != nil)
    }

    @Test
    func selectionRedirectKeepsCaretAtUTF16EndForFamilyEmoji() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        // 👨‍👩‍👧‍👦 is one grapheme (eleven UTF-16 units); the caret-at-end must land past it.
        textView.textStorage?.setAttributedString(NSAttributedString(string: "a👨‍👩‍👧‍👦b"))
        let engine = SessionEngine()

        let utf16End = (textView.string as NSString).length
        #expect(utf16End == 13)
        #expect(textView.string.count == 3)

        let redirected = AppendOnlyInputPolicy.redirectedSelection(
            proposed: NSRange(location: 2, length: 0),
            fullLength: (textView.string as NSString).length,
            hasMarkedText: textView.hasMarkedText()
        )
        if redirected != nil { engine.registerDeny() }

        #expect(redirected?.location == utf16End)
    }

    @Test
    func markedTextCommitAfterNonBMPContentKeepsCaretInUTF16Space() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        // Preload non-BMP content: 🇯🇵 and 🇺🇸 are each 4 UTF-16 code units.
        textView.textStorage?.setAttributedString(NSAttributedString(string: "flags 🇯🇵🇺🇸"))
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

        // Simulate a real IME composition + commit at the end.
        textView.setMarkedText(
            "x",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(textView.hasMarkedText())

        var committed: String?
        textView.onCommittedText = { committed = $0 }
        textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(textView.hasMarkedText() == false)
        #expect(committed == "x")
        // Caret lands at UTF-16 end, not grapheme-count end.
        let utf16End = (textView.string as NSString).length
        #expect(textView.selectedRange().location == utf16End)
        #expect(utf16End != textView.string.count)
    }

    @Test
    func insertTextAppendsEmojiWithoutFalseDeny() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "before"))
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

        var committed: String?
        var denied = false
        textView.onCommittedText = { committed = $0 }
        textView.onDeny = { denied = true }

        // insertText at the end via the default NSNotFound range (non-marked-commit path).
        // Internally TextKit calls replaceCharacters, which must NOT fire a false deny
        // because isPerformingInsertion guards the append.
        textView.insertText("😀", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(textView.string == "before😀")
        #expect(committed == "😀")
        #expect(denied == false)
    }

    @Test
    func imeCompositionAndCommitAppendsCommittedText() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()

        var markedActivity = 0
        var committed: String?
        textView.onMarkedTextActivity = { markedActivity += 1 }
        textView.onCommittedText = { committed = $0 }

        // IME composition phase.
        textView.setMarkedText(
            "ni'hao",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(textView.hasMarkedText())
        #expect(markedActivity == 1)

        // Commit: the marked text is replaced by the committed candidate.
        textView.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(textView.hasMarkedText() == false)
        #expect(committed == "你好")
        #expect(textView.string == "你好")
    }

    @Test
    func directReplaceCharactersOutsideInsertTextDeniesAndBlocks() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "some text"))

        var denied = false
        textView.onDeny = { denied = true }

        // Direct replaceCharacters NOT routed through insertText: isPerformingInsertion
        // is false, so the guard denies and blocks the mutation.
        textView.replaceCharacters(in: NSRange(location: 0, length: 4), with: "other")

        #expect(denied)
        #expect(textView.string == "some text")
    }

    @Test
    func dragSelectionDenies() {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var denied = false
        textView.onDeny = { denied = true }

        let allowed = textView.dragSelection(
            with: NSEvent(),
            offset: NSSize(width: 10, height: 0),
            slideBack: true
        )

        #expect(allowed == false)
        #expect(denied)
    }

    @Test
    func pasteAndCutRouteThroughDeny() {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var denied = 0
        textView.onDeny = { denied += 1 }

        textView.paste(nil)
        textView.cut(nil)

        #expect(denied == 2)
    }

    @Test
    func blockedCommandSelectorsDenyViaEngine() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "some words"))
        let engine = SessionEngine()
        engine.start(duration: 60)
        engine.registerCommittedText("x")

        let before = engine.lastDenyAt
        #expect(before == nil)

        // 守卫判定已抽到 AppendOnlyInputPolicy；deny 时 SessionViewController 的 delegate 会 registerDeny。
        let blocked = AppendOnlyInputPolicy.shouldDenyCommand(
            #selector(UndoManager.undo),
            hasMarkedText: textView.hasMarkedText()
        )
        #expect(blocked)
        if blocked { engine.registerDeny() }
        #expect(engine.lastDenyAt != nil)
    }

    private func caretRect(for textView: AppendOnlyTextView) throws -> NSRect {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            Issue.record("Missing TextKit layout objects")
            return .zero
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: max(textView.selectedRange().location - 1, 0))
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        return textView.adjustedCaretRectForCurrentInsertionPoint(
            from: NSRect(x: lineRect.maxX, y: lineRect.minY, width: 2, height: lineRect.height)
        )
    }

    private func glyphBaselineY(in textView: AppendOnlyTextView, characterIndex: Int) throws -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            Issue.record("Missing TextKit layout objects")
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        return lineRect.minY + layoutManager.location(forGlyphAt: glyphIndex).y
    }
}
