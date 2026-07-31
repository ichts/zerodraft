/**
 * [INPUT]: 依赖 NSTextView 输入事件与 SessionEngine 活动回调
 * [OUTPUT]: 提供 AppendOnlyTextView 自定义编辑器
 * [POS]: FirstLine 的 AppKit editor core，负责 append-only、IME 安全约束与固定写作字体
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppKit
import CoreText

final class AppendOnlyTextView: NSTextView, @preconcurrency NSLayoutManagerDelegate {
    var onCommittedText: ((String) -> Void)?
    var onMarkedTextActivity: (() -> Void)?
    var onDeny: (() -> Void)?

    private let compositionTopRatio: CGFloat = 0.35
    private let compositionBottomRatio: CGFloat = 0.65
    private let insetEpsilon: CGFloat = 0.5
    private var lastAppliedViewportHeight: CGFloat = 0
    private(set) var pendingCompositionRefresh = true
    private let sessionFontSize: CGFloat = 28
    private let punctuationFontScale: CGFloat = 0.84
    private let lightPunctuationCharacters = CharacterSet(charactersIn: ".,:;!?，。：；！？")
    private let writingFont: WritingFontCandidate = .pitchLight
    private let chineseFont: ChineseFontCandidate = .zhuqueFangsong
    private var sessionFont: NSFont {
        let baseFont = writingFont.font(size: sessionFontSize)
            ?? NSFont.systemFont(ofSize: sessionFontSize, weight: .regular)
        return fontByAddingCJKFallback(to: baseFont, size: sessionFontSize)
    }
    private var stableLineBaselineOffset: CGFloat {
        guard let cjk = chineseFont.font(size: sessionFontSize) else { return sessionFontSize }

        return ceil(cjk.ascender - cjk.descender + cjk.leading + abs(cjk.descender))
    }
    private var caretHeight: CGFloat {
        ceil(sessionFontSize)
    }
    private var targetScriptBoundaryGap: CGFloat {
        sessionFontSize * 0.1
    }

    override var frame: NSRect {
        didSet {
            textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
            updateViewportInsetsIfNeeded()
        }
    }

    override var allowsUndo: Bool {
        get { false }
        set { }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if plainString(from: string).isEmpty == false {
            onMarkedTextActivity?()
        }

        super.setMarkedText(normalizedMarkedText(string), selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let inserted = plainString(from: string)
        let end = NSRange(location: self.string.count, length: 0)
        let isDefaultRange = replacementRange.location == NSNotFound
        let isMarkedCommit = hasMarkedText()

        guard isMarkedCommit || isDefaultRange || replacementRange == end else {
            return
        }

        if isMarkedCommit {
            super.insertText(string, replacementRange: replacementRange)
        } else {
            selectedRange = end
            super.insertText(string, replacementRange: end)
        }

        guard inserted.isEmpty == false else { return }
        pendingCompositionRefresh = true
        applyFocusTypographyToExistingText()
        onCommittedText?(inserted)
    }

    override func replaceCharacters(in range: NSRange, with string: String) {
        guard hasMarkedText() else {
            return
        }

        super.replaceCharacters(in: range, with: string)
    }

    override func deleteBackward(_ sender: Any?) {
        guard hasMarkedText() else {
            onDeny?()
            return
        }

        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        guard hasMarkedText() else {
            onDeny?()
            return
        }

        super.deleteForward(sender)
    }

    override func cut(_ sender: Any?) {
        onDeny?()
    }

    override func paste(_ sender: Any?) {
        onDeny?()
    }

    override func readSelection(from pboard: NSPasteboard) -> Bool {
        onDeny?()
        return false
    }

    override func dragSelection(with event: NSEvent, offset: NSSize, slideBack: Bool) -> Bool {
        false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let blocked = [
            #selector(UndoManager.undo),
            Selector(("redo:")),
            #selector(NSText.cut(_:)),
            #selector(NSText.paste(_:)),
            #selector(NSResponder.deleteBackward(_:)),
            #selector(NSResponder.deleteForward(_:)),
            #selector(NSResponder.deleteWordBackward(_:)),
            #selector(NSResponder.deleteWordForward(_:)),
            #selector(NSResponder.deleteToBeginningOfLine(_:)),
            #selector(NSResponder.deleteToEndOfLine(_:)),
            #selector(NSResponder.deleteToBeginningOfParagraph(_:)),
            #selector(NSResponder.deleteToEndOfParagraph(_:)),
            #selector(NSResponder.yank(_:)),
            #selector(NSResponder.transpose(_:)),
        ]

        if blocked.contains(item.action ?? Selector(("_noop:"))) {
            return false
        }

        return super.validateUserInterfaceItem(item)
    }

    private static let caretWidth: CGFloat = 1.5
    private static let caretVerticalPadding: CGFloat = 1

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: adjustedCaretRectForCurrentInsertionPoint(from: rect), color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var adjusted = rect
        if rect.width < 10 {
            adjusted = rect.union(adjustedCaretRectForCurrentInsertionPoint(from: rect)).insetBy(dx: -2, dy: -2)
        }
        super.setNeedsDisplay(adjusted, avoidAdditionalLayout: flag)
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        trimCaretLayers()
    }

    override func layout() {
        super.layout()
        updateViewportInsetsIfNeeded()
        trimCaretLayers()
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        baselineOffset.pointee = stableLineBaselineOffset
        return true
    }

    private func trimCaretLayers() {
        guard let layer else { return }
        for sub in layer.sublayers ?? [] {
            guard sub.bounds.height > 10, sub.bounds.width < 10 else { continue }
            let adjusted = adjustedCaretRectForCurrentInsertionPoint(from: sub.frame)
            sub.frame.origin.y = adjusted.origin.y
            sub.frame.size.width = Self.caretWidth
            sub.frame.size.height = adjusted.height
            sub.bounds.size.width = Self.caretWidth
            sub.bounds.size.height = adjusted.height
        }
    }

    func adjustedCaretRectForCurrentInsertionPoint(from rect: NSRect) -> NSRect {
        let adjusted = defaultCaretRect(from: rect)
        if let lineRect = trailingNewlineCaretLineRect(),
           let font = chineseFont.font(size: sessionFontSize),
           let bounds = caretInkBounds(for: "国", font: font) {
            let baseline = textContainerOrigin.y + lineRect.minY + stableLineBaselineOffset
            return caretRect(from: adjusted, baseline: baseline, bounds: bounds)
        }

        guard let character = previousCaretCharacter() else { return adjusted }
        guard let layoutManager, let textContainer else { return adjusted }
        guard let font = caretFont(for: character.value) else { return adjusted }
        guard let bounds = caretInkBounds(for: character.value, font: font) else { return adjusted }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: character.range.location)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
        let baseline = textContainerOrigin.y + lineRect.minY + layoutManager.location(forGlyphAt: glyphIndex).y
        return caretRect(from: adjusted, baseline: baseline, bounds: bounds)
    }

    private func caretRect(from rect: NSRect, baseline: CGFloat, bounds: NSRect) -> NSRect {
        var adjusted = rect
        adjusted.size.width = Self.caretWidth
        let inkTop = baseline - bounds.maxY
        adjusted.origin.y = floor(inkTop + bounds.height / 2 - caretHeight / 2)
        adjusted.size.height = caretHeight
        return adjusted
    }

    private func trailingNewlineCaretLineRect() -> NSRect? {
        let value = string as NSString
        let insertionLocation = min(max(selectedRange().location, 0), value.length)
        guard insertionLocation == value.length, insertionLocation > 0 else { return nil }
        guard value.substring(with: NSRange(location: insertionLocation - 1, length: 1)) == "\n" else { return nil }
        guard let layoutManager, let textContainer else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.extraLineFragmentRect
        return rect.isEmpty ? nil : rect
    }

    private func caretFont(for character: String) -> NSFont? {
        if character.unicodeScalars.contains(where: isWideCJKGlyph) {
            return chineseFont.font(size: sessionFontSize)
        }

        return writingFont.font(size: sessionFontSize)
    }

    private func defaultCaretRect(from rect: NSRect) -> NSRect {
        var adjusted = rect
        adjusted.size.width = Self.caretWidth
        let targetHeight = min(rect.height, sessionFontSize)
        adjusted.origin.y += max((rect.height - targetHeight) / 2, 0)
        adjusted.size.height = targetHeight
        return adjusted
    }

    private func previousCaretCharacter() -> (value: String, range: NSRange)? {
        let value = string as NSString
        let insertionLocation = min(max(selectedRange().location, 0), value.length)
        guard insertionLocation > 0 else { return nil }

        let range = value.rangeOfComposedCharacterSequence(at: insertionLocation - 1)
        return (value.substring(with: range), range)
    }

    private func inkBounds(for character: String, font: NSFont) -> NSRect? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        guard scalar.value <= UInt16.max else { return nil }

        let coreTextFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        var codeUnit = UniChar(scalar.value)
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(coreTextFont, &codeUnit, &glyph, 1), glyph != 0 else { return nil }

        var measuredGlyph = glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(coreTextFont, .horizontal, &measuredGlyph, &bounds, 1)
        guard bounds.height > 0 else { return nil }
        return bounds
    }

    private func caretInkBounds(for character: String, font: NSFont) -> NSRect? {
        if let bounds = inkBounds(for: character, font: font) {
            return bounds
        }

        let fallbackGlyph = character.unicodeScalars.contains(where: isWideCJKGlyph) ? "国" : "x"
        return inkBounds(for: fallbackGlyph, font: font)
    }

    private func isWideCJKGlyph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2EFF,   // CJK Radicals Supplement
             0x3000...0x303F,   // CJK Symbols and Punctuation
             0x3040...0x30FF,   // Hiragana and Katakana
             0x31F0...0x31FF,   // Katakana Phonetic Extensions
             0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xAC00...0xD7AF,   // Hangul Syllables
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0xFF00...0xFFEF:   // Halfwidth and Fullwidth Forms
            return true
        default:
            return false
        }
    }

    override var rangeForUserCompletion: NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func configureSessionTypography() {
        let paragraph = sessionParagraphStyle()
        let attributes = activeTextAttributes(paragraph: paragraph)

        defaultParagraphStyle = paragraph
        typingAttributes = attributes
        insertionPointColor = NSColor(FirstLineColors.ink).withAlphaComponent(0.55)
        textColor = NSColor(FirstLineColors.ink)
        font = sessionFont
        alignment = .center
        layoutManager?.delegate = self

        markedTextAttributes = activeTextAttributes(paragraph: paragraph)
    }

    func applySessionTypographyToExistingText() {
        applyFocusTypographyToExistingText()
    }

    func applyFocusTypographyToExistingText() {
        guard hasMarkedText() == false else { return }
        guard let textStorage else { return }

        let paragraph = sessionParagraphStyle()
        typingAttributes = activeTextAttributes(paragraph: paragraph)
        guard textStorage.length > 0 else { return }

        let range = NSRange(location: 0, length: textStorage.length)
        let activeRange = currentThoughtRange(in: textStorage.string)
        let previousRange = previousThoughtRange(before: activeRange, in: textStorage.string)

        textStorage.beginEditing()
        textStorage.removeAttribute(.shadow, range: range)
        textStorage.addAttributes(hiddenTextAttributes(paragraph: paragraph), range: range)
        if let previousRange, previousRange.length > 0 {
            textStorage.addAttributes(inactiveTextAttributes(paragraph: paragraph), range: previousRange)
        }
        if activeRange.length > 0 {
            textStorage.addAttributes(activeTextAttributes(paragraph: paragraph), range: activeRange)
            textStorage.removeAttribute(.shadow, range: activeRange)
        }
        applyLightPunctuationTypography(in: range, textStorage: textStorage)
        applyScriptBoundaryKerning(in: range, textStorage: textStorage)
        textStorage.endEditing()
    }

    func scrollCaretToCompositionAnchor() {
        guard let scrollView = enclosingScrollView,
              let layoutManager,
              let textContainer else { return }

        if string.isEmpty {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let insertionLocation = selectedRange().location
        let lineRect: NSRect

        if insertionLocation == string.count,
           string.last == "\n",
           layoutManager.extraLineFragmentRect.isEmpty == false {
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            let characterIndex = max(insertionLocation - 1, 0)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
        }

        let viewportHeight = scrollView.contentView.bounds.height
        let anchorY = round(viewportHeight * compositionTopRatio)
        let targetY = max(-scrollView.contentInsets.top, round(lineRect.minY - anchorY))
        let currentY = scrollView.contentView.bounds.origin.y

        guard abs(currentY - targetY) > insetEpsilon else { return }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func clearPendingCompositionRefresh() {
        pendingCompositionRefresh = false
    }

    private func updateViewportInsetsIfNeeded() {
        guard let scrollView = enclosingScrollView else { return }

        let viewportHeight = round(scrollView.contentView.bounds.height)
        guard viewportHeight > 0 else { return }
        guard abs(viewportHeight - lastAppliedViewportHeight) > insetEpsilon else { return }

        lastAppliedViewportHeight = viewportHeight

        let topInset = round(viewportHeight * compositionTopRatio)
        let bottomInset = round(viewportHeight * compositionBottomRatio)
        let currentInsets = scrollView.contentInsets

        guard abs(currentInsets.top - topInset) > insetEpsilon ||
              abs(currentInsets.bottom - bottomInset) > insetEpsilon else { return }

        scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        pendingCompositionRefresh = true
    }

    private func plainString(from value: Any) -> String {
        if let text = value as? String { return text }
        if let text = value as? NSAttributedString { return text.string }
        return ""
    }

    private func normalizedMarkedText(_ value: Any) -> Any {
        let paragraph = sessionParagraphStyle()
        let attributes = activeTextAttributes(paragraph: paragraph)

        if let text = value as? NSAttributedString {
            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.addAttributes(attributes, range: NSRange(location: 0, length: mutable.length))
            return mutable
        }

        if let text = value as? String {
            return NSAttributedString(string: text, attributes: attributes)
        }

        return value
    }

    private func fontByAddingCJKFallback(to baseFont: NSFont, size: CGFloat) -> NSFont {
        guard let cjkFallback = chineseFont.font(size: size) else {
            return baseFont
        }

        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: [cjkFallback.fontDescriptor],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    private func applyLightPunctuationTypography(in range: NSRange, textStorage: NSTextStorage) {
        let punctuationSize = sessionFontSize * punctuationFontScale
        guard let punctuationFont = writingFont.punctuationFont(size: punctuationSize) else { return }

        let value = textStorage.string as NSString
        value.enumerateSubstrings(in: range, options: [.byComposedCharacterSequences]) { substring, substringRange, _, _ in
            guard let scalar = substring?.unicodeScalars.first else { return }
            guard self.lightPunctuationCharacters.contains(scalar) else { return }
            guard self.font(punctuationFont, supports: scalar) else { return }
            textStorage.addAttribute(.font, value: punctuationFont, range: substringRange)
        }
    }

    private func font(_ font: NSFont, supports scalar: Unicode.Scalar) -> Bool {
        guard scalar.value <= UInt16.max else { return false }

        let coreTextFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        var codeUnit = UniChar(scalar.value)
        var glyph = CGGlyph()
        return CTFontGetGlyphsForCharacters(coreTextFont, &codeUnit, &glyph, 1) && glyph != 0
    }

    private func applyScriptBoundaryKerning(in range: NSRange, textStorage: NSTextStorage) {
        let value = textStorage.string as NSString
        var scalars: [(scalar: Unicode.Scalar, range: NSRange)] = []

        value.enumerateSubstrings(in: range, options: [.byComposedCharacterSequences]) { substring, substringRange, _, _ in
            guard let scalar = substring?.unicodeScalars.first else { return }
            scalars.append((scalar, substringRange))
        }

        for index in scalars.indices {
            if index > scalars.startIndex,
               index < scalars.index(before: scalars.endIndex),
               scalars[index].scalar == " ",
               shouldTightenBoundary(left: scalars[scalars.index(before: index)].scalar, right: scalars[scalars.index(after: index)].scalar) {
                let adjustment = explicitSpaceBoundaryKerning(
                    left: scalars[scalars.index(before: index)].scalar,
                    right: scalars[scalars.index(after: index)].scalar
                )
                if adjustment < 0 {
                    textStorage.addAttribute(.kern, value: adjustment, range: scalars[scalars.index(before: index)].range)
                }
                continue
            }

            guard index < scalars.index(before: scalars.endIndex) else { continue }
            let current = scalars[index]
            let next = scalars[scalars.index(after: index)]
            guard shouldTightenBoundary(left: current.scalar, right: next.scalar) else { continue }
            let adjustment = scriptBoundaryKerning(left: current.scalar, right: next.scalar)
            guard adjustment < 0 else { continue }

            textStorage.addAttribute(.kern, value: adjustment, range: current.range)
        }
    }

    private func shouldTightenBoundary(left: Unicode.Scalar, right: Unicode.Scalar) -> Bool {
        let leftIsCJK = isWideCJKGlyph(left)
        let rightIsCJK = isWideCJKGlyph(right)
        guard leftIsCJK != rightIsCJK else { return false }

        let other = leftIsCJK ? right : left
        return CharacterSet.alphanumerics.contains(other)
    }

    private func scriptBoundaryKerning(left: Unicode.Scalar, right: Unicode.Scalar) -> CGFloat {
        let fallback = -ceil(sessionFontSize * 0.04)
        guard let leftFont = font(for: left), let rightFont = font(for: right) else { return fallback }
        guard let leftMetrics = glyphMetrics(for: left, font: leftFont),
              let rightMetrics = glyphMetrics(for: right, font: rightFont) else { return fallback }

        let leftSide = max(leftMetrics.advance - leftMetrics.bounds.maxX, 0)
        let rightSide = max(rightMetrics.bounds.minX, 0)
        return min(targetScriptBoundaryGap - leftSide - rightSide, 0)
    }

    private func explicitSpaceBoundaryKerning(left: Unicode.Scalar, right: Unicode.Scalar) -> CGFloat {
        let fallback = -ceil(sessionFontSize * 0.55)
        guard let leftFont = font(for: left),
              let rightFont = font(for: right),
              let spaceFont = writingFont.font(size: sessionFontSize) else { return fallback }
        guard let leftMetrics = glyphMetrics(for: left, font: leftFont),
              let rightMetrics = glyphMetrics(for: right, font: rightFont),
              let spaceMetrics = glyphMetrics(for: " ", font: spaceFont) else { return fallback }

        let naturalGap = max(leftMetrics.advance - leftMetrics.bounds.maxX, 0)
            + spaceMetrics.advance
            + max(rightMetrics.bounds.minX, 0)
        return min(targetScriptBoundaryGap - naturalGap, 0)
    }

    private func font(for scalar: Unicode.Scalar) -> NSFont? {
        isWideCJKGlyph(scalar)
            ? chineseFont.font(size: sessionFontSize)
            : writingFont.font(size: sessionFontSize)
    }

    private func glyphMetrics(for scalar: Unicode.Scalar, font: NSFont) -> (advance: CGFloat, bounds: NSRect)? {
        guard scalar.value <= UInt16.max else { return nil }

        let coreTextFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        var codeUnit = UniChar(scalar.value)
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(coreTextFont, &codeUnit, &glyph, 1), glyph != 0 else { return nil }

        var measuredGlyph = glyph
        var advance = CGSize.zero
        var bounds = CGRect.zero
        CTFontGetAdvancesForGlyphs(coreTextFont, .horizontal, &measuredGlyph, &advance, 1)
        CTFontGetBoundingRectsForGlyphs(coreTextFont, .horizontal, &measuredGlyph, &bounds, 1)
        return (advance.width, bounds)
    }

    private func sessionParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 1.45
        paragraph.lineSpacing = 0
        return paragraph
    }

    private func activeTextAttributes(paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: sessionFont,
            .foregroundColor: NSColor(FirstLineColors.ink),
            .paragraphStyle: paragraph,
        ]
    }

    private func inactiveTextAttributes(paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3.5
        shadow.shadowOffset = .zero
        shadow.shadowColor = NSColor(FirstLineColors.ink).withAlphaComponent(0.26)

        return [
            .font: sessionFont,
            .foregroundColor: NSColor(FirstLineColors.ink).withAlphaComponent(0.12),
            .paragraphStyle: paragraph,
            .shadow: shadow,
        ]
    }

    private func hiddenTextAttributes(paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: sessionFont,
            .foregroundColor: NSColor(FirstLineColors.ink).withAlphaComponent(0),
            .paragraphStyle: paragraph,
        ]
    }

    private func currentThoughtRange(in value: String) -> NSRange {
        let nsString = value as NSString
        guard nsString.length > 0 else { return NSRange(location: 0, length: 0) }

        let insertionLocation = min(max(selectedRange().location, 0), nsString.length)
        if insertionLocation == nsString.length,
           nsString.length > 0,
           nsString.substring(with: NSRange(location: nsString.length - 1, length: 1)) == "\n" {
            return NSRange(location: nsString.length, length: 0)
        }

        let characterLocation = max(insertionLocation - 1, 0)
        return nsString.paragraphRange(for: NSRange(location: characterLocation, length: 0))
    }

    private func previousThoughtRange(before currentRange: NSRange, in value: String) -> NSRange? {
        let nsString = value as NSString
        guard nsString.length > 0 else { return nil }

        let boundary = min(max(currentRange.location, 0), nsString.length)
        let probeLocation = boundary - 1
        guard probeLocation >= 0 else { return nil }

        let previousRange = nsString.paragraphRange(for: NSRange(location: probeLocation, length: 0))
        guard previousRange.location != currentRange.location || previousRange.length != currentRange.length else {
            return nil
        }

        return previousRange
    }
}
