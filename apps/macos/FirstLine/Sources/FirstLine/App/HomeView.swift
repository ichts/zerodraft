/**
 * [INPUT]: AppState and DesignSystem tokens
 * [OUTPUT]: HomeView launch gate; fixed 60s session, no duration picker, durable wipe aftermath
 * [POS]: FirstLine Home surface; explains the rules, shows trial status, starts a session,
 *        and carries the durable red wipe line + one margin fossil until the next session.
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import SwiftUI

struct HomeView: View {
    @Bindable var appState: AppState

    // Session length is fixed at 60 seconds; there is no duration picker.
    private let sessionDuration: TimeInterval = 60

    var body: some View {
        ZStack {
            // One faint fossil of the most recently lost draft, dead in the margin.
            if let fossil = appState.lastWipeFossil {
                Text(fossil)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FirstLineColors.ink.opacity(0.12))
                    .rotationEffect(.degrees(-3))
                    .frame(width: 200, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 28)
                    .padding(.bottom, 40)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: FirstLineSpacing.md) {
                VStack(spacing: FirstLineSpacing.sm) {
                    Text("First Line")
                        .font(FirstLineTypography.title)
                        .foregroundStyle(FirstLineColors.ink)

                    Text("The first draft only moves forward.")
                        .font(FirstLineTypography.tagline)
                        .foregroundStyle(FirstLineColors.ui)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: FirstLineSpacing.xs) {
                    Text("Stop for 8 seconds and the page clears.")
                        .font(FirstLineTypography.body)
                        .foregroundStyle(FirstLineColors.ink)

                    Text("No delete. No paste. No undo.")
                        .font(FirstLineTypography.microcopy)
                        .foregroundStyle(FirstLineColors.ui)
                }
                .multilineTextAlignment(.center)

                Text(appState.trialStatusText)
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(appState.isTrialExhausted ? FirstLineColors.ink : FirstLineColors.ui)

                if appState.lastWipeFossil != nil {
                    Text("Draft deleted. it joined the pile.")
                        .font(FirstLineTypography.sessionStatus)
                        .foregroundStyle(FirstLineColors.danger)
                }

                Button("Give it sixty seconds.") {
                    appState.startSession(duration: sessionDuration)
                }
                .buttonStyle(FirstLinePrimaryButtonStyle())
            }
            .padding(FirstLineSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
