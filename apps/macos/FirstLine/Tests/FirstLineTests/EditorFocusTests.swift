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
