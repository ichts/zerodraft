/**
 * [INPUT]: AppKit only（NSRange / Selector），无 SwiftUI
 * [OUTPUT]: AppendOnlyInputPolicy - 编辑器 append-only 守卫的单一可测来源
 * [POS]: First Line 编辑器输入策略；封装两块 append-only 守卫逻辑，供 SessionViewController 的
 *        NSTextViewDelegate 与 EditorFocusTests 共用，消除此前 Coordinator/SessionViewController
 *        双份重复。移动命令仅在组合态可进入 marked range；deleteBackward/Forward 在有
 *        marked text 时放行，否则 deny；普通选区强制移到 UTF-16 末尾。
 * [PROTOCOL]: 变更时更新此头部
 *
 * 语义来源（原 EditorViewRepresentable.Coordinator，照搬至 SessionViewController 的同一份逻辑）：
 *   - blockedSelectors: undo / redo: / paste: / cut: / deleteWord* / deleteTo* / yank: / transpose:
 *     -> 一律 registerDeny + return true（吃掉命令）
 *   - deleteSelectors: deleteBackward: / deleteForward: -> hasMarkedText 时 return false（放行给 IME），
 *     否则 registerDeny + return true
 *   - 选区: marked text 内放行；越界则 deny 并约束到组合区末尾；无组合态则约束到 UTF-16 末尾
 */

import AppKit

@MainActor
enum AppendOnlyInputPolicy {
    /// 一律屏蔽的命令选择器（与原 Coordinator.blockedSelectors 逐字一致）。
    static let blockedSelectors: [Selector] = [
        #selector(UndoManager.undo),
        Selector(("redo:")),
        #selector(NSText.paste(_:)),
        #selector(NSText.cut(_:)),
        #selector(NSResponder.deleteWordBackward(_:)),
        #selector(NSResponder.deleteWordForward(_:)),
        #selector(NSResponder.deleteToBeginningOfLine(_:)),
        #selector(NSResponder.deleteToEndOfLine(_:)),
        #selector(NSResponder.deleteToBeginningOfParagraph(_:)),
        #selector(NSResponder.deleteToEndOfParagraph(_:)),
        #selector(NSResponder.yank(_:)),
        #selector(NSResponder.transpose(_:)),
    ]

    static let movementSelectors: [Selector] = [
        Selector(("moveLeft:")),
        Selector(("moveRight:")),
        Selector(("moveUp:")),
        Selector(("moveDown:")),
        Selector(("moveToBeginningOfDocument:")),
        Selector(("moveToEndOfDocument:")),
        Selector(("moveToBeginningOfLine:")),
        Selector(("moveToEndOfLine:")),
        Selector(("moveToBeginningOfParagraph:")),
        Selector(("moveToEndOfParagraph:")),
        Selector(("moveToLeftEndOfLine:")),
        Selector(("moveToRightEndOfLine:")),
        Selector(("pageUp:")),
        Selector(("pageDown:")),
        Selector(("moveWordLeft:")),
        Selector(("moveWordRight:")),
        Selector(("moveWordForward:")),
        Selector(("moveWordBackward:")),
        Selector(("moveLeftAndModifySelection:")),
        Selector(("moveRightAndModifySelection:")),
        Selector(("moveUpAndModifySelection:")),
        Selector(("moveDownAndModifySelection:")),
        Selector(("moveWordLeftAndModifySelection:")),
        Selector(("moveWordRightAndModifySelection:")),
        Selector(("moveToBeginningOfDocumentAndModifySelection:")),
        Selector(("moveToEndOfDocumentAndModifySelection:")),
        Selector(("pageUpAndModifySelection:")),
        Selector(("pageDownAndModifySelection:")),
    ]

    /// 删除单字符命令（hasMarkedText 时放行给 IME 删候选，否则 deny）。
    static let deleteSelectors: [Selector] = [
        #selector(NSResponder.deleteBackward(_:)),
        #selector(NSResponder.deleteForward(_:)),
    ]

    /// 是否应吞掉该命令（返回 true 表示已处理、阻止默认行为）。
    /// - 对于 blockedSelectors：恒为 true（deny）。
    /// - 对于 movementSelectors / deleteSelectors：hasMarkedText 时为 false（放行），否则 true（deny）。
    /// - 其余：false。
    static func shouldDenyCommand(_ selector: Selector, hasMarkedText: Bool) -> Bool {
        if blockedSelectors.contains(selector) { return true }
        if movementSelectors.contains(selector) || deleteSelectors.contains(selector) {
            return !hasMarkedText
        }
        return false
    }

    /// 选区重定向：需要强制到 UTF-16 末尾时返回该末尾 range，允许原选区时返回 nil。
    /// - markedRange 内：放行原选区（返回 nil），越界则约束到组合区末尾。
    /// - proposed 已是 UTF-16 末尾：允许（返回 nil）。
    /// - 否则：返回末尾 range（调用方据此 registerDeny 并应用重定向）。
    static func redirectedSelection(proposed: NSRange, fullLength: Int, markedRange: NSRange?) -> NSRange? {
        if let markedRange {
            if proposed.location >= markedRange.location && NSMaxRange(proposed) <= NSMaxRange(markedRange) {
                return nil
            }
            return NSRange(location: NSMaxRange(markedRange), length: 0)
        }
        let end = NSRange(location: fullLength, length: 0)
        return proposed == end ? nil : end
    }
}
