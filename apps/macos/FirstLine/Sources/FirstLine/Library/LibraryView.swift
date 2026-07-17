/**
 * [INPUT]: 依赖 AppState、LibrarySession 和 DesignSystem token
 * [OUTPUT]: 提供 LibraryView 列表与详情界面
 * [POS]: First Line Library surface，负责浏览、查看和删除已保存 session
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import SwiftUI

struct LibraryView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationSplitView {
            Group {
                if appState.librarySessions.isEmpty {
                    VStack(alignment: .leading, spacing: FirstLineSpacing.md) {
                        Text("Library")
                            .font(FirstLineTypography.title)
                        Text("No completed sessions yet.")
                            .font(FirstLineTypography.body)
                            .foregroundStyle(FirstLineColors.ui)
                        Text(AppPaths.libraryDirectory.path)
                            .font(FirstLineTypography.microcopy)
                            .foregroundStyle(FirstLineColors.ui)
                    }
                    .padding(FirstLineSpacing.xl)
                } else {
                    List(appState.librarySessions, selection: Binding(
                        get: { appState.selectedLibrarySession?.id },
                        set: { newValue in
                            guard let id = newValue,
                                  let session = appState.librarySessions.first(where: { $0.id == id }) else { return }
                            appState.selectLibrarySession(session)
                        }
                    )) { session in
                        VStack(alignment: .leading, spacing: FirstLineSpacing.xs) {
                            Text(session.snippet)
                                .font(FirstLineTypography.body)
                                .lineLimit(1)
                            Text(summary(for: session))
                                .font(FirstLineTypography.microcopy)
                                .foregroundStyle(FirstLineColors.ui)
                        }
                        .tag(session.id)
                    }
                    .navigationTitle("Library")
                }
            }
        } detail: {
            if let session = appState.selectedLibrarySession {
                LibraryDetailView(session: session, appState: appState)
            } else {
                VStack(alignment: .leading, spacing: FirstLineSpacing.md) {
                    Text("Library")
                        .font(FirstLineTypography.title)
                    Text("Select a saved session.")
                        .font(FirstLineTypography.body)
                        .foregroundStyle(FirstLineColors.ui)
                }
                .padding(FirstLineSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .alert("Delete session?", isPresented: $appState.deletePromptVisible) {
            Button("Delete", role: .destructive) {
                appState.confirmDelete()
            }

            Button("Cancel", role: .cancel) {
                appState.cancelDelete()
            }
        } message: {
            Text("This removes the markdown file from the library.")
        }
    }

    private func summary(for session: LibrarySession) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: session.completedAt)) · \(session.durationSeconds / 60) min · \(session.wordCount) words"
    }
}

private struct LibraryDetailView: View {
    let session: LibrarySession
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: FirstLineSpacing.md) {
            Text(session.snippet)
                .font(FirstLineTypography.title)

            Text(metadata)
                .font(FirstLineTypography.microcopy)
                .foregroundStyle(FirstLineColors.ui)

            ScrollView {
                Text(session.body)
                    .font(FirstLineTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: FirstLineSpacing.sm) {
                Button("Copy Text") {
                    appState.copyLibrarySessionText(session)
                }
                .buttonStyle(FirstLinePrimaryButtonStyle())

                Menu("More") {
                    Button("Open in Default Editor") {
                        appState.openLibrarySessionInDefaultEditor(session)
                    }
                    Button("Reveal in Finder") {
                        appState.revealLibrarySessionInFinder(session)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        appState.requestDelete(session)
                    }
                }
                .buttonStyle(FirstLineSecondaryButtonStyle())
            }
        }
        .padding(FirstLineSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metadata: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Completed \(formatter.string(from: session.completedAt)) · \(session.durationSeconds / 60) min · \(session.wordCount) words · v\(session.appVersion)"
    }
}
