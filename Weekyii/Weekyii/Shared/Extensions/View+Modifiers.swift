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
            .background { fillLayer }
            .clipShape(shape)
            .overlay { border.allowsHitTesting(false) }
            .overlay { ornamentLayer.allowsHitTesting(false).accessibilityHidden(true) }
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
        if skin.edges != .all {
            edgeRules
        } else if let stops = skin.borderGradient, !stops.isEmpty {
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

    /// Top / bottom rules for page-block and ledger-row surfaces.
    @ViewBuilder
    private var edgeRules: some View {
        if skin.borderWidth > 0 {
            VStack(spacing: 0) {
                if skin.edges == .horizontalRules {
                    Rectangle().fill(skin.border.color).frame(height: skin.borderWidth)
                }
                Spacer(minLength: 0)
                Rectangle().fill(skin.border.color).frame(height: skin.borderWidth)
            }
        }
    }

    @ViewBuilder
    private var fillLayer: some View {
        ZStack {
            if case .leather(let top, let bottom) = skin.material {
                LinearGradient(colors: [top.color, bottom.color], startPoint: .top, endPoint: .bottom)
                LeatherGrain()
            } else {
                skin.fill?.color ?? fallbackFill
            }
            if let glow = skin.innerGlow {
                RadialGradient(
                    colors: [glow.color.opacity(0.30), glow.color.opacity(0)],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 260
                )
            }
        }
    }

    /// Inner gilded hairline, inset from the surface edge, and/or the tooled
    /// double gilt rule of a bound cover.
    @ViewBuilder
    private var ornamentLayer: some View {
        ZStack {
            if let ornament = skin.ornament {
                let inset: CGFloat = 3.5
                RoundedRectangle(cornerRadius: max(0, skin.cornerRadius - inset))
                    .strokeBorder(ornament.color.opacity(0.22), lineWidth: 0.75)
                    .padding(inset)
            }
            if let tooling = skin.tooling {
                RoundedRectangle(cornerRadius: max(0, skin.cornerRadius - 5))
                    .strokeBorder(tooling.color.opacity(0.85), lineWidth: 0.8)
                    .padding(5)
                RoundedRectangle(cornerRadius: max(0, skin.cornerRadius - 8))
                    .strokeBorder(tooling.color.opacity(0.45), lineWidth: 0.5)
                    .padding(8)
            }
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

/// Fine pore grain for a leather surface: deterministic dark and light specks,
/// so the texture is identical on every redraw.
struct LeatherGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 14)
            for index in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let side = 0.6 + next() * 0.9
                let light = index % 7 == 0
                let alpha = light ? 0.05 + next() * 0.05 : 0.10 + next() * 0.16
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)),
                    with: .color(light ? Color(red: 1, green: 0.85, blue: 0.7).opacity(alpha) : Color.black.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Four L-shaped brackets hugging the corners of a rect, with rounded elbows.
/// Kept as a reusable shape even though no surface draws it today: 魔戒's corner
/// brackets were removed, and this is the piece to re-attach if they come back.
struct CornerBracketsShape: Shape {
    var inset: CGFloat
    var arm: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > arm * 2, r.height > arm * 2 else { return path }
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: r.minX, y: r.minY), 1, 1),
            (CGPoint(x: r.maxX, y: r.minY), -1, 1),
            (CGPoint(x: r.minX, y: r.maxY), 1, -1),
            (CGPoint(x: r.maxX, y: r.maxY), -1, -1)
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * radius))
            path.addQuadCurve(
                to: CGPoint(x: corner.x + dx * radius, y: corner.y),
                control: corner
            )
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
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

/// The large month panel shared by 过去 and 未来. Classic themes keep the 24 pt
/// radius, 0.75 pt hairline and soft 14 pt shadow; personalised skins draw it as
/// their card.
private struct WeekPageSurfaceModifier: ViewModifier {
    @Environment(\.themeSkin) private var skin

    @ViewBuilder
    func body(content: Content) -> some View {
        if let card = skin.card {
            content.themedSurface(card)
        } else {
            content
                .background(Color.backgroundSecondary)
                .clipShape(.rect(cornerRadius: WeekRadius.xlarge))
                .overlay {
                    RoundedRectangle(cornerRadius: WeekRadius.xlarge, style: .continuous)
                        .stroke(Color.backgroundTertiary.opacity(0.55), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
                .shadow(color: WeekShadow.light.color, radius: 14, x: 0, y: 5)
        }
    }
}

/// A decorative soft shadow that follows `ThemeSkin.softShadows`. The shadow is
/// always applied (with a clear colour when off) so the view keeps its identity
/// across a theme switch.
private struct WeekSoftShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    @Environment(\.themeSkin) private var skin

    func body(content: Content) -> some View {
        content.shadow(
            color: skin.softShadows ? color : .clear,
            radius: skin.softShadows ? radius : 0,
            x: skin.softShadows ? x : 0,
            y: skin.softShadows ? y : 0
        )
    }
}

/// Full-screen texture for skins that have one (paper fibres, CRT scanlines,
/// a drafting grid): drawn above the content so every page and the tab bar get
/// it without any page knowing. Draws nothing for `.none`.
struct ThemeBackdropOverlay: View {
    let backdrop: ThemeBackdrop

    var body: some View {
        switch backdrop {
        case .none:
            EmptyView()
        case .paperGrain(let ink):
            lines(ink)
        case .scanlines(let ink):
            lines(ink)
        case .draftingGrid(let ink):
            draftingGrid(ink)
        case .vellum(let fibre, let vignette, let topLight):
            vellum(fibre: fibre, vignette: vignette, topLight: topLight)
        }
    }

    /// Short scattered fibres, a darkened edge and a warm light from the top.
    /// The fibres come from a fixed seed, so the sheet never shimmers.
    private func vellum(fibre: ThemeHexPair, vignette: ThemeHexPair, topLight: ThemeHexPair) -> some View {
        let fibreColor = fibre.color
        return GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, canvas in
                    var seed: UInt64 = 0x2545F4914F6CDD1D
                    func next() -> CGFloat {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        return CGFloat((seed >> 33) % 10_000) / 10_000
                    }
                    let count = Int(canvas.width * canvas.height / 240)
                    for _ in 0..<count {
                        let x = next() * canvas.width
                        let y = next() * canvas.height
                        let length = 3 + next() * 7
                        let angle = (next() - 0.5) * 0.45
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                        context.stroke(path, with: .color(fibreColor.opacity(0.35 + next() * 0.65)), lineWidth: 0.5)
                    }
                }
                RadialGradient(
                    colors: [topLight.color, topLight.color.opacity(0)],
                    center: .top,
                    startRadius: 0,
                    endRadius: max(1, size.height * 0.55)
                )
                RadialGradient(
                    colors: [vignette.color.opacity(0), vignette.color],
                    center: .center,
                    startRadius: min(size.width, size.height) * 0.5,
                    endRadius: max(size.width, size.height) * 0.75
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lines(_ ink: ThemeHexPair) -> some View {
        let color = ink.color
        return Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color))
                y += 3
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A 10 pt minor square with a heavier 50 pt major every fifth line, so the
    /// page reads as graph paper rather than a ruled list.
    private func draftingGrid(_ ink: ThemeHexPair) -> some View {
        let color = ink.color
        return Canvas { context, size in
            for x in stride(from: CGFloat.zero, through: size.width, by: 10) {
                let major = Int((x / 10).rounded()) % 5 == 0
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                    with: .color(color.opacity(major ? 1 : 0.45))
                )
            }
            for y in stride(from: CGFloat.zero, through: size.height, by: 10) {
                let major = Int((y / 10).rounded()) % 5 == 0
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(color.opacity(major ? 1 : 0.45))
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    func weekPageSurface() -> some View {
        modifier(WeekPageSurfaceModifier())
    }

    /// Drop-in for `.shadow(color:radius:x:y:)` on decorative shadows. Classic
    /// themes render exactly the same shadow; flat personalised skins drop it.
    func weekSoftShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(WeekSoftShadowModifier(color: color, radius: radius, x: x, y: y))
    }

    func refreshOnStateTransitions(using appState: AppState, perform action: @escaping () -> Void) -> some View {
        modifier(StateTransitionRefreshModifier(appState: appState, action: action))
    }
}

extension View {
    /// Grouped `Form` / `List` screens (Settings). Personalised skins drop the
    /// system grey and let the theme's page show through; classic themes are
    /// left exactly as they were.
    func themedGroupedList() -> some View {
        modifier(ThemedGroupedListModifier())
    }

    /// Row fill for grouped lists. Apply to the rows' container (a `Group` of
    /// sections); `nil` on classic themes keeps the system cell background.
    func themedListRows() -> some View {
        modifier(ThemedListRowsModifier())
    }
}

private struct ThemedGroupedListModifier: ViewModifier {
    @Environment(\.themeSkin) private var skin

    func body(content: Content) -> some View {
        let skinned = skin.card != nil
        content
            .scrollContentBackground(skinned ? .hidden : .automatic)
            .background(skinned ? Color.backgroundPrimary.ignoresSafeArea() : Color.clear.ignoresSafeArea())
    }
}

private struct ThemedListRowsModifier: ViewModifier {
    @Environment(\.themeSkin) private var skin

    func body(content: Content) -> some View {
        content.listRowBackground(skin.card != nil ? Color.backgroundSecondary : nil)
    }
}
