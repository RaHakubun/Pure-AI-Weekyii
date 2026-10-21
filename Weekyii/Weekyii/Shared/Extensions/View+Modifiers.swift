import SwiftUI

/// Draws a `ThemeSurfaceSkin`: fill, border (or gradient tube), a hard offset
/// shadow or a soft glow, and the paper "second sheet" under the bottom edge.
/// Every decoration is drawn from the skin alone, so switching theme can never
/// leave a previous theme's border, shadow or sheet behind.
struct ThemedSurfaceModifier: ViewModifier {
    let skin: ThemeSurfaceSkin
    let fallbackFill: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: skin.cornerRadius)
    }

    /// Only blurred shadows go through `.shadow`; a zero-radius shadow is drawn
    /// as a solid offset shape so it stays crisp (brutalist).
    private var glow: ThemeShadowSkin? {
        guard let shadow = skin.shadow, shadow.radius > 0 else { return nil }
        return shadow
    }

    func body(content: Content) -> some View {
        content
            .background(skin.fill?.color ?? fallbackFill)
            .clipShape(shape)
            .overlay { border.allowsHitTesting(false) }
            .background { underlay.allowsHitTesting(false) }
            .shadow(
                color: glow?.color.color ?? .clear,
                radius: glow?.radius ?? 0,
                x: glow?.x ?? 0,
                y: glow?.y ?? 0
            )
    }

    @ViewBuilder
    private var border: some View {
        if let stops = skin.borderGradient, !stops.isEmpty {
            shape.strokeBorder(
                LinearGradient(
                    colors: stops.map { Color(hex: $0) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: skin.borderWidth
            )
        } else if skin.borderWidth > 0 {
            shape.strokeBorder(skin.border.color, lineWidth: skin.borderWidth)
        }
    }

    @ViewBuilder
    private var underlay: some View {
        ZStack {
            if let stack = skin.stackLine {
                // A 1 pt sheet edge, separated from the card by a strip of page colour.
                shape.fill(stack.color).offset(y: 2.5)
                shape.fill(Color.backgroundPrimary).offset(y: 1.5)
            }
            if let shadow = skin.shadow, shadow.radius == 0 {
                shape.fill(shadow.color.color).offset(x: shadow.x, y: shadow.y)
            }
        }
    }
}

private struct WeekyiiCardModifier: ViewModifier {
    @Environment(\.themeSkin) private var skin

    @ViewBuilder
    func body(content: Content) -> some View {
        if let card = skin.card {
            content
                .padding(12)
                .themedSurface(card)
        } else {
            classicBody(content: content)
        }
    }

    /// The original `weekyiiCard()` drawing, unchanged for classic themes.
    private func classicBody(content: Content) -> some View {
        let theme = WeekTheme.activeTheme
        let isPremiumTheme = theme.isPremiumTheme
        let style = theme.visualStyle
        let shadow = style.resolvedShadow

        return content
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
            .clipShape(.rect(cornerRadius: style.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .stroke(
                        // The premium accent border is a deliberate exception that
                        // predates `visualStyle`; keep it so classic themes are unchanged.
                        isPremiumTheme ? Color.weekyiiPrimary.opacity(0.28) : style.resolvedBorderColor,
                        lineWidth: style.borderWidth
                    )
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

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
    /// Frames the view as a theme surface (card, task row, feature panel).
    /// `fallbackFill` is used when the skin keeps the palette's own surface colour.
    func themedSurface(_ skin: ThemeSurfaceSkin, fallbackFill: Color = .backgroundSecondary) -> some View {
        modifier(ThemedSurfaceModifier(skin: skin, fallbackFill: fallbackFill))
    }

    func weekyiiCard() -> some View {
        modifier(WeekyiiCardModifier())
    }

    func refreshOnStateTransitions(using appState: AppState, perform action: @escaping () -> Void) -> some View {
        modifier(StateTransitionRefreshModifier(appState: appState, action: action))
    }
}
