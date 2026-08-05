/**
 * [INPUT]: AppKit only（NSRange / Selector），无 SwiftUI
 * [OUTPUT]: AppendOnlyInputPolicy - 编辑器 append-only 守卫的单一可测来源
 * [POS]: First Line 编辑器输入策略；封装两块 append-only 守卫逻辑，供 SessionViewController 的
 *        NSTextViewDelegate 与 EditorFocusTests 共用，消除此前 Coordinator/SessionViewController
 *        双份重复。逻辑与原 Coordinator 逐字等价：被屏蔽命令一律 deny；deleteBackward/Forward 在有
 *        marked text 时放行（让 IME 删候选），否则 deny；选区重定向在无 marked text 时强制移到 UTF-16
 *        末尾。
 * [PROTOCOL]: 变更时更新此头部
 *
 * 语义来源（原 EditorViewRepresentable.Coordinator，照搬至 SessionViewController 的同一份逻辑）：
 *   - blockedSelectors: undo / redo: / paste: / cut: / deleteWord* / deleteTo* / yank: / transpose:
 *     -> 一律 registerDeny + return true（吃掉命令）
 *   - deleteSelectors: deleteBackward: / deleteForward: -> hasMarkedText 时 return false（放行给 IME），
 *     否则 registerDeny + return true
 *   - 选区: hasMarkedText 时放行原选区；否则若 proposed 非 UTF-16 末尾就 registerDeny 并重定向到末尾
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

    /// 删除单字符命令（hasMarkedText 时放行给 IME 删候选，否则 deny）。
    static let deleteSelectors: [Selector] = [
        #selector(NSResponder.deleteBackward(_:)),
        #selector(NSResponder.deleteForward(_:)),
    ]

    /// 是否应吞掉该命令（返回 true 表示已处理、阻止默认行为）。
    /// - 对于 blockedSelectors：恒为 true（deny）。
    /// - 对于 deleteSelectors：hasMarkedText 时为 false（放行），否则 true（deny）。
    /// - 其余：false。
    static func shouldDenyCommand(_ selector: Selector, hasMarkedText: Bool) -> Bool {
        if blockedSelectors.contains(selector) {
            return true
        }
        if deleteSelectors.contains(selector) {
            return hasMarkedText == false
        }
        return false
    }

    /// 选区重定向：需要强制到 UTF-16 末尾时返回该末尾 range，允许原选区时返回 nil。
    /// - hasMarkedText：放行原选区（返回 nil）。
    /// - proposed 已是 UTF-16 末尾：允许（返回 nil）。
    /// - 否则：返回末尾 range（调用方据此 registerDeny 并应用重定向）。
    static func redirectedSelection(proposed: NSRange, fullLength: Int, hasMarkedText: Bool) -> NSRange? {
        if hasMarkedText {
            return nil
        }
        let end = NSRange(location: fullLength, length: 0)
        if proposed == end {
            return nil
        }
        return end
    }
}
