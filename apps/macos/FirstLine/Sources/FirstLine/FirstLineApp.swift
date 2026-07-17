/**
 * [INPUT]: 依赖 App/RootView.swift 提供主界面
 * [OUTPUT]: 提供 FirstLineApp SwiftUI 应用入口
 * [POS]: FirstLine macOS 壳子的根入口，负责将持久化设置应用到全局窗口
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import AppKit
import SwiftUI

final class FirstLineAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct FirstLineApp: App {
    @NSApplicationDelegateAdaptor(FirstLineAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(appState.settings.theme.colorScheme)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
                .disabled(appState.canNavigateToSupportSurface == false)
            }

            CommandMenu("Navigate") {
                Button("Writing") {
                    appState.openWritingMode()
                }
                .keyboardShortcut("1", modifiers: [.command])
                .disabled(appState.sessionEngine.phase == .success)

                Button("Home") {
                    appState.goHome()
                }
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(appState.sessionEngine.phase == .success)
            }
        }

        Settings {
            if appState.canNavigateToSupportSurface {
                SettingsView(appState: appState)
                    .preferredColorScheme(appState.settings.theme.colorScheme)
            } else {
                Text("Settings are unavailable during a writing session.")
                    .font(FirstLineTypography.body)
                    .foregroundStyle(FirstLineColors.ui)
                    .padding(FirstLineSpacing.md)
                    .frame(width: 360, height: 160)
                    .preferredColorScheme(appState.settings.theme.colorScheme)
            }
        }
    }
}
