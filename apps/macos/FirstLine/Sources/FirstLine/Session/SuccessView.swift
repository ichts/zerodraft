/**
 * [INPUT]: AppState, SessionEngine, DesignSystem tokens
 * [OUTPUT]: SuccessView result surface; word count in ink, export + discard actions
 * [POS]: Session success surface; shows the draft and offers copy / copy-for-AI / download / discard.
 *        Copy feedback is an ink label swap, the primary Copy button takes focus on appear, and
 *        Copy for AI uses the web-canonical cleanup prompt with the prompt + separator + draft join.
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import AppKit
import SwiftUI

struct SuccessView: View {
    @Bindable var appState: AppState

    @FocusState private var copyButtonFocused: Bool
    @State private var copiedFlash: CopiedAction?
    @State private var copiedResetTask: Task<Void, Never>?

    private enum CopiedAction: Equatable {
        case fullText
        case forAI
    }

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
                Button(copyFullTextLabel) {
                    copyFullText()
                }
                .buttonStyle(FirstLinePrimaryButtonStyle())
                .focused($copyButtonFocused)

                HStack(spacing: FirstLineSpacing.sm) {
                    Button(copyForAILabel) {
                        copyForAI()
                    }
                    .buttonStyle(FirstLineSecondaryButtonStyle())

                    Button("Download .md") {
                        downloadMarkdown()
                    }
                    .buttonStyle(FirstLineSecondaryButtonStyle())
                }

                Button("Discard") {
                    appState.abandonSession()
                }
                .buttonStyle(.plain)
                .font(FirstLineTypography.microcopy)
                .foregroundStyle(FirstLineColors.ui)
            }
        }
        .padding(FirstLineSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            // Keyboard-first: land focus on the primary Copy full text button.
            copyButtonFocused = true
        }
    }

    // MARK: - Copy labels

    private var copyFullTextLabel: String {
        copiedFlash == .fullText ? "Copied." : "Copy full text"
    }

    private var copyForAILabel: String {
        copiedFlash == .forAI ? "Copied." : "Copy for AI"
    }

    private func flashCopied(_ action: CopiedAction) {
        copiedFlash = action
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled == false { copiedFlash = nil }
        }
    }

    // MARK: - Export actions

    private func copyFullText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.sessionEngine.text, forType: .string)
        flashCopied(.fullText)
    }

    private func copyForAI() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.copyForAIPayload(for: appState.sessionEngine.text), forType: .string)
        flashCopied(.forAI)
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

    // MARK: - Copy-for-AI (forwarded to SuccessText, the pure-logic source of truth)

    /// Web-canonical cleanup prompt. See `SuccessText.copyForAIPrompt`.
    static var copyForAIPrompt: String { SuccessText.copyForAIPrompt }

    /// Copy-for-AI payload. See `SuccessText.copyForAIPayload(for:)`.
    static func copyForAIPayload(for text: String) -> String {
        SuccessText.copyForAIPayload(for: text)
    }

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
