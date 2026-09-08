/**
 * [INPUT]: Foundation only
 * [OUTPUT]: SuccessText - pure-logic success-surface text constants and payload builders
 *           (copy-for-AI prompt/payload, Download-.md export file name and markdown front matter)
 * [POS]: Decoupled from SwiftUI/AppKit so AppKit-side rewrite surfaces and tests can consume
 *        the web-canonical cleanup prompt, Copy-for-AI payload and export naming without
 *        importing a View.
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
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

    /// Outward product name recorded in the exported markdown's `source:` front matter.
    static let exportSourceLabel = "Zero Draft"

    /// Default Download-.md save-panel file name: `zero-draft-<timestamp>.md`.
    static func exportFileName(timestamp: String) -> String {
        "zero-draft-\(timestamp).md"
    }

    /// Builds the exported markdown document: front matter (created/source/words) + draft body.
    static func exportMarkdown(created: String, wordCount: Int, body: String) -> String {
        "---\ncreated: \(created)\nsource: \(exportSourceLabel)\nwords: \(wordCount)\n---\n\n\(body)"
    }
}
