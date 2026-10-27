import SwiftUI

enum ThemeStatusArtworkRenderingMode: Equatable {
    case animated
    case staticImage
}

/// A single entry point for the framed narrative artwork shown in Today status cards.
/// Business state stays in `TodayView`; this file owns theme-specific visual storytelling only.
struct ThemeStatusArtwork: View {
    let theme: WeekTheme
    let renderingMode: ThemeStatusArtworkRenderingMode

    init(theme: WeekTheme, renderingMode: ThemeStatusArtworkRenderingMode = .animated) {
        self.theme = theme
        self.renderingMode = renderingMode
    }

    var body: some View {
        Group {
            switch theme {
            case .sunset:
                SunsetStatusIllustration(renderingMode: renderingMode)
            case .lotr:
                LotrStatusIllustration(renderingMode: renderingMode)
            case .amber, .ocean, .forest, .rose, .lavender, .graphite, .mint, .midnight:
                NarrativeThemeStatusIllustration(theme: theme, renderingMode: renderingMode)
            case .brutal, .neon, .paper, .terminal, .blueprint:
                GeometricStatusIllustration(theme: theme, renderingMode: renderingMode)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Clips the status artwork and draws its frame. Classic themes keep the given
    /// rounded clip (plus the 20 % white hairline when `hairline` is set); a
    /// personalised skin frames it like its own cards instead.
    func themeArtworkFrame(cornerRadius: CGFloat, hairline: Bool = true) -> some View {
        modifier(ThemeArtworkFrameModifier(cornerRadius: cornerRadius, hairline: hairline))
    }
}

private struct ThemeArtworkFrameModifier: ViewModifier {
    let cornerRadius: CGFloat
    let hairline: Bool
    @Environment(\.themeSkin) private var skin

    @ViewBuilder
    func body(content: Content) -> some View {
        if let card = skin.card {
            let shape = RoundedRectangle(cornerRadius: min(cornerRadius, max(0, card.cornerRadius - 4)), style: .continuous)
            content
                .clipShape(shape)
                .overlay(shape.strokeBorder(card.border.color, lineWidth: min(card.borderWidth, 2.5)))
        } else if hairline {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                )
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct NarrativeThemeStatusIllustration: View {
    let theme: WeekTheme
    let renderingMode: ThemeStatusArtworkRenderingMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        renderingMode == .animated && !reduceMotion
    }

    @ViewBuilder
    var body: some View {
        if shouldAnimate {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                GeometryReader { proxy in
                    scene(size: proxy.size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        } else {
            GeometryReader { proxy in
                scene(size: proxy.size, time: 0)
            }
        }
    }

    @ViewBuilder
    private func scene(size: CGSize, time: TimeInterval) -> some View {
        switch theme {
        case .amber:
            AmberWindowScene(size: size, time: time)
        case .ocean:
            OceanSailScene(size: size, time: time)
        case .forest:
            ForestPathScene(size: size, time: time)
        case .rose:
            RoseGardenScene(size: size, time: time)
        case .lavender:
            LavenderFieldScene(size: size, time: time)
        case .graphite:
            GraphiteRidgeScene(size: size, time: time)
        case .mint:
            MintGreenhouseScene(size: size, time: time)
        case .midnight:
            MidnightAuroraScene(size: size, time: time)
        case .sunset, .lotr, .brutal, .neon, .paper, .terminal, .blueprint:
            Color.clear
        }
    }
}

// MARK: - Personalised theme artwork

/// Abstract artwork for the four personalised themes.
///
/// Each theme owns a different visual grammar rather than reusing one shape
/// set with a different palette: brutalism is flat and overprinted, neon is a
/// glowing signal field, paper is a layered print, and terminal is a compact
/// phosphor interface.
private struct ThemeArtworkPalette {
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let backgroundTertiary: Color
    let primary: Color
    let primaryLight: Color
    let accent: Color
    let accentLight: Color
    let textPrimary: Color
    let textSecondary: Color

    init(theme: WeekTheme, isDark: Bool) {
        let palette = theme.palette(for: .system, systemIsDark: isDark)
        backgroundPrimary = Color(hex: palette.backgroundPrimary)
        backgroundSecondary = Color(hex: palette.backgroundSecondary)
        backgroundTertiary = Color(hex: palette.backgroundTertiary)
        primary = Color(hex: palette.primary)
        primaryLight = Color(hex: palette.primaryLight)
        accent = Color(hex: palette.accentOrange)
        accentLight = Color(hex: palette.accentOrangeLight)
        textPrimary = Color(hex: palette.textPrimary)
        textSecondary = Color(hex: palette.textSecondary)
    }
}

private struct GeometricStatusIllustration: View {
    let theme: WeekTheme
    let renderingMode: ThemeStatusArtworkRenderingMode

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        renderingMode == .animated && !reduceMotion
    }

    @ViewBuilder
    var body: some View {
        if shouldAnimate {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                scene(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            scene(time: 0)
        }
    }

    @ViewBuilder
    private func scene(time: TimeInterval) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let palette = ThemeArtworkPalette(theme: theme, isDark: colorScheme == .dark)

            switch theme {
            case .brutal:
                BrutalStatusScene(size: size, time: time, palette: palette)
            case .neon:
                NeonStatusScene(size: size, time: time, palette: palette)
            case .paper:
                PaperStatusScene(size: size, time: time, palette: palette)
            case .terminal:
                TerminalStatusScene(size: size, time: time, palette: palette)
            case .blueprint:
                DraftingStatusScene(size: size, time: time, palette: palette)
            default:
                Color.clear
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Personalised theme scenes
//
// The four personalised scenes are drawn on a 260 × 88 design grid (the Today
// status card). Positions and flat bands stretch with the frame; round and square
// shapes use the smaller scale so they never turn into ovals in taller frames
// (Settings 112 pt, About 168 pt).

private struct ArtworkGrid {
    let size: CGSize

    var sx: CGFloat { size.width / 260 }
    var sy: CGFloat { size.height / 88 }
    /// Scale for shapes that must keep their proportions.
    var s: CGFloat { min(sx, sy) }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * sx, y: y * sy)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * sx, y: y * sy, width: width * sx, height: height * sy)
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, radius: CGFloat) -> Path {
        let center = point(cx, cy)
        let r = radius * s
        return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }
}

/// Neo-brutalist poster: flat primaries with heavy ink outlines and a print
/// registration wobble.
private struct BrutalStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = Color(hex: colorScheme == .dark ? "#F2F2F2" : "#111111")
        let shift = CGFloat(sin(time * 0.72)) * 1.5

        Canvas { context, canvas in
            let grid = ArtworkGrid(size: canvas)
            let line = 3 * grid.s

            context.fill(Path(grid.bounds), with: .color(palette.backgroundSecondary))

            let block = Path(grid.rect(18, 14, 74, 56).offsetBy(dx: shift, dy: 0))
            context.fill(block, with: .color(palette.primary))
            context.stroke(block, with: .color(ink), lineWidth: line)

            let sun = grid.circle(132, 38, radius: 22)
            context.fill(sun, with: .color(Color(hex: "#FFD43B")))
            context.stroke(sun, with: .color(ink), lineWidth: line)

            let side = 44 * grid.s
            let center = grid.point(192, 52)
            let square = Path(CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                .applying(
                    CGAffineTransform(rotationAngle: 8 * .pi / 180)
                        .concatenating(CGAffineTransform(translationX: center.x, y: center.y - shift))
                )
            context.fill(square, with: .color(palette.accent))
            context.stroke(square, with: .color(ink), lineWidth: line)

            context.fill(Path(grid.rect(18, 76, 224, 5)), with: .color(ink))

            var corner = Path()
            corner.move(to: grid.point(228, 12))
            corner.addLine(to: grid.point(244, 12))
            corner.addLine(to: CGPoint(x: 244 * grid.sx, y: 12 * grid.sy + 16 * grid.s))
            context.stroke(corner, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Synthwave horizon: a striped sun sinking behind a glowing horizon, with a
/// perspective grid rolling towards the viewer. Always a night sky, like a
/// lit sign, in both appearances.
private struct NeonStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    var body: some View {
        let night = Color(hex: "#0A0E1A")
        let magenta = Color(hex: "#FF4DA6")
        let cyan = Color(hex: "#00F0FF")
        let roll = CGFloat((time * 0.35).truncatingRemainder(dividingBy: 1))

        Canvas { context, canvas in
            let grid = ArtworkGrid(size: canvas)
            let horizon = 58 * grid.sy

            context.fill(Path(grid.bounds), with: .color(night))

            let sun = grid.circle(130, 44, radius: 30)
            context.opacity = 0.9
            context.fill(
                sun,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#FFE45C"), magenta]),
                    startPoint: grid.point(130, 44 - 30 * grid.s / grid.sy),
                    endPoint: grid.point(130, 44 + 30 * grid.s / grid.sy)
                )
            )
            context.opacity = 1

            // Bands cut out of the lower half of the sun.
            let sunCenter = grid.point(130, 44)
            for band in 0..<4 {
                let y = (40 + CGFloat(band) * 5) * grid.sy
                let height = (1.6 + CGFloat(band) * 0.5) * grid.sy
                let halfWidth = 34 * grid.s
                context.fill(
                    Path(CGRect(x: sunCenter.x - halfWidth, y: y, width: halfWidth * 2, height: height)),
                    with: .color(night)
                )
            }

            context.fill(Path(CGRect(x: 0, y: horizon, width: canvas.width, height: canvas.height - horizon)), with: .color(night))

            // Horizontal grid lines spread out quadratically and roll forward.
            for index in 0..<6 {
                let depth = CGFloat(index) + roll
                let y = horizon + depth * depth * 2.2 * grid.sy
                guard y <= canvas.height else { continue }
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: y))
                gridLine.addLine(to: CGPoint(x: canvas.width, y: y))
                let opacity = min(0.65, 0.25 + Double(depth) * 0.1)
                context.stroke(gridLine, with: .color(magenta.opacity(opacity)), lineWidth: 1)
            }

            for ray in -4...4 {
                var rayPath = Path()
                rayPath.move(to: grid.point(130, 58))
                rayPath.addLine(to: CGPoint(x: (130 + CGFloat(ray) * 46) * grid.sx, y: canvas.height))
                context.stroke(rayPath, with: .color(magenta.opacity(0.45)), lineWidth: 1)
            }

            var horizonLine = Path()
            horizonLine.move(to: CGPoint(x: 0, y: horizon))
            horizonLine.addLine(to: CGPoint(x: canvas.width, y: horizon))
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 2.2 * grid.s))
                glow.stroke(horizonLine, with: .color(cyan), lineWidth: 3 * grid.s)
            }
            context.stroke(horizonLine, with: .color(Color(hex: "#E8FDFF")), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Cut-paper landscape: three layered hills, each casting a thin shadow on the
/// sheet behind it, under a red paper sun.
private struct PaperStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let drift = CGFloat(sin(time * 0.40)) * 1.2
        let layers: [(Color, [CGFloat])] = [
            (Color(hex: "#D9AE72"), [0, 60, 40, 40, 70, 48, 110, 36, 150, 24, 190, 40, 260, 30]),
            (Color(hex: "#4A6C58"), [0, 70, 50, 52, 90, 64, 140, 50, 180, 40, 220, 58, 260, 52]),
            (Color(hex: "#B23A2E"), [0, 80, 60, 68, 110, 78, 160, 66, 200, 58, 230, 70, 260, 66])
        ]
        let sheetShadow = Color(hex: "#3A2A1A").opacity(colorScheme == .dark ? 0.30 : 0.16)

        Canvas { context, canvas in
            let grid = ArtworkGrid(size: canvas)

            context.fill(Path(grid.bounds), with: .color(palette.backgroundTertiary))

            let sun = grid.circle(196, 30, radius: 14).offsetBy(dx: 0, dy: drift)
            context.fill(sun, with: .color(Color(hex: "#B23A2E").opacity(0.85)))

            for (color, v) in layers {
                // M x0 y0  C c1 c2 p1  C c3 c4 p2  V 88  H 0  Z
                var hill = Path()
                hill.move(to: grid.point(v[0], v[1]))
                hill.addCurve(to: grid.point(v[6], v[7]), control1: grid.point(v[2], v[3]), control2: grid.point(v[4], v[5]))
                hill.addCurve(to: grid.point(v[12], v[13]), control1: grid.point(v[8], v[9]), control2: grid.point(v[10], v[11]))
                hill.addLine(to: CGPoint(x: canvas.width, y: canvas.height))
                hill.addLine(to: CGPoint(x: 0, y: canvas.height))
                hill.closeSubpath()

                context.fill(hill.offsetBy(dx: 0, dy: -1.2 * grid.sy), with: .color(sheetShadow))
                context.fill(hill, with: .color(color))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Phosphor console: a boot banner, an indeterminate progress sweep and a
/// blinking block cursor on a black screen with CRT scanlines. It shows no
/// numbers on purpose: the artwork has no access to the day's real progress.
private struct TerminalStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    private static let cells = 16
    private static let sweep = 5

    var body: some View {
        let grid = ArtworkGrid(size: size)
        let phosphor = Color(hex: "#33FF66")
        let text = Color(hex: "#8CFFA8")
        let dim = Color(hex: "#4E7A5C")
        let fontSize = max(9, 10.5 * grid.s)
        let step = Int(time * 6)
        let head = step % (Self.cells + Self.sweep) - Self.sweep
        let cursorOn = (Int(time / 0.6) % 2) == 0

        ZStack(alignment: .topLeading) {
            Color(hex: "#05100A")

            VStack(alignment: .leading, spacing: fontSize * 0.55) {
                Text(verbatim: "WEEKYII") + Text(verbatim: " · ").foregroundColor(dim) + Text(verbatim: "TODAY")
                progressLine(head: head, bright: phosphor, dim: dim)
                HStack(spacing: 3) {
                    Text(verbatim: "> ready")
                    Rectangle()
                        .fill(phosphor)
                        .frame(width: fontSize * 0.66, height: fontSize * 1.2)
                        .shadow(color: phosphor.opacity(0.8), radius: 3)
                        .opacity(cursorOn ? 1 : 0)
                }
            }
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundColor(text)
            .padding(.horizontal, 10 * grid.s)
            .padding(.vertical, 8 * grid.s)

            Canvas { context, canvas in
                var y: CGFloat = 0
                while y < canvas.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: canvas.width, height: 1)), with: .color(phosphor.opacity(0.05)))
                    y += 3
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func progressLine(head: Int, bright: Color, dim: Color) -> Text {
        var line = Text(verbatim: "[")
        for cell in 0..<Self.cells {
            let isLit = cell >= head && cell < head + Self.sweep
            line = line + Text(verbatim: isLit ? "█" : "░").foregroundColor(isLit ? bright : dim)
        }
        return line + Text(verbatim: "]")
    }
}

/// Drafting sheet: a floor plan in hairlines, a door leaf swinging to its stop,
/// an architect's dimension rule and a title block. Flat ink, no elevation, one
/// construction-orange marker. It shows no numbers: the artwork has no access to
/// the day's real progress.
private struct DraftingStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    var body: some View {
        let grid = ArtworkGrid(size: size)
        let ink = palette.primary
        let soft = palette.primaryLight
        let marker = palette.accent
        let rule = palette.textSecondary
        let swing = CGFloat((sin(time * 0.45 - Double.pi / 2) + 1) / 2)
        let leafAngle = -CGFloat.pi / 2 - swing * CGFloat.pi / 2
        let labelSize = max(5, 6.5 * grid.s)

        ZStack(alignment: .topLeading) {
            Canvas { context, canvas in
                let grid = ArtworkGrid(size: canvas)
                let thin = max(0.6, 1 * grid.s)
                let wall = max(1.1, 1.5 * grid.s)

                context.fill(Path(grid.bounds), with: .color(palette.backgroundSecondary))

                // Sheet grid: 10-unit cells, a heavier rule every fifth.
                var minor = Path()
                for x in stride(from: CGFloat.zero, through: 260, by: 10) {
                    minor.addRect(grid.rect(x, 0, 0.5, 88))
                }
                for y in stride(from: CGFloat.zero, through: 88, by: 10) {
                    minor.addRect(grid.rect(0, y, 260, 0.5))
                }
                context.fill(minor, with: .color(soft.opacity(0.16)))

                var major = Path()
                for x in stride(from: CGFloat.zero, through: 260, by: 50) {
                    major.addRect(grid.rect(x, 0, 1, 88))
                }
                for y in stride(from: CGFloat.zero, through: 88, by: 50) {
                    major.addRect(grid.rect(0, y, 260, 1))
                }
                context.fill(major, with: .color(soft.opacity(0.3)))

                // Plan: an outer wall, a partition with a door opening, a window.
                var walls = Path()
                walls.addRect(grid.rect(22, 14, 96, 54))
                walls.move(to: grid.point(68, 14))
                walls.addLine(to: grid.point(68, 38))
                walls.move(to: grid.point(68, 52))
                walls.addLine(to: grid.point(68, 68))
                walls.move(to: grid.point(68, 44))
                walls.addLine(to: grid.point(118, 44))
                context.stroke(
                    walls,
                    with: .color(ink),
                    style: StrokeStyle(lineWidth: wall, lineCap: .square, lineJoin: .miter)
                )

                var window = Path()
                window.move(to: grid.point(34, 17.5))
                window.addLine(to: grid.point(58, 17.5))
                window.move(to: grid.point(34, 14))
                window.addLine(to: grid.point(34, 17.5))
                window.move(to: grid.point(58, 14))
                window.addLine(to: grid.point(58, 17.5))
                context.stroke(window, with: .color(soft), lineWidth: thin)

                // Door: the arc is the drawn geometry, the leaf sweeps to its stop.
                let hinge = grid.point(68, 52)
                let radius = 14 * grid.s
                var arc = Path()
                arc.addArc(
                    center: hinge,
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false
                )
                context.stroke(arc, with: .color(soft.opacity(0.7)), lineWidth: thin)

                let tip = CGPoint(
                    x: hinge.x + cos(leafAngle) * radius,
                    y: hinge.y + sin(leafAngle) * radius
                )
                var leaf = Path()
                leaf.move(to: hinge)
                leaf.addLine(to: tip)
                context.stroke(leaf, with: .color(marker), style: StrokeStyle(lineWidth: wall, lineCap: .square))
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: tip.x - 1.6 * grid.s,
                        y: tip.y - 1.6 * grid.s,
                        width: 3.2 * grid.s,
                        height: 3.2 * grid.s
                    )),
                    with: .color(marker)
                )

                var centerMark = Path()
                centerMark.move(to: CGPoint(x: hinge.x - 3 * grid.s, y: hinge.y))
                centerMark.addLine(to: CGPoint(x: hinge.x + 3 * grid.s, y: hinge.y))
                centerMark.move(to: CGPoint(x: hinge.x, y: hinge.y - 3 * grid.s))
                centerMark.addLine(to: CGPoint(x: hinge.x, y: hinge.y + 3 * grid.s))
                context.stroke(centerMark, with: .color(rule.opacity(0.6)), lineWidth: thin)

                // Dimension rule with slash ticks under the plan.
                var dimension = Path()
                dimension.move(to: grid.point(22, 76))
                dimension.addLine(to: grid.point(118, 76))
                dimension.move(to: grid.point(22, 68))
                dimension.addLine(to: grid.point(22, 79))
                dimension.move(to: grid.point(118, 68))
                dimension.addLine(to: grid.point(118, 79))
                context.stroke(
                    dimension,
                    with: .color(rule.opacity(0.55)),
                    style: StrokeStyle(lineWidth: thin, lineCap: .square)
                )

                var ticks = Path()
                for x in [CGFloat(22), CGFloat(118)] {
                    ticks.move(to: grid.point(x - 2, 78))
                    ticks.addLine(to: grid.point(x + 2, 74))
                }
                context.stroke(
                    ticks,
                    with: .color(marker),
                    style: StrokeStyle(lineWidth: max(1, 1.4 * grid.s), lineCap: .square)
                )

                // Detail callout and title block.
                var leader = Path()
                leader.move(to: grid.point(187, 30))
                leader.addLine(to: grid.point(124, 30))
                leader.move(to: grid.point(124, 30))
                leader.addLine(to: grid.point(124, 34))
                context.stroke(
                    leader,
                    with: .color(rule.opacity(0.8)),
                    style: StrokeStyle(lineWidth: thin, lineCap: .square)
                )
                context.stroke(grid.circle(196, 30, radius: 9), with: .color(ink), lineWidth: thin)
                context.fill(grid.circle(124, 30, radius: 1.4), with: .color(marker))

                let callout = context.resolve(
                    Text(verbatim: "A")
                        .font(.system(size: max(6, 8 * grid.s), weight: .semibold, design: .monospaced))
                        .foregroundColor(ink)
                )
                context.draw(callout, at: grid.point(196, 30), anchor: .center)

                var block = Path()
                block.addRect(grid.rect(176, 62, 70, 20))
                block.move(to: grid.point(176, 72))
                block.addLine(to: grid.point(246, 72))
                block.move(to: grid.point(212, 72))
                block.addLine(to: grid.point(212, 82))
                context.stroke(block, with: .color(soft.opacity(0.85)), lineWidth: thin)
            }
            .frame(width: size.width, height: size.height)

            Text(verbatim: "WEEKYII")
                .tracking(1.4)
                .frame(width: 64 * grid.sx, alignment: .leading)
                .position(x: 211 * grid.sx, y: 67 * grid.sy)
            Text(verbatim: "PLAN 01")
                .frame(width: 32 * grid.sx, alignment: .leading)
                .position(x: 196 * grid.sx, y: 77 * grid.sy)
            Text(verbatim: "1:100")
                .frame(width: 32 * grid.sx, alignment: .leading)
                .position(x: 231 * grid.sx, y: 77 * grid.sy)
        }
        .font(.system(size: labelSize, weight: .medium, design: .monospaced))
        .foregroundColor(rule)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct AmberWindowScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pulse = CGFloat((sin(time * 0.72) + 1) * 0.5)
        let flameSway = CGFloat(sin(time * 1.35)) * 3.4
        let windowX = size.width * 0.67
        let deskY = size.height * 0.70

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#21150D"), Color(hex: "#3A2412"), Color(hex: "#5A3516")]
                    : [Color(hex: "#F8D9A4"), Color(hex: "#E9A95C"), Color(hex: "#C9752D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 44, bottomLeading: 2, bottomTrailing: 2, topTrailing: 44),
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#D8953D").opacity(0.72), Color(hex: "#7C451B").opacity(0.45)]
                        : [Color(hex: "#FFF1C4"), Color(hex: "#E8B55F")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size.width * 0.29, height: size.height * 0.76)
            .position(x: windowX, y: size.height * 0.43)

            Path { path in
                path.move(to: CGPoint(x: windowX, y: size.height * 0.08))
                path.addLine(to: CGPoint(x: windowX, y: size.height * 0.68))
                path.move(to: CGPoint(x: windowX - size.width * 0.14, y: size.height * 0.39))
                path.addLine(to: CGPoint(x: windowX + size.width * 0.14, y: size.height * 0.39))
            }
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.30), lineWidth: 1)

            Rectangle()
                .fill(Color(hex: colorScheme == .dark ? "#17110D" : "#8A512A").opacity(colorScheme == .dark ? 0.92 : 0.62))
                .frame(height: size.height * 0.31)
                .position(x: size.width / 2, y: size.height * 0.89)

            Circle()
                .fill(Color(hex: "#FFBE62").opacity(0.12 + Double(pulse) * 0.16))
                .frame(width: 52 + pulse * 8, height: 52 + pulse * 8)
                .blur(radius: 9)
                .position(x: size.width * 0.34 + flameSway * 0.35, y: deskY - size.height * 0.27)

            Capsule()
                .fill(Color(hex: colorScheme == .dark ? "#F3B65E" : "#FFF0B2").opacity(0.72 + Double(pulse) * 0.24))
                .frame(width: 8, height: 15 + pulse * 5)
                .rotationEffect(.degrees(Double(flameSway) * 1.8))
                .position(x: size.width * 0.34 + flameSway, y: deskY - size.height * 0.27)

            Path { path in
                path.move(to: CGPoint(x: size.width * 0.27, y: deskY))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.41, y: deskY),
                    control: CGPoint(x: size.width * 0.34, y: deskY - size.height * 0.22)
                )
                path.move(to: CGPoint(x: size.width * 0.20, y: deskY + 2))
                path.addLine(to: CGPoint(x: size.width * 0.47, y: deskY + 2))
            }
            .stroke(Color(hex: colorScheme == .dark ? "#E1A353" : "#6E3A1E"), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.54))
                .frame(width: size.width * 0.20, height: 3)
                .rotationEffect(.degrees(-3))
                .position(x: size.width * 0.52, y: deskY + 4)
        }
    }
}

private struct OceanSailScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let horizonY = size.height * 0.52
        let sailX = size.width * 0.382
        let boatBob = CGFloat(sin(time * 0.92)) * 3.5
        let boatTilt = sin(time * 0.58) * 2.2

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#071A2B"), Color(hex: "#12344F"), Color(hex: "#245778")]
                    : [Color(hex: "#CDEEFF"), Color(hex: "#82C5E5"), Color(hex: "#4E96BF")],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(hex: "#123B59"), Color(hex: "#061927")]
                            : [Color(hex: "#4A9EC4"), Color(hex: "#176C99")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: size.height * 0.51)
                .position(x: size.width / 2, y: size.height * 0.76)

            Canvas { context, canvas in
                for index in 0..<7 {
                    let progress = CGFloat(index) / 6
                    let y = horizonY + 6 + CGFloat(index) * max((canvas.height - horizonY - 8) / 7, 4)
                    let phase = time * 0.55 + Double(index) * 0.74
                    let drift = CGFloat(sin(phase)) * (5 + progress * 3)
                    var path = Path()
                    path.move(to: CGPoint(x: canvas.width * 0.06 + drift, y: y))
                    path.addQuadCurve(
                        to: CGPoint(x: canvas.width * 0.94 - drift, y: y),
                        control: CGPoint(x: canvas.width * 0.50, y: y + CGFloat(cos(phase)) * 4.2)
                    )
                    context.stroke(
                        path,
                        with: .color(Color.white.opacity(colorScheme == .dark ? 0.09 : 0.23 - Double(progress) * 0.08)),
                        style: StrokeStyle(lineWidth: max(0.6, 1.4 - progress * 0.5), lineCap: .round)
                    )
                }
            }

            Path { path in
                path.move(to: CGPoint(x: sailX, y: horizonY - 26))
                path.addLine(to: CGPoint(x: sailX, y: horizonY + 2))
                path.addLine(to: CGPoint(x: sailX - 19, y: horizonY + 1))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(colorScheme == .dark ? 0.78 : 0.94))
            .offset(y: boatBob)
            .rotationEffect(.degrees(boatTilt), anchor: .bottom)

            Path { path in
                path.move(to: CGPoint(x: sailX - 23, y: horizonY + 3))
                path.addQuadCurve(
                    to: CGPoint(x: sailX + 17, y: horizonY + 3),
                    control: CGPoint(x: sailX - 3, y: horizonY + 11)
                )
            }
            .stroke(Color(hex: colorScheme == .dark ? "#B9DCEC" : "#174E70"), lineWidth: 2)
            .offset(y: boatBob)
            .rotationEffect(.degrees(boatTilt), anchor: .center)
        }
    }
}

private struct ForestPathScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let mistOffset = CGFloat(sin(time * 0.24)) * 14
        let horizonY = size.height * 0.55

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#0E2017"), Color(hex: "#1D3B2A"), Color(hex: "#345B3E")]
                    : [Color(hex: "#D8F0DC"), Color(hex: "#9DC9A4"), Color(hex: "#5A9368")],
                startPoint: .top,
                endPoint: .bottom
            )

            ForestTreeLayer(size: size, baseline: horizonY + 8, tint: Color(hex: colorScheme == .dark ? "#274936" : "#4F8660"), scale: 0.72, offsetX: mistOffset * 0.75)
                .opacity(colorScheme == .dark ? 0.72 : 0.66)
            ForestTreeLayer(size: size, baseline: horizonY + 23, tint: Color(hex: colorScheme == .dark ? "#112A1D" : "#2F6544"), scale: 1.0, offsetX: -mistOffset * 0.28)

            Path { path in
                path.move(to: CGPoint(x: size.width * 0.44, y: horizonY + 3))
                path.addLine(to: CGPoint(x: size.width * 0.22, y: size.height + 8))
                path.addLine(to: CGPoint(x: size.width * 0.68, y: size.height + 8))
                path.addLine(to: CGPoint(x: size.width * 0.48, y: horizonY + 3))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#A0A67D").opacity(0.38), Color(hex: "#4D4B35").opacity(0.62)]
                        : [Color(hex: "#E5D7AA").opacity(0.76), Color(hex: "#A88A54").opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.18))
                .frame(width: size.width * 0.72, height: 14)
                .blur(radius: 5)
                .offset(x: mistOffset, y: -4)
        }
    }
}

private struct ForestTreeLayer: View {
    let size: CGSize
    let baseline: CGFloat
    let tint: Color
    let scale: CGFloat
    let offsetX: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let count = 15
            for index in 0..<count {
                let x = CGFloat(index) / CGFloat(count - 1) * canvas.width + offsetX
                let height = (22 + CGFloat((index * 13) % 25)) * scale
                var path = Path()
                path.move(to: CGPoint(x: x, y: baseline - height))
                path.addLine(to: CGPoint(x: x - height * 0.28, y: baseline))
                path.addLine(to: CGPoint(x: x + height * 0.28, y: baseline))
                path.closeSubpath()
                context.fill(path, with: .color(tint))
            }
        }
    }
}

private struct RoseGardenScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let breeze = CGFloat(sin(time * 0.68)) * 7

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#28131E"), Color(hex: "#54243B"), Color(hex: "#7A3652")]
                    : [Color(hex: "#FFE1EA"), Color(hex: "#EFA5B9"), Color(hex: "#C96583")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, canvas in
                let centers = [
                    CGPoint(x: canvas.width * 0.72, y: canvas.height * 0.72),
                    CGPoint(x: canvas.width * 0.86, y: canvas.height * 0.64),
                    CGPoint(x: canvas.width * 0.58, y: canvas.height * 0.82)
                ]
                for (clusterIndex, center) in centers.enumerated() {
                    for petalIndex in 0..<5 {
                        let angle = Double(petalIndex) / 5 * Double.pi * 2 + Double(clusterIndex) * 0.22
                        let dx = CGFloat(cos(angle)) * 13
                        let dy = CGFloat(sin(angle)) * 8
                        let rect = CGRect(x: center.x + dx - 11, y: center.y + dy - 6, width: 22, height: 12)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color(hex: colorScheme == .dark ? "#C66A89" : "#F5CAD5").opacity(0.36 + Double(petalIndex) * 0.05))
                        )
                    }
                }

                var stem = Path()
                stem.move(to: CGPoint(x: canvas.width * 0.24, y: canvas.height))
                stem.addQuadCurve(
                    to: CGPoint(x: canvas.width * 0.36, y: canvas.height * 0.32),
                    control: CGPoint(x: canvas.width * 0.22, y: canvas.height * 0.56)
                )
                context.stroke(stem, with: .color(Color(hex: colorScheme == .dark ? "#8E6D78" : "#8F5368").opacity(0.7)), lineWidth: 2)

                for index in 0..<6 {
                    let progress = CGFloat(
                        (time * 0.12 + Double(index) * 0.19)
                            .truncatingRemainder(dividingBy: 1.0)
                    )
                    let baseX = canvas.width * (0.18 + CGFloat((index * 17) % 61) / 100)
                    let flutter = CGFloat(sin(time * 1.25 + Double(index) * 0.9)) * 11
                    let petal = CGRect(
                        x: baseX + flutter + progress * 16,
                        y: canvas.height * (0.08 + progress * 0.86),
                        width: 9,
                        height: 5
                    )
                    context.fill(
                        Path(ellipseIn: petal),
                        with: .color(Color(hex: colorScheme == .dark ? "#F0ADC1" : "#FFF0F4").opacity(0.58 + Double(index % 3) * 0.12))
                    )
                }
            }

            Capsule()
                .fill(Color(hex: colorScheme == .dark ? "#E2A6B9" : "#FFF2F5").opacity(0.72))
                .frame(width: 18, height: 9)
                .rotationEffect(.degrees(-24 + Double(breeze)))
                .position(x: size.width * 0.38 + breeze, y: size.height * 0.32 - breeze * 0.25)

            Rectangle()
                .fill(Color(hex: colorScheme == .dark ? "#170C12" : "#8E3F59").opacity(colorScheme == .dark ? 0.42 : 0.18))
                .frame(height: size.height * 0.18)
                .position(x: size.width / 2, y: size.height * 0.94)
        }
    }
}

private struct LavenderFieldScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let horizonY = size.height * 0.48

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#171225"), Color(hex: "#39284F"), Color(hex: "#67457D")]
                    : [Color(hex: "#ECE2F7"), Color(hex: "#C7A8DB"), Color(hex: "#9871B1")],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(hex: colorScheme == .dark ? "#E4DCF1" : "#FFF7DF").opacity(colorScheme == .dark ? 0.72 : 0.88))
                .frame(width: 28, height: 28)
                .position(x: size.width * 0.72, y: size.height * 0.25)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(hex: "#4F3765"), Color(hex: "#20182D")]
                            : [Color(hex: "#9670AD"), Color(hex: "#5F4776")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: size.height * 0.54)
                .position(x: size.width / 2, y: size.height * 0.76)

            Canvas { context, canvas in
                let vanishing = CGPoint(x: canvas.width * 0.42, y: horizonY)
                for index in 0..<9 {
                    let bottomX = CGFloat(index) / 8 * canvas.width
                    let rowSway = CGFloat(sin(time * 0.82 + Double(index) * 0.48)) * 6
                    var row = Path()
                    row.move(to: vanishing)
                    row.addQuadCurve(
                        to: CGPoint(x: bottomX + rowSway, y: canvas.height + 2),
                        control: CGPoint(x: (vanishing.x + bottomX) * 0.5 + rowSway * 0.35, y: canvas.height * 0.73)
                    )
                    context.stroke(
                        row,
                        with: .color(Color(hex: colorScheme == .dark ? "#A786BF" : "#D8BCE9").opacity(0.38)),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                }
                for index in 0..<22 {
                    let x = CGFloat((index * 47) % 101) / 100 * canvas.width
                    let y = horizonY + CGFloat((index * 29) % 47) / 47 * (canvas.height - horizonY)
                    let flowerSway = CGFloat(sin(time * 0.82 + Double(index) * 0.31)) * 5
                    let rect = CGRect(x: x + flowerSway, y: y, width: 2.8, height: 7)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(Color(hex: "#D8B6EA").opacity(0.56)))
                }
            }
        }
    }
}

private struct GraphiteRidgeScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shift = CGFloat(sin(time * 0.34)) * 4
        let pulse = CGFloat((sin(time * 1.2) + 1) * 0.5)

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#101215"), Color(hex: "#252A30"), Color(hex: "#3C424A")]
                    : [Color(hex: "#F0F1F3"), Color(hex: "#CDD0D5"), Color(hex: "#A5AAB1")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, canvas in
                let ridgeY = canvas.height * 0.62
                var back = Path()
                back.move(to: CGPoint(x: -10, y: canvas.height))
                back.addLine(to: CGPoint(x: -10, y: ridgeY + 8))
                back.addLine(to: CGPoint(x: canvas.width * 0.22 + shift, y: ridgeY - 22))
                back.addLine(to: CGPoint(x: canvas.width * 0.43 + shift, y: ridgeY + 1))
                back.addLine(to: CGPoint(x: canvas.width * 0.67 + shift, y: ridgeY - 30))
                back.addLine(to: CGPoint(x: canvas.width + 10, y: ridgeY + 9))
                back.addLine(to: CGPoint(x: canvas.width + 10, y: canvas.height))
                back.closeSubpath()
                context.fill(back, with: .color(Color.black.opacity(colorScheme == .dark ? 0.50 : 0.22)))

                for index in 0..<18 {
                    let x = CGFloat(index) / 17 * canvas.width
                    var hatch = Path()
                    hatch.move(to: CGPoint(x: x, y: ridgeY + 3))
                    hatch.addLine(to: CGPoint(x: x + 22, y: canvas.height))
                    context.stroke(hatch, with: .color(Color.white.opacity(colorScheme == .dark ? 0.055 : 0.20)), lineWidth: 0.8)
                }

                var route = Path()
                route.move(to: CGPoint(x: canvas.width * 0.18, y: canvas.height + 2))
                route.addQuadCurve(
                    to: CGPoint(x: canvas.width * 0.382, y: ridgeY - 2),
                    control: CGPoint(x: canvas.width * 0.34, y: canvas.height * 0.77)
                )
                context.stroke(
                    route,
                    with: .color(Color(hex: colorScheme == .dark ? "#C0C6CD" : "#626A73").opacity(0.78)),
                    style: StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [6, 5], dashPhase: -CGFloat(time * 8))
                )
            }

            Circle()
                .fill(Color(hex: colorScheme == .dark ? "#E6AD72" : "#C87938"))
                .frame(width: 8 + pulse * 4, height: 8 + pulse * 4)
                .shadow(color: Color(hex: "#E6AD72").opacity(0.35 + Double(pulse) * 0.35), radius: 4 + pulse * 3)
                .position(x: size.width * 0.382 + shift, y: size.height * 0.59)
        }
    }
}

private struct MintGreenhouseScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let sway = CGFloat(sin(time * 0.72)) * 5.5
        let dropletTravel = CGFloat((time * 0.32).truncatingRemainder(dividingBy: 1.0))
        let rippleProgress = max(0, (dropletTravel - 0.82) / 0.18)
        let rippleOpacity = rippleProgress > 0 ? 1 - rippleProgress : 0
        let glassX = size.width * 0.43

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#071D1A"), Color(hex: "#123A34"), Color(hex: "#2F7467")]
                    : [Color(hex: "#ECFFF9"), Color(hex: "#B8EBDD"), Color(hex: "#68BDAA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // The arched conservatory window gives the scene a recognisable silhouette.
            Path { path in
                path.move(to: CGPoint(x: size.width * 0.08, y: size.height + 2))
                path.addLine(to: CGPoint(x: size.width * 0.08, y: size.height * 0.58))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.92, y: size.height * 0.58),
                    control: CGPoint(x: size.width * 0.50, y: -size.height * 0.30)
                )
                path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height + 2))
            }
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.48), lineWidth: 1.2)

            Path { path in
                path.move(to: CGPoint(x: size.width * 0.50, y: size.height * 0.08))
                path.addLine(to: CGPoint(x: size.width * 0.50, y: size.height))
                path.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.44))
                path.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.44))
            }
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.26), lineWidth: 0.8)

            // A translucent drinking glass anchors the composition.
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 3, bottomLeading: 10, bottomTrailing: 10, topTrailing: 3),
                style: .continuous
            )
            .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28))
            .overlay {
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 3, bottomLeading: 10, bottomTrailing: 10, topTrailing: 3),
                    style: .continuous
                )
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.38 : 0.72), lineWidth: 1)
            }
            .frame(width: 52, height: 47)
            .position(x: glassX, y: size.height * 0.76)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: colorScheme == .dark ? "#4DB69C" : "#77CEB8").opacity(0.30))
                .frame(width: 45, height: 21)
                .position(x: glassX, y: size.height * 0.83)

            Path { path in
                path.move(to: CGPoint(x: glassX, y: size.height * 0.72))
                path.addQuadCurve(
                    to: CGPoint(x: glassX + sway, y: size.height * 0.22),
                    control: CGPoint(x: glassX - 9, y: size.height * 0.48)
                )
                path.move(to: CGPoint(x: glassX - 5, y: size.height * 0.63))
                path.addQuadCurve(
                    to: CGPoint(x: glassX - 31 + sway, y: size.height * 0.40),
                    control: CGPoint(x: glassX - 18, y: size.height * 0.52)
                )
                path.move(to: CGPoint(x: glassX - 2, y: size.height * 0.52))
                path.addQuadCurve(
                    to: CGPoint(x: glassX + 32 + sway, y: size.height * 0.34),
                    control: CGPoint(x: glassX + 17, y: size.height * 0.45)
                )
            }
            .stroke(Color(hex: colorScheme == .dark ? "#87D8C1" : "#237E69"), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            mintLeaf(width: 35, height: 17, rotation: -25, colorScheme: colorScheme)
                .position(x: glassX - 29 + sway, y: size.height * 0.39)
            mintLeaf(width: 39, height: 18, rotation: 22, colorScheme: colorScheme)
                .position(x: glassX + 31 + sway, y: size.height * 0.33)
            mintLeaf(width: 31, height: 15, rotation: -8, colorScheme: colorScheme)
                .position(x: glassX + sway, y: size.height * 0.23)

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.82 : 0.94))
                .frame(width: 7, height: 9)
                .overlay(Circle().stroke(Color(hex: "#A7F3DE").opacity(0.70), lineWidth: 0.8))
                .position(
                    x: glassX + 42,
                    y: size.height * 0.24 + dropletTravel * size.height * 0.58
                )

            Ellipse()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.52), lineWidth: 1)
                .frame(width: 24 + rippleProgress * 22, height: 5 + rippleProgress * 5)
                .position(x: glassX + 3, y: size.height * 0.82)
                .opacity(Double(rippleOpacity))
        }
    }

    private func mintLeaf(width: CGFloat, height: CGFloat, rotation: Double, colorScheme: ColorScheme) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#A1E8D2"), Color(hex: "#38957E")]
                        : [Color(hex: "#C9F7E9"), Color(hex: "#2D9B7F")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.7))
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
    }
}

private struct MidnightAuroraScene: View {
    let size: CGSize
    let time: TimeInterval

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let drift = CGFloat(sin(time * 0.28)) * 14
        let horizonY = size.height * 0.68

        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#030812"), Color(hex: "#0B1A35"), Color(hex: "#16345B")]
                    : [Color(hex: "#DCE8FF"), Color(hex: "#9DB9E8"), Color(hex: "#557BB5")],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, canvas in
                for index in 0..<11 {
                    let x = CGFloat((index * 37) % 101) / 100 * canvas.width
                    let y = CGFloat((index * 19) % 47) / 47 * canvas.height * 0.52
                    let radius: CGFloat = index % 3 == 0 ? 1.4 : 0.8
                    let twinkle = 0.34 + (sin(time * 1.3 + Double(index) * 0.8) + 1) * 0.20
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(Color.white.opacity(colorScheme == .dark ? twinkle : twinkle * 0.72))
                    )
                }

                for band in 0..<3 {
                    let y = canvas.height * (0.24 + CGFloat(band) * 0.10)
                    let wave = CGFloat(sin(time * 0.64 + Double(band) * 0.9)) * 10
                    var path = Path()
                    path.move(to: CGPoint(x: -20 + drift * CGFloat(band + 1) * 0.35, y: y))
                    path.addCurve(
                        to: CGPoint(x: canvas.width + 20 + drift, y: y + 5 - wave * 0.25),
                        control1: CGPoint(x: canvas.width * 0.28, y: y - 14 - CGFloat(band) * 2 + wave),
                        control2: CGPoint(x: canvas.width * 0.70, y: y + 18 - wave)
                    )
                    let tint = band == 1 ? Color(hex: "#7AA8DE") : Color(hex: "#74BFAE")
                    let glow = (sin(time * 0.74 + Double(band)) + 1) * 0.05
                    context.stroke(
                        path,
                        with: .color(tint.opacity((colorScheme == .dark ? 0.28 : 0.21) + glow)),
                        style: StrokeStyle(lineWidth: 9 - CGFloat(band) * 1.6, lineCap: .round)
                    )
                }
            }
            .blur(radius: 0.8)

            Circle()
                .fill(Color(hex: colorScheme == .dark ? "#E6EEFF" : "#FFF9E7").opacity(0.84))
                .frame(width: 24, height: 24)
                .position(x: size.width * 0.72, y: size.height * 0.25)

            Path { path in
                path.move(to: CGPoint(x: -10, y: size.height + 4))
                path.addLine(to: CGPoint(x: -10, y: horizonY + 4))
                path.addLine(to: CGPoint(x: size.width * 0.24, y: horizonY - 14))
                path.addLine(to: CGPoint(x: size.width * 0.43, y: horizonY + 2))
                path.addLine(to: CGPoint(x: size.width * 0.68, y: horizonY - 18))
                path.addLine(to: CGPoint(x: size.width + 10, y: horizonY + 6))
                path.addLine(to: CGPoint(x: size.width + 10, y: size.height + 4))
                path.closeSubpath()
            }
            .fill(Color(hex: colorScheme == .dark ? "#050B14" : "#36527C").opacity(colorScheme == .dark ? 0.90 : 0.62))

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: size.height * 0.28)
                .position(x: size.width / 2, y: size.height * 0.88)
        }
    }
}

// Existing Sunset composition, moved out of TodayView without changing its visual language.
private struct SunsetStatusIllustration: View {
    let renderingMode: ThemeStatusArtworkRenderingMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    private var shouldAnimate: Bool {
        renderingMode == .animated && !reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sunX = size.width * 0.382
            let sunY = size.height * 0.31 + (drift ? 3.2 : -3.2)
            let horizonY = size.height * 0.58

            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "#3E201E"), Color(hex: "#562922"), Color(hex: "#6A2F27")]
                        : [Color(hex: "#F8D0BA"), Color(hex: "#F19F79"), Color(hex: "#E0715D")],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "#1D2937" : "#8FB2CA"),
                                Color(hex: colorScheme == .dark ? "#111C2A" : "#5E88A6")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: size.height * 0.42)
                    .offset(y: horizonY)

                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.24))
                    .frame(height: 1.0)
                    .position(x: size.width * 0.5, y: horizonY)

                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 2, bottomTrailing: 0, topTrailing: 0))
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16))
                    .frame(width: size.width * 0.34, height: size.height * 0.22)
                    .position(x: size.width * 0.84, y: horizonY - 2)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12))
                            .frame(width: size.width * 0.20, height: 1)
                            .offset(x: -10, y: 0)
                    }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "#F46A5F" : "#EE5A4E"),
                                Color(hex: colorScheme == .dark ? "#D8473F" : "#C63B35")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.26), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .scaleEffect(0.68)
                            .offset(y: -8)
                    )
                    .frame(width: 52, height: 52)
                    .position(x: sunX, y: sunY)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#F36A5D").opacity(colorScheme == .dark ? 0.46 : 0.54),
                                Color(hex: "#D64A42").opacity(colorScheme == .dark ? 0.34 : 0.42),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 64, height: size.height * 0.52)
                    .scaleEffect(x: 1.05, y: 1.0, anchor: .top)
                    .position(x: sunX + 12, y: size.height * 0.77)

                stylizedRipples(size: size, horizonY: horizonY, sunX: sunX)
            }
            .onAppear {
                guard shouldAnimate else { return }
                withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
        }
    }

    @ViewBuilder
    private func stylizedRipples(size: CGSize, horizonY: CGFloat, sunX: CGFloat) -> some View {
        if shouldAnimate {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                rippleCanvas(time: timeline.date.timeIntervalSinceReferenceDate, horizonY: horizonY, sunX: sunX)
            }
        } else {
            rippleCanvas(time: 0, horizonY: horizonY, sunX: sunX)
        }
    }

    private func rippleCanvas(time: TimeInterval, horizonY: CGFloat, sunX: CGFloat) -> some View {
        Canvas { context, canvasSize in
                let t = time
                let bandCount = 8
                let verticalStep = max((canvasSize.height - horizonY) / CGFloat(bandCount + 1), 6.0)

                for index in 0..<bandCount {
                    let progress = CGFloat(index) / CGFloat(max(bandCount - 1, 1))
                    let y = horizonY + CGFloat(index + 1) * verticalStep + CGFloat(index % 2 == 0 ? -1.5 : 0.8)
                    let width = canvasSize.width * (0.14 + progress * 0.44)
                    let wobble = CGFloat(sin(t * 0.68 + Double(index) * 0.95)) * 4.8
                    let centerX = sunX + 10 + wobble + CGFloat(index) * 0.7
                    let height = max(0.9, 1.8 - progress * 0.9)
                    let alpha = max(0.07, 0.34 - Double(progress) * 0.20)
                    let rect = CGRect(x: centerX - width / 2, y: y, width: width, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: height)
                    context.fill(path, with: .color(Color(hex: "#FFD2AE").opacity(alpha)))
                    context.stroke(path, with: .color(Color.white.opacity(alpha * 0.42)), lineWidth: 0.45)
                }
        }
        .blendMode(.screen)
    }
}

// A no-green Middle-earth impression built around weathered gold, volcanic rock and embers.
private struct LotrStatusIllustration: View {
    let renderingMode: ThemeStatusArtworkRenderingMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var shouldAnimate: Bool {
        renderingMode == .animated && !reduceMotion
    }

    @ViewBuilder
    var body: some View {
        if shouldAnimate {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                GeometryReader { proxy in
                    scene(size: proxy.size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        } else {
            GeometryReader { proxy in
                scene(size: proxy.size, time: 0)
            }
        }
    }

    private func scene(size: CGSize, time: TimeInterval) -> some View {
        let glint = CGFloat((sin(time * 0.65) + 1) * 0.5)
        let ringX = size.width * 0.32
        let ringY = size.height * 0.48

        return ZStack {
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(hex: "#090909"), Color(hex: "#231512"), Color(hex: "#4B1E15")]
                            : [Color(hex: "#EBDDBF"), Color(hex: "#C9A47A"), Color(hex: "#7A4A30")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color(hex: "#D94A2E").opacity(colorScheme == .dark ? 0.24 : 0.18))
                        .frame(width: 78, height: 78)
                        .blur(radius: 12)
                        .position(x: size.width * 0.76, y: size.height * 0.48)

                    // A distant volcanic ridge replaces the previous anonymous mountain line.
                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.43, y: size.height + 4))
                        path.addLine(to: CGPoint(x: size.width * 0.59, y: size.height * 0.64))
                        path.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.46))
                        path.addLine(to: CGPoint(x: size.width * 0.73, y: size.height * 0.35))
                        path.addLine(to: CGPoint(x: size.width * 0.79, y: size.height * 0.47))
                        path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.69))
                        path.addLine(to: CGPoint(x: size.width + 8, y: size.height + 4))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: colorScheme == .dark ? "#08090A" : "#3F332B").opacity(0.94))

                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.75, y: size.height * 0.42))
                        path.addCurve(
                            to: CGPoint(x: size.width * 0.82, y: size.height),
                            control1: CGPoint(x: size.width * 0.73, y: size.height * 0.60),
                            control2: CGPoint(x: size.width * 0.86, y: size.height * 0.74)
                        )
                    }
                    .stroke(
                        LinearGradient(colors: [Color(hex: "#FFD27A"), Color(hex: "#FF8A3D"), Color(hex: "#B52B1D")], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                    .shadow(color: Color(hex: "#FF8A3D").opacity(0.7), radius: 4)

                    // Molten crater glow on the summit.
                    Ellipse()
                        .fill(Color(hex: "#FFB14E").opacity(colorScheme == .dark ? 0.55 : 0.45))
                        .frame(width: 16, height: 6)
                        .blur(radius: 3)
                        .position(x: size.width * 0.73, y: size.height * 0.37)

                    // Warm halo behind the ring.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#F0C46A").opacity(colorScheme == .dark ? 0.34 : 0.24), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 52
                            )
                        )
                        .frame(width: 104, height: 104)
                        .opacity(0.75 + Double(glint) * 0.25)
                        .position(x: ringX, y: ringY)

                    WeatheredRingView(glint: glint, colorScheme: colorScheme)
                        .position(x: ringX, y: ringY)

                    // Near hills in front of the ring's lower edge.
                    Path { path in
                        path.move(to: CGPoint(x: -4, y: size.height + 4))
                        path.addLine(to: CGPoint(x: -4, y: size.height * 0.86))
                        path.addQuadCurve(
                            to: CGPoint(x: size.width * 0.3, y: size.height * 0.88),
                            control: CGPoint(x: size.width * 0.14, y: size.height * 0.76)
                        )
                        path.addQuadCurve(
                            to: CGPoint(x: size.width * 0.62, y: size.height * 0.9),
                            control: CGPoint(x: size.width * 0.46, y: size.height * 0.98)
                        )
                        path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height + 4))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: colorScheme == .dark ? "#050506" : "#30271F").opacity(0.9))

                    Canvas { context, canvas in
                        for index in 0..<14 {
                            let phase = time * 0.42 + Double(index) * 0.73
                            let x = canvas.width * (0.5 + CGFloat((index * 11) % 43) / 100)
                            let rise = CGFloat((phase.truncatingRemainder(dividingBy: 1.0))) * canvas.height * 0.58
                            let y = canvas.height * 0.96 - rise
                            let side: CGFloat = index.isMultiple(of: 3) ? 2.4 : 1.8
                            let ember = Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side))
                            context.fill(ember, with: .color(Color(hex: index.isMultiple(of: 2) ? "#FFB14E" : "#D84C2F").opacity(0.58)))
                        }
                    }
                }
    }
}

private struct WeatheredRingView: View {
    let glint: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(Color(hex: "#4D2B10").opacity(0.92), lineWidth: 12)
                .offset(y: 2.5)

            Ellipse()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "#6F4217"),
                            Color(hex: "#C88A35"),
                            Color(hex: "#FFE6A0"),
                            Color(hex: "#9A5F20"),
                            Color(hex: "#E6B85A"),
                            Color(hex: "#5F3512")
                        ],
                        center: .center
                    ),
                    lineWidth: 8
                )

            Ellipse()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
                .padding(3)

            // Faint fire-letter inscription along the band.
            Ellipse()
                .stroke(
                    Color(hex: "#FF9A3D").opacity(0.35 + Double(glint) * 0.35),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [2.2, 2.6])
                )
                .padding(1)
                .shadow(color: Color(hex: "#FF8A3D").opacity(0.8), radius: 2)

            Group {
                Capsule().frame(width: 7, height: 1.2).rotationEffect(.degrees(16)).position(x: 18, y: 13)
                Capsule().frame(width: 6, height: 1.2).rotationEffect(.degrees(-10)).position(x: 29, y: 9)
                Capsule().frame(width: 8, height: 1.2).rotationEffect(.degrees(8)).position(x: 42, y: 10)
                Capsule().frame(width: 6, height: 1.2).rotationEffect(.degrees(-18)).position(x: 50, y: 16)
            }
            .foregroundStyle(Color(hex: "#5B3312").opacity(0.68))

            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.82 : 0.64))
                .frame(width: 13, height: 2.6)
                .rotationEffect(.degrees(-12 + Double(glint) * 20))
                .position(
                    x: 15 + glint * 34,
                    y: 14 - CGFloat(sin(Double(glint) * .pi)) * 5
                )
        }
        .frame(width: 66, height: 44)
        .rotationEffect(.degrees(-10))
        .shadow(color: Color.black.opacity(0.32), radius: 2, x: 0, y: 3)
        .shadow(color: Color(hex: "#E6A348").opacity(colorScheme == .dark ? 0.38 : 0.20), radius: 6)
    }
}

#if DEBUG
private struct ThemeStatusArtworkGallery: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(WeekTheme.allCases) { theme in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(theme.displayName)
                            .font(.headline)
                        ThemeStatusArtwork(theme: theme)
                            .frame(height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                            )
                    }
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary)
    }
}

#Preview("Theme Artwork · Light") {
    ThemeStatusArtworkGallery()
        .preferredColorScheme(.light)
}

#Preview("Theme Artwork · Dark") {
    ThemeStatusArtworkGallery()
        .preferredColorScheme(.dark)
}
#endif
