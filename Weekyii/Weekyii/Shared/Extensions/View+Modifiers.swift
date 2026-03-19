import SwiftUI

private struct StateTransitionRefreshModifier: ViewModifier {
    @ObservedObject var appState: AppState
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: appState.stateTransitionRevision) { _, _ in
            action()
        }
    }
}

extension View {
    func weekyiiCard() -> some View {
        let isPremiumTheme = WeekTheme.activeTheme.isPremiumTheme

        return self
            .padding(12)
            .background {
                ZStack {
                    Color.backgroundSecondary

                    if isPremiumTheme {
                        LinearGradient(
                            colors: [
                                Color.weekyiiPrimary.opacity(0.12),
                                Color.clear,
                                Color.accentOrange.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.screen)

                        RadialGradient(
                            colors: [
                                Color.weekyiiPrimary.opacity(0.10),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 180
                        )
                        .blendMode(.screen)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(
                        isPremiumTheme ? Color.weekyiiPrimary.opacity(0.28) : Color.backgroundTertiary,
                        lineWidth: 1
                    )
            )
            .shadow(color: WeekShadow.light.color, radius: WeekShadow.light.radius, x: WeekShadow.light.x, y: WeekShadow.light.y)
    }

    func refreshOnStateTransitions(using appState: AppState, perform action: @escaping () -> Void) -> some View {
        modifier(StateTransitionRefreshModifier(appState: appState, action: action))
    }
}
