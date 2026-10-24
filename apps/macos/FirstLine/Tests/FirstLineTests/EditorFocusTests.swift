import AppKit
import CoreText
import Testing
@testable import WriteItDown

@MainActor
struct EditorFocusTests {
    @Test(arguments: [WritingAlignment.centered, .left], [false, true])
    func currentLineSitsAtTheSheetAnchorAndIsCentered(alignment: WritingAlignment, focus: Bool) throws {
        for size in [NSSize(width: 1040, height: 720), NSSize(width: 1440, height: 900)] {
            try checkWritingLine(alignment: alignment, focus: focus, size: size)
        }
    }

    private func checkWritingLine(alignment: WritingAlignment, focus: Bool, size: NSSize) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root))
        state.settings.writingAlignment = alignment
        state.settings.focusMode = focus
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = room
        window.setContentSize(size)
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.view.layoutSubtreeIfNeeded()
        RoomWindowKeeper.windows.append(window)

        let editor = try #require(descendants(of: room.view, as: AppendOnlyTextView.self).first)
        let scroll = try #require(editor.enclosingScrollView)
        let paper = try #require(scroll.superview)
        let placeholder = try #require(descendants(of: room.view, as: NSTextField.self)
            .first(where: { $0.stringValue == "Start typing." }))
        let lineHeight = CGFloat(WritingFontSize.medium.points) * 1.6
        let container = try #require(editor.textContainer)
        // The centred column is the view width minus both insets. A frame reassignment
        // must not reset the container to the full view width: that drew the writing
        // line one inset to the right (8 pt at 1040, 314 pt at full screen).
        func expectColumnWidth() {
            let usable = editor.bounds.width - 2 * editor.textContainerInset.width
            #expect(abs(container.containerSize.width - usable) <= 1,
                    "writing column is \(container.containerSize.width), expected \(usable) at \(size)")
        }
        expectColumnWidth()

        // Empty sheet: the writing line sits at 39% of the sheet, and the placeholder
        // shares that line's centre and baseline (not its own centred box).
        let emptyY = try currentLineTop(in: editor, paper: paper)
        #expect(abs(emptyY / paper.bounds.height - 0.39) < 0.01)
        let placeholderX = paper.convert(NSPoint(x: placeholder.bounds.midX, y: 0), from: placeholder).x
        #expect(abs(placeholderX - paper.bounds.midX) <= 1)
        // NSTextField is flipped, so its baseline is firstBaselineOffsetFromTop from
        // the field's top (y = 0 in its own coordinates).
        let placeholderBaseline = topInPaper(placeholder.firstBaselineOffsetFromTop,
                                             of: placeholder, paper: paper)
        let emptyBaseline = topInPaper(try #require(editor.currentInsertionBaseline()), of: editor, paper: paper)
        #expect(abs(placeholderBaseline - emptyBaseline) <= 1)
        #expect(!placeholder.isHidden)
        #expect(editor.alignment == .center)

        // One line: the typed line keeps that anchor and the same baseline.
        editor.insertText("One", replacementRange: NSRange(location: NSNotFound, length: 0))
        room.viewDidLayout()
        room.refreshRoom()
        expectColumnWidth()
        let firstY = try currentLineTop(in: editor, paper: paper)
        #expect(abs(firstY / paper.bounds.height - 0.39) < 0.01)
        let firstBaseline = topInPaper(try #require(editor.currentInsertionBaseline()), of: editor, paper: paper)
        #expect(abs(firstBaseline - placeholderBaseline) <= 1)
        #expect(placeholder.isHidden)
        let firstLineX = try lineCentreX(in: editor, paper: paper)
        #expect(abs(firstLineX - paper.bounds.midX) <= 2)

        // Zen: adding a line keeps the current line at the anchor and moves the first line up one line.
        let firstLineTopBefore = try firstLineTop(in: editor, paper: paper)
        editor.insertText("\nTwo", replacementRange: NSRange(location: NSNotFound, length: 0))
        room.viewDidLayout()
        #expect(abs(try currentLineTop(in: editor, paper: paper) - firstY) <= 2)
        let firstLineTopAfter = try firstLineTop(in: editor, paper: paper)
        #expect(abs((firstLineTopBefore - firstLineTopAfter) - lineHeight) <= 2)

        // A long draft keeps the current line at the anchor; earlier lines leave the top of the sheet.
        editor.insertText("\nThree\nFour\nFive\nSix\nSeven\nEight\nNine\nTen",
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        room.viewDidLayout()
        #expect(abs(try currentLineTop(in: editor, paper: paper) - firstY) <= 2)
        #expect(try firstLineTop(in: editor, paper: paper) < 0)
        #expect(abs(try lineCentreX(in: editor, paper: paper) - paper.bounds.midX) <= 2)
    }

    @Test(arguments: [NSSize(width: 1040, height: 720), NSSize(width: 1600, height: 1000)])
    func drawnWritingLineStaysCentredInWideWindows(size: NSSize) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root))
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = room
        window.setContentSize(size)
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.view.layoutSubtreeIfNeeded()
        RoomWindowKeeper.windows.append(window)

        let editor = try #require(descendants(of: room.view, as: AppendOnlyTextView.self).first)
        let paper = try #require(editor.enclosingScrollView?.superview)
        editor.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
        room.viewDidLayout()
        room.refreshRoom()
        room.view.layoutSubtreeIfNeeded()
        room.view.displayIfNeeded()

        // Render the real view hierarchy: layout numbers alone missed the old bug
        // where the drawn column sat one inset to the right of the sheet centre.
        let rep = try #require(room.view.bitmapImageRepForCachingDisplay(in: room.view.bounds))
        room.view.cacheDisplay(in: room.view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / room.view.bounds.width
        let lineCentreFromPaperTop = try currentLineTop(in: editor, paper: paper)
        let paperTopFromRoomTop = room.view.bounds.height - paper.frame.maxY
        let y0 = Int((paperTopFromRoomTop + lineCentreFromPaperTop - 30) * scale)
        let y1 = Int((paperTopFromRoomTop + lineCentreFromPaperTop + 30) * scale)
        var minX = Int.max, maxX = Int.min
        for y in max(y0, 0)..<min(y1, rep.pixelsHigh) {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), colour.alphaComponent > 0.4 else { continue }
                let luma = 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
                if luma < 0.5 { minX = min(minX, x); maxX = max(maxX, x) }
            }
        }
        #expect(minX < maxX, "no writing ink rendered at \(size)")
        let centre = CGFloat(minX + maxX) / 2 / scale
        #expect(abs(centre - room.view.bounds.midX) <= 2,
                "drawn writing line centre \(centre) is not the sheet centre \(room.view.bounds.midX) at \(size)")
    }

    @Test
    func lineFadeMaskMatchesTheLiveTrialGradient() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = FocusClock(0)
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = room
        window.setContentSize(NSSize(width: 1040, height: 720))
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        let editor = try #require(descendants(of: room.view, as: AppendOnlyTextView.self).first)
        let scroll = try #require(editor.enclosingScrollView)
        let paper = try #require(scroll.superview)
        editor.insertText("one\ntwo\nthree", replacementRange: NSRange(location: NSNotFound, length: 0))
        room.viewDidLayout()
        room.refreshRoom()
        RoomWindowKeeper.windows.append(window)

        let mask = try #require(scroll.layer?.mask as? CAGradientLayer)
        #expect(scroll.layer?.isGeometryFlipped == true)
        #expect(mask.startPoint == CGPoint(x: 0.5, y: 0))
        let height = scroll.bounds.height
        let locations = try #require(mask.locations).map { CGFloat(truncating: $0) }
        let colors = try #require(mask.colors) as! [CGColor]
        let scrollTop = paper.bounds.height - scroll.frame.maxY
        let boxTop = try currentLineTop(in: editor, paper: paper) - scrollTop
        let inkOffset = try #require(editor.currentLineInkOffsetY())
        let renderedCentre = boxTop + inkOffset
        let line = CGFloat(WritingFontSize.medium.points) * 1.6
        #expect(inkOffset > 0)
        #expect(inkOffset < line / 2)
        func alpha(at offset: CGFloat) -> CGFloat? {
            // The room rounds its zen anchor to a whole point, so the rendered line can
            // sit up to half a point from the gradient's computed centre.
            let target = (renderedCentre + offset) / height
            guard let index = locations.firstIndex(where: { abs($0 - target) * height <= 1 }) else { return nil }
            return colors[index].alpha
        }
        #expect(abs((alpha(at: -line) ?? -1) - 0.22) < 0.01)
        #expect(abs((alpha(at: -2 * line) ?? -1) - 0.07) < 0.01)
        #expect(abs((alpha(at: -0.5 * line) ?? -1) - 1) < 0.01)
        #expect(abs((alpha(at: 0.5 * line) ?? -1) - 1) < 0.01)
        #expect(abs((alpha(at: line) ?? -1) - 0.22) < 0.01)
        #expect(abs((alpha(at: 2 * line) ?? -1) - 0.07) < 0.01)
        let top = try #require(alpha(at: -2.5 * line))
        #expect(top <= 0.001)
    }

    @Test
    func sessionTypographyUsesOneInkColourForEveryLine() throws {
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "first\nsecond\ncurrent"))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        textView.applySessionTypography()

        let storage = try #require(textView.textStorage)
        for location in [0, 6, 13, textView.string.count - 1] {
            let color = try #require(storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)
            #expect(abs(color.alphaComponent - 1) < 0.001)
            #expect(storage.attribute(.shadow, at: location, effectiveRange: nil) == nil)
        }
        #expect(textView.alignment == .center)
        let paragraph = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.alignment == .center)
    }

    // MARK: - Geometry helpers

    private func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, as: type)
        }
    }

    private func topInPaper(_ y: CGFloat, of view: NSView, paper: NSView) -> CGFloat {
        paper.bounds.height - paper.convert(NSPoint(x: 0, y: y), from: view).y
    }

    private func currentLineRect(in textView: AppendOnlyTextView) throws -> NSRect {
        let layout = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        layout.ensureLayout(for: container)
        let length = (textView.string as NSString).length
        if textView.string.isEmpty || textView.string.hasSuffix("\n") {
            return layout.extraLineFragmentRect
        }
        let glyph = layout.glyphIndexForCharacter(at: max(length - 1, 0))
        return layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    private func currentLineTop(in textView: AppendOnlyTextView, paper: NSView) throws -> CGFloat {
        let line = try currentLineRect(in: textView)
        return topInPaper(textView.textContainerOrigin.y + line.midY, of: textView, paper: paper)
    }

    private func firstLineTop(in textView: AppendOnlyTextView, paper: NSView) throws -> CGFloat {
        let layout = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        layout.ensureLayout(for: container)
        let line = layout.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        return topInPaper(textView.textContainerOrigin.y + line.minY, of: textView, paper: paper)
    }

    private func lineCentreX(in textView: AppendOnlyTextView, paper: NSView) throws -> CGFloat {
        let line = try currentLineRect(in: textView)
        return paper.convert(NSPoint(x: textView.textContainerOrigin.x + line.midX, y: 0), from: textView).x
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

        textView.applySessionTypography()

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

        textView.applySessionTypography()

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
        textView.applySessionTypography()

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
        textView.applySessionTypography()

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
        textView.applySessionTypography()

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

        textView.applySessionTypography()

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

        textView.applySessionTypography()

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
        textView.applySessionTypography()

        let before = try glyphBaselineY(in: textView, characterIndex: 0)
        textView.setMarkedText(
            "r",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let after = try glyphBaselineY(in: textView, characterIndex: 0)

        #expect(abs(before - after) < 0.5)
    }

    @Test func movementCommandsDenyAndKeepCaretAtEnd() {
        let engine = SessionEngine()
        let controller = SessionViewController(appState: licensedTestState(sessionEngine: engine))
        let editor = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        editor.loadRestoredText("hello world")
        for selector in ["moveLeft:", "moveRight:", "moveUp:", "moveDown:",
                         "moveToBeginningOfDocument:", "moveToEndOfDocument:",
                         "moveToBeginningOfLine:", "moveToEndOfLine:",
                         "moveToBeginningOfParagraph:", "moveToEndOfParagraph:",
                         "moveToLeftEndOfLine:", "moveToRightEndOfLine:",
                         "pageUp:", "pageDown:", "moveWordLeft:", "moveWordRight:",
                         "moveWordForward:", "moveWordBackward:",
                         "moveLeftAndModifySelection:", "moveRightAndModifySelection:",
                         "moveUpAndModifySelection:", "moveDownAndModifySelection:",
                         "moveWordLeftAndModifySelection:", "moveWordRightAndModifySelection:",
                         "moveToBeginningOfDocumentAndModifySelection:",
                         "moveToEndOfDocumentAndModifySelection:",
                         "pageUpAndModifySelection:", "pageDownAndModifySelection:"] {
            #expect(controller.textView(editor, doCommandBy: Selector((selector))))
            #expect(editor.selectedRange() == NSRange(location: 11, length: 0))
            #expect(engine.lastDenyAt != nil)
        }
    }

    @Test
    func imeMovementStaysWithinMarkedRange() throws {
        let engine = SessionEngine()
        let controller = SessionViewController(appState: licensedTestState(sessionEngine: engine))
        let editor = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        editor.configureSessionTypography()
        editor.loadRestoredText("draft")
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = try #require(editor.hasMarkedText() ? editor.markedRange() : nil)
        let inside = NSRange(location: marked.location + 2, length: 0)
        let outside = NSRange(location: 0, length: 0)
        #expect(controller.textView(editor, doCommandBy: Selector(("moveLeft:"))) == false)
        #expect(controller.textView(editor, willChangeSelectionFromCharacterRange: editor.selectedRange(),
                                    toCharacterRange: inside) == inside)
        #expect(engine.lastDenyAt == nil)
        #expect(controller.textView(editor, willChangeSelectionFromCharacterRange: inside,
                                    toCharacterRange: outside) == NSRange(location: NSMaxRange(marked), length: 0))
        #expect(engine.lastDenyAt != nil)
        #expect(controller.textView(editor, doCommandBy: Selector(("moveRight:"))) == false)
        #expect(controller.textView(editor, doCommandBy: #selector(NSResponder.deleteWordBackward(_:))))
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
            markedRange: textView.hasMarkedText() ? textView.markedRange() : nil
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
            markedRange: textView.hasMarkedText() ? textView.markedRange() : nil
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

    @Test
    func loadRestoredTextRestoresExistingDraftIntoEmptyEditor() {
        // 活动会话从 Home 返回 Writing 时，新 SessionVC 用 loadRestoredText 把 engine 草稿写回
        // 空编辑器。它受控豁免 append-only 守卫（isRestoringProgrammatically），写后重应用 zen 排印
        // 并把 caret 移到 UTF-16 末尾。
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()

        textView.loadRestoredText("hello world")

        #expect(textView.string == "hello world")
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        #expect(textView.selectedRange() == end)
    }

    @Test
    func loadRestoredTextDoesNotWeakenUserAppendOnlyGuards() {
        // 恢复入口是受控豁免：flag 仅在 loadRestoredText 执行期间为 true、写后复位。
        // 用户输入路径（未经 insertText 的直接 replaceCharacters、paste、cut）在恢复之后仍被守卫拦截。
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        var denied = 0
        textView.onDeny = { denied += 1 }

        textView.loadRestoredText("existing draft stays")
        #expect(textView.string == "existing draft stays")

        // 恢复后，未经 insertText 的直接 replaceCharacters 仍 deny（未被恢复豁免污染）。
        let before = denied
        textView.replaceCharacters(in: NSRange(location: 0, length: 8), with: "other")
        #expect(denied == before + 1)
        #expect(textView.string == "existing draft stays")

        // paste / cut 仍 deny。
        let before2 = denied
        textView.paste(nil)
        textView.cut(nil)
        #expect(denied == before2 + 2)
    }

    @Test
    func loadRestoredTextIsNoOpForEmptyText() {
        // 空 engine 文本不写（避免清空已有内容 / 误触发）。
        let textView = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.configureSessionTypography()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "keep me"))

        textView.loadRestoredText("")

        #expect(textView.string == "keep me")
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

@MainActor
private enum RoomWindowKeeper {
    static var windows: [NSWindow] = []
}

private final class FocusClock {
    var now: TimeInterval
    init(_ now: TimeInterval) { self.now = now }
}
