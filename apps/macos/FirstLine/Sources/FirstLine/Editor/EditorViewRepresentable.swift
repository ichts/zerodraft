/**
 * [INPUT]: 依赖 SessionEngine 与 AppendOnlyTextView
 * [OUTPUT]: 提供 EditorViewRepresentable SwiftUI↔AppKit 编辑器桥
 * [POS]: FirstLine editor bridge，负责把固定字体 NSTextView 嵌进 SwiftUI session 界面
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppKit
import SwiftUI

struct EditorViewRepresentable: NSViewRepresentable {
    @Bindable var engine: SessionEngine

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = AppendOnlyTextView()

        textView.delegate = context.coordinator
        textView.onCommittedText = { inserted in
            context.coordinator.engine.registerCommittedText(inserted)
        }
        textView.onMarkedTextActivity = {
            context.coordinator.engine.registerMarkedTextActivity()
        }
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 24, height: 0)
        textView.selectedTextAttributes = [:]
        textView.insertionPointColor = NSColor(FirstLineColors.ink)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        textView.configureSessionTypography()

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AppendOnlyTextView else { return }

        let isComposing = textView.hasMarkedText()
        let shouldSyncText = isComposing == false && textView.string != engine.text
        let needsCompositionRefresh = isComposing == false && (shouldSyncText || textView.pendingCompositionRefresh)

        if shouldSyncText {
            textView.string = engine.text
            textView.applySessionTypographyToExistingText()
        }

        textView.isEditable = engine.phase == .writing || engine.phase == .danger

        if isComposing == false {
            let end = NSRange(location: textView.string.count, length: 0)
            if textView.selectedRange() != end {
                textView.setSelectedRange(end)
            }

            if needsCompositionRefresh {
                textView.scrollCaretToCompositionAnchor()
                textView.clearPendingCompositionRefresh()
            }
        }

        if textView.isEditable {
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let engine: SessionEngine

        init(engine: SessionEngine) {
            self.engine = engine
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let blockedSelectors = [
                #selector(UndoManager.undo),
                Selector(("redo:")),
                #selector(NSText.paste(_:)),
                #selector(NSText.cut(_:)),
            ]

            if blockedSelectors.contains(commandSelector) {
                return true
            }

            let deleteSelectors = [
                #selector(NSResponder.deleteBackward(_:)),
                #selector(NSResponder.deleteForward(_:)),
            ]

            if deleteSelectors.contains(commandSelector) {
                if textView.hasMarkedText() { return false }
                return true
            }

            return false
        }

        func textView(_ textView: NSTextView,
                      willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                      toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
            if textView.hasMarkedText() {
                return newSelectedCharRange
            }

            return NSRange(location: textView.string.count, length: 0)
        }
    }
}
