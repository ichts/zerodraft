/**
 * [INPUT]: 依赖 AppState、SessionEngine、Editor bridge 和 DesignSystem token
 * [OUTPUT]: 提供 SessionView 主写作界面，包含 Flood bone ground、静态 fossil 层、paper 列、danger veil、倒计时、narrator strip 与 deny 反馈
 * [POS]: FirstLine 的核心会话模式，负责 append-only 输入与 danger/failure/success 循环
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

struct SessionView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var denyFlashActive = false
    @State private var denyResetTask: Task<Void, Never>?
    @State private var denyShakeOffset: CGFloat = 0
    @State private var denyHairlineActive = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Flood soul: bone canvas ground, paper is bounded to the writing column.
                FirstLineColors.canvas
                    .ignoresSafeArea()

                FossilLayer(
                    isDanger: isDanger,
                    paperColumnWidth: 720,
                    reducesMotion: shouldReduceMotion
                )
                .ignoresSafeArea()

                Group {
                    if isDanger {
                        FirstLineColors.danger
                            .opacity(0.07)
                            .ignoresSafeArea()
                    }
                }
                .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.3), value: isDanger)

                VStack(spacing: 0) {
                    Spacer(minLength: max(24, proxy.size.height * 0.06))

                    paperColumn

                    Spacer(minLength: max(260, proxy.size.height * 0.38))
                }
                .padding(.horizontal, 48)

                Group {
                    if isDanger {
                        countdownCluster
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.62)
                    }
                }
                .animation(shouldReduceMotion ? nil : .easeOut(duration: 0.18), value: isDanger)

                if appState.sessionEngine.phase == .failure, fossilText.isEmpty == false {
                    Text(fossilText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(FirstLineColors.ink)
                        .opacity(0.14)
                        .rotationEffect(.degrees(3))
                        .frame(width: 220)
                        .position(x: proxy.size.width - 150, y: proxy.size.height * 0.5)
                        .allowsHitTesting(false)
                }

                topChrome

                narratorStrip
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .compositingGroup()
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                appState.handleTick()
            }
            .onChange(of: appState.sessionEngine.lastDenyAt) { _, newValue in
                guard newValue != nil else { return }
                denyFlashActive = true
                denyResetTask?.cancel()
                denyResetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if Task.isCancelled == false { denyFlashActive = false }
                }
                triggerDenyFeedback()
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

            HStack(spacing: FirstLineSpacing.sm) {
                if canFinish {
                    Button("Finish") {
                        appState.sessionEngine.finish()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .font(FirstLineTypography.buttonLabel)
                    .foregroundStyle(FirstLineColors.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FirstLineColors.uiLight, lineWidth: 1)
                    )
                }

                Text(timerText)
                    .font(FirstLineTypography.sessionStatus)
                    .foregroundStyle(timerColor)
            }
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
                    .transition(shouldReduceMotion ? .identity : .opacity.animation(.easeInOut(duration: 0.18)))
                }

                if appState.sessionEngine.phase == .failure {
                    Rectangle()
                        .fill(FirstLineColors.danger)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                }
            }

        }
    }

    /// The clean white paper: the editor column bounded to maxWidth 720, sitting on
    /// the bone canvas. White is the surface of the paper only, not the window.
    private var paperColumn: some View {
        editorStack
            .frame(maxWidth: 720)
            .frame(minHeight: 520)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(FirstLineColors.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FirstLineColors.faint.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: FirstLineColors.ink.opacity(0.06), radius: 24, x: 0, y: 12)
            // Deny feedback: a 2px horizontal shake of the paper, suppressed under reduced motion.
            .offset(x: denyShakeOffset)
            // Deny feedback: a red hairline that flashes on the paper border for ~90ms.
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FirstLineColors.danger, lineWidth: 1)
                    .opacity(denyHairlineActive ? 1 : 0)
            )
    }

    private func triggerDenyFeedback() {
        // The red hairline is a color/opacity flash; it is allowed under reduced motion.
        denyHairlineActive = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            denyHairlineActive = false
        }

        guard shouldReduceMotion == false else { return }
        // 2px horizontal shake for ~160ms: -2 -> +2 -> 0.
        let half = 0.08
        denyShakeOffset = -2
        withAnimation(.easeInOut(duration: half)) { denyShakeOffset = 2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + half) {
            withAnimation(.easeInOut(duration: half)) { denyShakeOffset = 0 }
        }
    }

    private var countdownCluster: some View {
        VStack(spacing: FirstLineSpacing.xs) {
            Text("\(appState.sessionEngine.secondsUntilDeletion)")
                .font(.system(size: 104, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(FirstLineColors.danger)

            Text("keep typing or the draft is deleted")
                .font(FirstLineTypography.sessionStatus)
                .textCase(.uppercase)
                .foregroundStyle(FirstLineColors.ui)
        }
        .allowsHitTesting(false)
    }

    private var narratorStrip: some View {
        HStack(spacing: FirstLineSpacing.sm) {
            Text(narratorText)
                .font(FirstLineTypography.sessionStatus)
                .textCase(.uppercase)
                .foregroundStyle(narratorColor)
                .allowsHitTesting(false)

            Spacer()

            if isSessionLive {
                Button("Abandon - the text is lost") {
                    appState.abandonSession()
                }
                .buttonStyle(.plain)
                .font(FirstLineTypography.sessionStatus)
                .foregroundStyle(FirstLineColors.danger)
            }

            Text("\(appState.sessionEngine.wordCount) words")
                .font(FirstLineTypography.sessionStatus)
                .foregroundStyle(FirstLineColors.ui)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, FirstLineSpacing.xs)
    }

    private var narratorText: String {
        if denyFlashActive {
            return "no going back."
        }
        switch appState.sessionEngine.phase {
        case .failure:
            return "draft deleted. it joined the pile."
        case .danger:
            return "keep typing or the draft is deleted"
        default:
            return "forward only. don't stop."
        }
    }

    private var narratorColor: Color {
        if denyFlashActive {
            return FirstLineColors.danger
        }
        return appState.sessionEngine.phase == .failure ? FirstLineColors.danger : FirstLineColors.ui
    }

    private var fossilText: String {
        let collapsed = appState.sessionEngine.wipedText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return String(collapsed.prefix(64))
    }

    private var isDanger: Bool {
        appState.sessionEngine.phase == .danger
    }

    private var isSessionLive: Bool {
        appState.sessionEngine.phase == .writing || appState.sessionEngine.phase == .danger
    }

    private var canFinish: Bool {
        isSessionLive && appState.sessionEngine.wordCount > 0
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
}
