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
        self
            .padding(12)
            .background(Color.backgroundSecondary)
            .clipShape(.rect(cornerRadius: WeekRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: WeekRadius.medium)
                    .stroke(Color.backgroundTertiary, lineWidth: 1)
            )
            .shadow(color: WeekShadow.light.color, radius: WeekShadow.light.radius, x: WeekShadow.light.x, y: WeekShadow.light.y)
    }

    func refreshOnStateTransitions(using appState: AppState, perform action: @escaping () -> Void) -> some View {
        modifier(StateTransitionRefreshModifier(appState: appState, action: action))
    }
}
