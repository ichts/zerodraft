/**
 * [INPUT]: 依赖 NSTextView 输入事件、AppState 输入授权与 SessionEngine 活动回调
 * [OUTPUT]: 提供 AppendOnlyTextView 自定义编辑器
 * [POS]: AppKit editor core，负责 append-only、IME 候选内删除、居中 zen 排版与受控 wipe；TextKit 位置用 UTF-16
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import AppKit
import CoreText

final class AppendOnlyTextView: NSTextView, @preconcurrency NSLayoutManagerDelegate {
    /// The flag marks nonempty committed text or composition activity for trial reservation.
    var onPrepareInput: ((Bool) -> Bool)?
    var onCommittedText: ((String) -> Void)?
    var onMarkedTextActivity: (() -> Void)?
    var onDeny: (() -> Void)?

    private var compositionAnchorY: CGFloat = 0
    private let insetEpsilon: CGFloat = 0.5
    private(set) var pendingCompositionRefresh = true
    /// The room sets this from Reduce Motion; history scrolls then snap.
    var animatesHistoryScroll = true
    /// One uniform opacity per completed line, closest line first; older lines are gone.
    static let historyLineOpacities: [CGFloat] = [1, 0.22, 0.07]
    /// Guards replaceCharacters during a live insertText so the append path never
    /// trips a false deny. TextKit location/length values are UTF-16 offsets.
    private var isPerformingInsertion = false
    private var isUpdatingMarkedText = false
    /// Guards the text storage edits AppKit itself makes while a composition key
    /// (delete/forward/selection) is being handed to the input context.
    private var isCompositionEditing = false
    /// The marked range the input method last handed us. Third-party IMEs may
    /// replace that range through insertText after unmarkText, which is still a
    /// composition commit, not a user edit.
    private var compositionRange: NSRange?
    /// Guards replaceCharacters during a programmatic restore of an existing engine
    /// draft (loadRestoredText). The append-only user-input guards behave identically
    /// whenever this flag is false; it only allows the controlled restore path to write
    /// the already-existing engine text back into the view when re-entering a live
    /// session surface (Home -> Writing). User input is never weakened.
    private var isRestoringProgrammatically = false
    private var sessionFontSize: CGFloat = 28
    private var typographyConfigured = false
    private let punctuationFontScale: CGFloat = 0.84
    private let lightPunctuationCharacters = CharacterSet(charactersIn: ".,:;!?，。：；！？")
    private let writingFont: WritingFontCandidate = .pitchLight
    private let chineseFont: ChineseFontCandidate = .zhuqueFangsong
    private var sessionFont: NSFont {
        writingFont.fontWithCJKFallback(size: sessionFontSize)
            ?? NSFont.systemFont(ofSize: sessionFontSize, weight: .regular)
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
            // The writing column is narrowed by textContainerInset, so the container
            // width is the view width minus both insets. Writing bounds.width here
            // re-centred the column in the full view + inset, shifting the text right
            // by the inset at wide window sizes.
            if let textContainer {
                let usable = max(bounds.width - 2 * textContainerInset.width, 0)
                if abs(textContainer.containerSize.width - usable) > 0.5 {
                    textContainer.containerSize = NSSize(width: usable, height: .greatestFiniteMagnitude)
                }
            }
            updateViewportInsetsIfNeeded()
        }
    }

    override var allowsUndo: Bool {
        get { false }
        set { }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let hadMarkedText = hasMarkedText()
        let isActivity = !plainString(from: string).isEmpty
        guard isRestoringProgrammatically || (onPrepareInput?(isActivity) ?? true) else { return }
        let viewport = preservedCompositionViewport()
        if !isRestoringProgrammatically && isActivity {
            onMarkedTextActivity?()
        }

        let targetRange: NSRange
        if replacementRange.location != NSNotFound,
           NSMaxRange(replacementRange) <= (textStorage?.length ?? 0) {
            targetRange = replacementRange
        } else if hadMarkedText {
            targetRange = compositionRange ?? self.selectedRange()
        } else {
            targetRange = self.selectedRange()
        }
        isUpdatingMarkedText = true
        defer { isUpdatingMarkedText = false }
        super.setMarkedText(normalizedMarkedText(string), selectedRange: selectedRange, replacementRange: targetRange)
        compositionRange = hasMarkedText() ? markedRange() : nil
        restoreCompositionViewport(viewport)
    }

    override func unmarkText() {
        // Keep the last marked range until the following insertText commits it;
        // third-party IMEs may unmark before they replace the composition.
        let keptComposition = compositionRange
        let viewport = preservedCompositionViewport()
        isUpdatingMarkedText = true
        super.unmarkText()
        isUpdatingMarkedText = false
        compositionRange = keptComposition
        restoreCompositionViewport(viewport)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let inserted = plainString(from: string)
        let previousEnd = NSRange(location: utf16Length, length: 0)
        let isDefaultRange = replacementRange.location == NSNotFound
        let isMarkedCommit = hasMarkedText()
        let isCompositionReplacement: Bool = {
            guard let compositionRange else { return false }
            return replacementRange.location >= compositionRange.location
                && NSMaxRange(replacementRange) <= NSMaxRange(compositionRange)
        }()

        guard isMarkedCommit || isDefaultRange || replacementRange == previousEnd
                || isCompositionReplacement || isUpdatingMarkedText || isCompositionEditing else {
            onDeny?()
            return
        }

        if !isUpdatingMarkedText && !isRestoringProgrammatically {
            guard onPrepareInput?(!inserted.isEmpty) ?? true else { return }
        }
        let end = NSRange(location: utf16Length, length: 0)
        if (isMarkedCommit && hasMarkedText()) || isCompositionReplacement {
            isPerformingInsertion = true
            defer { isPerformingInsertion = false }
            super.insertText(string, replacementRange: replacementRange)
        } else {
            selectedRange = end
            isPerformingInsertion = true
            defer { isPerformingInsertion = false }
            super.insertText(string, replacementRange: end)
        }

        if isMarkedCommit || isCompositionReplacement { compositionRange = nil }
        guard inserted.isEmpty == false && !isUpdatingMarkedText && !isRestoringProgrammatically else { return }
        pendingCompositionRefresh = true
        applySessionTypography()
        onCommittedText?(inserted)
    }

    /// Clears a draft only after the engine has adjudicated a wipe.
    func clearWipedText() {
        isRestoringProgrammatically = true
        defer { isRestoringProgrammatically = false }
        let hadComposition = hasMarkedText()
        if hadComposition { unmarkText() }
        // The input context keeps its own marked range. If the wipe happens while a
        // composition is live, the next Pinyin key would otherwise replace that stale
        // range in the now-empty editor and the first letter would vanish.
        if hadComposition { inputContext?.discardMarkedText() }
        compositionRange = nil
        textStorage?.setAttributedString(NSAttributedString(string: ""))
        setSelectedRange(NSRange(location: 0, length: 0))
        // A long draft leaves the scroll view at the bottom; the empty room's line
        // must return to the same anchor as a fresh start.
        pendingCompositionRefresh = true
    }

    /// A selection change that AppKit makes on the IME's behalf (setMarkedText,
    /// unmark, delete, commit) is allowed even if it leaves the marked range.
    var isCompositionEditingText: Bool {
        isUpdatingMarkedText || isPerformingInsertion || isCompositionEditing
    }

    private var isCompositionSessionLive: Bool {
        guard let compositionRange else { return false }
        return NSMaxRange(compositionRange) <= utf16Length
    }

    private func preservedCompositionViewport() -> NSPoint? {
        enclosingScrollView?.contentView.bounds.origin
    }

    private func restoreCompositionViewport(_ origin: NSPoint?) {
        guard let origin, let scrollView = enclosingScrollView,
              scrollView.contentView.bounds.origin != origin else { return }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func replaceCharacters(in range: NSRange, with string: String) {
        let compositionWrite = hasMarkedText() || isUpdatingMarkedText || isPerformingInsertion
            || isRestoringProgrammatically || isCompositionEditing || isCompositionSessionLive
        guard compositionWrite else {
            onDeny?()
            return
        }
        super.replaceCharacters(in: range, with: string)
    }

    override func deleteBackward(_ sender: Any?) {
        guard hasMarkedText() || isCompositionEditing || isCompositionSessionLive else {
            onDeny?()
            return
        }
        // Hand the key to the active input method; it owns candidate editing and
        // the marked range. Never rewrite the composition ourselves. A composition
        // update is not allowed to move the viewport.
        let viewport = preservedCompositionViewport()
        isCompositionEditing = true
        super.deleteBackward(sender)
        isCompositionEditing = false
        restoreCompositionViewport(viewport)
    }

    override func deleteForward(_ sender: Any?) {
        guard hasMarkedText() || isCompositionEditing || isCompositionSessionLive else {
            onDeny?()
            return
        }
        // Hand the key to the active input method, same as deleteBackward.
        let viewport = preservedCompositionViewport()
        isCompositionEditing = true
        super.deleteForward(sender)
        isCompositionEditing = false
        restoreCompositionViewport(viewport)
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
        onDeny?()
        return false
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
    /// The caret band is one em tall with its bottom 0.12 em below the baseline,
    /// the same geometry the house `.caret` rule uses. One band for every glyph
    /// keeps the caret from bobbing between scripts, and the empty caret and the
    /// first typed character then share the exact same rect origin.
    private static let caretDescenderEm: CGFloat = 0.12

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: adjustedCaretRectForCurrentInsertionPoint(from: rect), color: color, turnedOn: flag)
    }

    /// The caret rect the editor draws for the current insertion point. Used by the
    /// room's geometry tests; the drawing path comes through drawInsertionPoint.
    func caretRectForCurrentInsertionPoint() -> NSRect {
        let insertion = min(max(selectedRange().location, 0), utf16Length)
        if let window {
            let screen = firstRect(forCharacterRange: NSRange(location: insertion, length: 0), actualRange: nil)
            let inView = convert(window.convertFromScreen(screen), from: nil)
            if inView.height > 0 {
                return adjustedCaretRectForCurrentInsertionPoint(from: inView)
            }
        }
        return adjustedCaretRectForCurrentInsertionPoint(from: fallbackLineRect())
    }

    /// Baseline of the line the caret occupies, in view coordinates. Empty text uses
    /// the extra line fragment, which shares the first typed line's baseline, so the
    /// caret does not move vertically when the first character lands.
    func currentInsertionBaseline() -> CGFloat? {
        guard let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let insertion = min(max(selectedRange().location, 0), utf16Length)
        if string.isEmpty || (insertion == utf16Length && string.hasSuffix("\n")) {
            let extra = layoutManager.extraLineFragmentRect
            return textContainerOrigin.y + extra.minY + stableLineBaselineOffset
        }
        let index = insertion < utf16Length ? insertion : max(insertion - 1, 0)
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        return textContainerOrigin.y + line.minY + layoutManager.location(forGlyphAt: glyph).y
    }

    /// Line box used only when the view has no window to ask for the insertion rect.
    private func fallbackLineRect() -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        let insertion = min(max(selectedRange().location, 0), utf16Length)
        let line: NSRect
        if string.isEmpty || (insertion == utf16Length && string.hasSuffix("\n")) {
            line = layoutManager.extraLineFragmentRect
        } else {
            let index = insertion < utf16Length ? insertion : max(insertion - 1, 0)
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        }
        return NSRect(x: textContainerOrigin.x + line.minX, y: textContainerOrigin.y + line.minY,
                      width: Self.caretWidth, height: line.height)
    }

    func adjustedCaretRectForCurrentInsertionPoint(from rect: NSRect) -> NSRect {
        let baseline = currentInsertionBaseline() ?? (rect.minY + stableLineBaselineOffset)
        let height = caretHeight
        return NSRect(x: rect.minX, y: baseline - height * (1 - Self.caretDescenderEm),
                      width: Self.caretWidth, height: height)
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

    /// One baseline offset for every real line, so mixed Latin/CJK lines keep the
    /// same grid and the first typed line shares the empty room's inserted line.
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
            sub.frame.origin.x = adjusted.origin.x
            sub.frame.origin.y = adjusted.origin.y
            sub.frame.size.width = Self.caretWidth
            sub.frame.size.height = adjusted.height
            sub.bounds.size.width = Self.caretWidth
            sub.bounds.size.height = adjusted.height
        }
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

    func configureSessionTypography(size: CGFloat = 28) {
        guard !typographyConfigured || size != sessionFontSize else { return }
        typographyConfigured = true
        sessionFontSize = size
        let paragraph = sessionParagraphStyle()
        let attributes = activeTextAttributes(paragraph: paragraph)

        defaultParagraphStyle = paragraph
        typingAttributes = attributes
        insertionPointColor = FirstLineColors.inkNSColor
        textColor = FirstLineColors.inkNSColor
        font = sessionFont
        alignment = .center
        layoutManager?.delegate = self
        // The fixed 1.6 line box already includes the leading; the fallback font's
        // own leading would add another 5.6 pt to CJK lines and break the pitch.
        layoutManager?.usesFontLeading = false

        markedTextAttributes = activeTextAttributes(paragraph: paragraph)
        applySessionTypography()
    }

    /// Controlled restore of an existing engine draft when re-entering a live session
    /// surface (Home -> Writing). Unlike a user input path, this writes directly via the
    /// textStorage while isRestoringProgrammatically is set, so the append-only guard in
    /// replaceCharacters lets the write through. The user-input guards are unchanged when
    /// this flag is false. Re-applies zen typography and moves the caret to the UTF-16 end.
    func loadRestoredText(_ text: String) {
        guard text.isEmpty == false else { return }
        guard let textStorage else { return }
        isRestoringProgrammatically = true
        defer { isRestoringProgrammatically = false }
        let whole = NSRange(location: 0, length: textStorage.length)
        textStorage.replaceCharacters(in: whole, with: text)
        compositionRange = nil
        let end = NSRange(location: utf16Length, length: 0)
        if selectedRange() != end { setSelectedRange(end) }
        applySessionTypography()
        pendingCompositionRefresh = true
    }

    /// Base ink for the current line; completed lines are stepped by `applyLineOpacity`
    /// to the live trial's 100/22/7 intent.
    func applySessionTypography() {
        guard hasMarkedText() == false else { return }
        guard let textStorage else { return }

        let paragraph = sessionParagraphStyle()
        typingAttributes = activeTextAttributes(paragraph: paragraph)
        guard textStorage.length > 0 else { return }

        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.removeAttribute(.shadow, range: range)
        textStorage.addAttributes(activeTextAttributes(paragraph: paragraph), range: range)
        applyLightPunctuationTypography(in: range, textStorage: textStorage)
        applyScriptBoundaryKerning(in: range, textStorage: textStorage)
        textStorage.endEditing()
        // Line opacities need a laid-out storage, so apply them after the edit block.
        applyLineOpacity(in: range, textStorage: textStorage)
    }

    /// Each completed line gets one uniform opacity; the current line is full. The
    /// line's top and bottom always match, and older lines are gone. The opacities
    /// follow the live trial's intent (100/22/7).
    private func applyLineOpacity(in range: NSRange, textStorage: NSTextStorage) {
        guard textStorage.length > 0, let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        var lines: [(index: Int, glyphRange: NSRange)] = []
        var index = 0
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: textStorage.length)
        ) { _, _, _, glyphRange, _ in
            lines.append((index, glyphRange))
            index += 1
        }
        guard !lines.isEmpty else { return }
        let length = textStorage.length
        let insertion = min(max(selectedRange().location, 0), length)
        let currentIndex: Int
        if insertion == length, string.hasSuffix("\n") {
            currentIndex = lines.count
        } else if insertion < length {
            let glyph = layoutManager.glyphIndexForCharacter(at: insertion)
            currentIndex = lines.first { NSLocationInRange(glyph, $0.glyphRange) }?.index ?? (lines.count - 1)
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: max(length - 1, 0))
            currentIndex = lines.first { NSLocationInRange(glyph, $0.glyphRange) }?.index ?? (lines.count - 1)
        }
        for line in lines {
            let distance = currentIndex - line.index
            let alpha: CGFloat
            if distance <= 0 {
                alpha = 1
            } else if distance < Self.historyLineOpacities.count {
                alpha = Self.historyLineOpacities[distance]
            } else {
                alpha = 0
            }
            let characterRange = layoutManager.characterRange(forGlyphRange: line.glyphRange, actualGlyphRange: nil)
            let clipped = NSIntersectionRange(characterRange, range)
            guard clipped.length > 0 else { continue }
            textStorage.addAttribute(.foregroundColor,
                                      value: FirstLineColors.inkNSColor.withAlphaComponent(alpha),
                                      range: clipped)
        }
    }

    func setCompositionAnchor(_ y: CGFloat) {
        guard abs(compositionAnchorY - y) > insetEpsilon else { return }
        compositionAnchorY = y
        updateViewportInsetsIfNeeded()
        pendingCompositionRefresh = true
    }

    func scrollCaretToCompositionAnchor() {
        guard let scrollView = enclosingScrollView,
              let line = compositionLineRect() else { return }

        // Zen: the current (last) line sits at the anchor; earlier lines move up and fade.
        let initialY = round(textContainerOrigin.y + line.midY - compositionAnchorY)
        let targetY = max(
            -scrollView.contentInsets.top, initialY,
            ceil(textContainerOrigin.y + line.maxY - scrollView.contentView.bounds.height + 40)
        )
        let currentY = scrollView.contentView.bounds.origin.y
        let delta = abs(currentY - targetY)
        guard delta > insetEpsilon else { return }
        let lineHeight = sessionFontSize * 1.6
        // A new line moves the history by one pitch; animate that, and snap on a
        // session/resize jump. Reduce Motion snaps.
        if animatesHistoryScroll, delta <= lineHeight * 2.5 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
            }
        } else {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func compositionLineRect() -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        if string.isEmpty || (selectedRange().location == utf16Length && string.last == "\n") {
            return layoutManager.extraLineFragmentRect
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: max(selectedRange().location - 1, 0))
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    func clearPendingCompositionRefresh() {
        pendingCompositionRefresh = false
    }

    private func updateViewportInsetsIfNeeded() {
        guard let scrollView = enclosingScrollView else { return }

        let viewportHeight = round(scrollView.contentView.bounds.height)
        guard viewportHeight > 0, compositionAnchorY > 0,
              let line = compositionLineRect() else { return }

        let topInset = max(0, round(compositionAnchorY - textContainerOrigin.y - line.height / 2))
        let bottomInset = max(0, viewportHeight - topInset)
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

    /// UTF-16 code-unit count of the current text. NSRange/TextKit locations are
    /// UTF-16 offsets; Swift's `String.count` counts grapheme clusters and
    /// misplaces the caret after emoji/flags/multi-scalar graphemes.
    private var utf16Length: Int {
        (string as NSString).length
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
        // Fixed line pitch. lineHeightMultiple scales each font's natural line height,
        // so the CJK fallback (a taller font) produced a 58.4 pt line next to the
        // Latin 44.8 pt line. Min == max forces 1.6 x font size for every script.
        let lineHeight = sessionFontSize * 1.6
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineHeightMultiple = 1
        paragraph.lineSpacing = 0
        return paragraph
    }

    private func activeTextAttributes(paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: sessionFont,
            .foregroundColor: FirstLineColors.inkNSColor,
            .paragraphStyle: paragraph,
        ]
    }

}
