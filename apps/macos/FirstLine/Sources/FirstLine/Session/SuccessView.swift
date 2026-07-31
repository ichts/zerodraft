/**
 * [INPUT]: AppState, SessionEngine, DesignSystem tokens
 * [OUTPUT]: SuccessView result surface; word count in ink, export + discard actions
 * [POS]: Session success surface; shows the draft and offers copy / copy-for-AI / download / discard
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import AppKit
import SwiftUI

struct SuccessView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: FirstLineSpacing.md) {
            Text("\(appState.sessionEngine.wordCount) words")
                .font(FirstLineTypography.title)
                .foregroundStyle(FirstLineColors.ink)

            ScrollView {
                Text(appState.sessionEngine.text)
                    .font(FirstLineTypography.body)
                    .foregroundStyle(FirstLineColors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 320)
            .frame(maxWidth: 640)

            VStack(spacing: FirstLineSpacing.sm) {
                Button("Copy full text") {
                    copyFullText()
                }
                .buttonStyle(FirstLinePrimaryButtonStyle())

                HStack(spacing: FirstLineSpacing.sm) {
                    Button("Copy for AI") {
                        copyForAI()
                    }
                    .buttonStyle(FirstLineSecondaryButtonStyle())

                    Button("Download .md") {
                        downloadMarkdown()
                    }
                    .buttonStyle(FirstLineSecondaryButtonStyle())
                }

                Button("Discard and start next") {
                    appState.abandonSession()
                }
                .buttonStyle(.plain)
                .font(FirstLineTypography.microcopy)
                .foregroundStyle(FirstLineColors.ui)
            }
        }
        .padding(FirstLineSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Export actions

    private func copyFullText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.sessionEngine.text, forType: .string)
    }

    private func copyForAI() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.copyForAIPrompt + appState.sessionEngine.text, forType: .string)
    }

    private func downloadMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "first-line-\(Self.filenameFormatter.string(from: Date())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdownContent().write(to: url, atomically: true, encoding: .utf8)
    }

    private func markdownContent() -> String {
        let created = Self.timestampFormatter.string(from: Date())
        let words = appState.sessionEngine.wordCount
        let body = appState.sessionEngine.text
        return """
        ---
        created: \(created)
        source: First Line
        words: \(words)
        ---

        \(body)
        """
    }

    // Cleanup prompt prefixed to the draft for the user's AI-to-Obsidian workflow.
    private static let copyForAIPrompt =
        "Below is a zero draft - raw, unedited, typos included. Shape it into a clear first draft. " +
        "Keep my ideas and my voice; fix structure, spelling, and flow. Do not add claims I didn\u{2019}t make.\n\n" +
        "---\n\n"

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
