/**
 * [INPUT]: 依赖 AppState、SessionEngine、Editor bridge 和 DesignSystem token
 * [OUTPUT]: 提供 SessionView 主写作界面
 * [POS]: FirstLine 的核心会话模式，负责 append-only 输入与 danger/failure/success 循环
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

struct SessionView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var pulse = false
    @State private var abandonPromptVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                FirstLineColors.paper
                    .ignoresSafeArea()

                zenMasks

                VStack(spacing: 0) {
                    Spacer(minLength: max(24, proxy.size.height * 0.06))

                    editorStack
                        .frame(maxWidth: 720)

                    Spacer(minLength: max(260, proxy.size.height * 0.38))
                }
                .padding(.horizontal, 48)

                topChrome
            }
            .compositingGroup()
            .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
                appState.handleTick()
            }
            .onAppear {
                pulse = appState.sessionEngine.phase == .danger
            }
            .onChange(of: appState.sessionEngine.phase) { _, phase in
                pulse = phase == .danger
            }
        }
    }

    private var topChrome: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    FirstLineColors.uiLight.opacity(0.4)

                    Rectangle()
                        .fill(timerColor)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 2)
            .opacity(appState.sessionEngine.phase == .danger ? 0.92 : 0.42)

            Text(timerText)
                .font(FirstLineTypography.sessionStatus)
                .foregroundStyle(timerColor)
                .padding(.top, FirstLineSpacing.sm)
                .padding(.trailing, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
    }

    private var editorStack: some View {
        VStack(spacing: FirstLineSpacing.sm) {
            ZStack(alignment: .top) {
                EditorViewRepresentable(
                    engine: appState.sessionEngine
                )
                    .id(appState.sessionEngine.sessionID)
                    .frame(minHeight: 520)
                    .blur(radius: shouldReduceMotion ? 0 : dangerBlurRadius)
                    .animation(.easeInOut(duration: shouldReduceMotion ? 0 : 3), value: appState.sessionEngine.phase)

                if appState.sessionEngine.hasMultipleLines {
                    LinearGradient(
                        stops: [
                            .init(color: FirstLineColors.paper.opacity(0.28), location: 0),
                            .init(color: FirstLineColors.paper.opacity(0.14), location: 0.22),
                            .init(color: FirstLineColors.paper.opacity(0.06), location: 0.46),
                            .init(color: .clear, location: 0.82),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 156)
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                }
            }
            .shadow(color: shadowColor, radius: shouldReduceMotion ? 2 : (pulse ? 18 : 2), y: shouldReduceMotion ? 2 : (pulse ? 8 : 2))
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

            HStack(spacing: FirstLineSpacing.md) {
                Spacer()

                Button("Abandon") {
                    abandonPromptVisible = true
                }
                .buttonStyle(FirstLineSecondaryButtonStyle())
            }
        }
        .alert("Abandon this session?", isPresented: $abandonPromptVisible) {
            Button("Keep Writing", role: .cancel) { }
            Button("Abandon", role: .destructive) {
                appState.abandonSession()
            }
        } message: {
            Text("Current text will be lost.")
        }
    }

    private var zenMasks: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: FirstLineColors.paper, location: 0),
                    .init(color: FirstLineColors.paper.opacity(0.88), location: 0.42),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)

            Spacer()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: FirstLineColors.paper.opacity(0.88), location: 0.52),
                    .init(color: FirstLineColors.paper, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
        }
        .allowsHitTesting(false)
    }

    private var progress: Double {
        guard appState.sessionEngine.duration > 0 else { return 0 }
        return min(max(appState.sessionEngine.elapsed / appState.sessionEngine.duration, 0), 1)
    }

    private var timerColor: Color {
        switch appState.sessionEngine.phase {
        case .danger:
            FirstLineColors.danger
        case .success:
            FirstLineColors.success
        default:
            FirstLineColors.ui
        }
    }

    private var timerText: String {
        let totalSeconds = max(Int(ceil(appState.sessionEngine.remaining)), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var dangerBlurRadius: CGFloat {
        appState.sessionEngine.phase == .danger ? 3 : 0
    }

    private var shouldReduceMotion: Bool {
        switch appState.settings.reducedMotion {
        case .system:
            systemReduceMotion
        case .always:
            true
        case .never:
            false
        }
    }

    private var borderColor: Color {
        appState.sessionEngine.phase == .danger ? FirstLineColors.danger : FirstLineColors.uiLight
    }

    private var shadowColor: Color {
        appState.sessionEngine.phase == .danger
            ? FirstLineColors.danger.opacity(pulse ? 0.16 : 0.05)
            : Color.black.opacity(0.01)
    }
}
