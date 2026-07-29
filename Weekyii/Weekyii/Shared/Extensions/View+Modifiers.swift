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

    /// Keeps long-form content readable on large iPad canvases while leaving
    /// compact layouts edge-to-edge, matching the existing iPhone design.
    func weekReadableContent(
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .top
    ) -> some View {
        modifier(WeekReadableContentModifier(maxWidth: maxWidth, alignment: alignment))
    }

    /// Gives form-style sheets a consistent iPad width without constraining
    /// their existing compact presentation.
    func weekFormWidth() -> some View {
        modifier(WeekFormWidthModifier())
    }
}

private struct WeekReadableContentModifier: ViewModifier {
    @Environment(\.weekLayoutMetrics) private var metrics
    let maxWidth: CGFloat?
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: maxWidth ?? metrics.pageMaxWidth,
                maxHeight: .infinity,
                alignment: alignment
            )
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private struct WeekFormWidthModifier: ViewModifier {
    @Environment(\.weekLayoutMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: metrics.formMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
