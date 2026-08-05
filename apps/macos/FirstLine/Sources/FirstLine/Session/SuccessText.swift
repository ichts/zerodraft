/**
 * [INPUT]: Foundation only
 * [OUTPUT]: SuccessText - pure-logic success-surface text constants and payload builders
 * [POS]: Decoupled from SwiftUI/AppKit so AppKit-side rewrite surfaces and tests can consume
 *        the web-canonical cleanup prompt and Copy-for-AI payload without importing a View.
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * Extracted verbatim from SuccessView so the canonical prompt string and join/trim semantics
 * have a single source of truth shared by the SwiftUI SuccessView (today) and the AppKit
 * SuccessViewController (rewrite), and by SuccessSurfaceTests.
 */

import Foundation

enum SuccessText {
    /// Web-canonical cleanup prompt (kept verbatim from index.html AI_CLEANUP_PROMPT).
    static let copyForAIPrompt =
        "Below is my raw freewriting draft. Organize it into clear notes. " +
        "Keep my original wording where possible. List any tasks or open questions separately at the end. " +
        "Do not add ideas that are not in the draft."

    /// Builds the Copy-for-AI clipboard payload: prompt + separator + trimmed draft,
    /// matching the web's `copyForAI` join format.
    static func copyForAIPayload(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return copyForAIPrompt + "\n\n---\n\n" + trimmed
    }
}
