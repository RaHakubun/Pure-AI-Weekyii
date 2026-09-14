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
            case .brutal, .neon, .paper, .terminal:
                GeometricStatusIllustration(theme: theme, renderingMode: renderingMode)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
        case .sunset, .lotr, .brutal, .neon, .paper, .terminal:
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
            default:
                Color.clear
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct BrutalStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    var body: some View {
        let unit = min(size.width, size.height)
        let registrationShift = CGFloat(sin(time * 0.72)) * 2.5

        ZStack {
            palette.backgroundSecondary

            Rectangle()
                .fill(palette.primary)
                .frame(width: unit * 0.62, height: unit * 0.62)
                .overlay(Rectangle().stroke(palette.textPrimary, lineWidth: max(2, unit * 0.025)))
                .rotationEffect(.degrees(-7))
                .offset(x: -unit * 0.17 + registrationShift, y: -unit * 0.05)

            Rectangle()
                .fill(palette.accent)
                .frame(width: unit * 0.39, height: unit * 0.39)
                .overlay(Rectangle().stroke(palette.textPrimary, lineWidth: max(2, unit * 0.02)))
                .rotationEffect(.degrees(11))
                .offset(x: unit * 0.22, y: unit * 0.10 - registrationShift)

            Circle()
                .fill(palette.backgroundPrimary)
                .frame(width: unit * 0.25, height: unit * 0.25)
                .overlay(Circle().stroke(palette.textPrimary, lineWidth: max(2, unit * 0.024)))
                .offset(x: unit * 0.10, y: -unit * 0.20)

            Rectangle()
                .fill(palette.textPrimary)
                .frame(width: unit * 0.72, height: max(3, unit * 0.045))
                .offset(x: unit * 0.03, y: unit * 0.29)

            Path { path in
                path.move(to: CGPoint(x: size.width * 0.09, y: size.height * 0.22))
                path.addLine(to: CGPoint(x: size.width * 0.31, y: size.height * 0.22))
                path.addLine(to: CGPoint(x: size.width * 0.31, y: size.height * 0.30))
            }
            .stroke(palette.textPrimary, style: StrokeStyle(lineWidth: max(2, unit * 0.02), lineCap: .square, lineJoin: .miter))
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct NeonStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let unit = min(size.width, size.height)
        let isDark = colorScheme == .dark
        let cyan = isDark ? palette.primary : Color(hex: "#00C9D8")
        let cyanLight = isDark ? palette.primaryLight : Color(hex: "#B4FAFF")
        let magenta = isDark ? palette.accent : Color(hex: "#F1008A")
        let violet = Color(hex: isDark ? "#A78BFA" : "#7657E8")
        let acid = Color(hex: isDark ? "#B7FF63" : "#8FBF2E")
        let ground = Color(hex: isDark ? "#070B18" : "#E8EEF0")
        let groundMid = Color(hex: isDark ? "#121B32" : "#C7D6DC")
        let paper = Color(hex: isDark ? "#152039" : "#F8FBFA")
        let paperShadow = Color(hex: isDark ? "#02040A" : "#738692")
        let pulse = 0.86 + ((sin(time * 2.1) + 1) * 0.5) * 0.14
        let exposureShift = CGFloat(sin(time * 0.34)) * unit * 0.025

        ZStack {
            LinearGradient(
                colors: [ground, groundMid, ground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(cyan.opacity(isDark ? 0.13 : 0.08))
                .frame(width: unit * 1.18, height: unit * 1.18)
                .blur(radius: unit * 0.28)
                .offset(x: -size.width * 0.28, y: -size.height * 0.12)

            Circle()
                .fill(magenta.opacity(isDark ? 0.12 : 0.07))
                .frame(width: unit * 0.96, height: unit * 0.96)
                .blur(radius: unit * 0.23)
                .offset(x: size.width * 0.28, y: size.height * 0.12)

            // The plate is the light-sensitive surface. The artwork below
            // behaves like several exposures laid on top of one another.
            Rectangle()
                .fill(paper.opacity(0.93))
                .frame(width: size.width * 0.82, height: size.height * 0.82)
                .rotationEffect(.degrees(-2.5))
                .shadow(color: paperShadow.opacity(isDark ? 0.45 : 0.20), radius: unit * 0.08, y: unit * 0.04)

            Rectangle()
                .stroke(paperShadow.opacity(isDark ? 0.40 : 0.22), lineWidth: 1)
                .frame(width: size.width * 0.82, height: size.height * 0.82)
                .rotationEffect(.degrees(-2.5))

            Canvas { context, canvas in
                func point(_ x: CGFloat, _ y: CGFloat, offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CGPoint {
                    CGPoint(
                        x: canvas.width * x + offsetX,
                        y: canvas.height * y + offsetY
                    )
                }

                // A dark contact shadow: the object blocks the light, rather
                // than depicting a recognisable building or device.
                var shadow = Path()
                shadow.move(to: point(0.25, 0.17, offsetX: unit * 0.035, offsetY: unit * 0.025))
                shadow.addLine(to: point(0.60, 0.17, offsetX: unit * 0.035, offsetY: unit * 0.025))
                shadow.addLine(to: point(0.68, 0.37, offsetX: unit * 0.035, offsetY: unit * 0.025))
                shadow.addLine(to: point(0.55, 0.78, offsetX: unit * 0.035, offsetY: unit * 0.025))
                shadow.addLine(to: point(0.25, 0.67, offsetX: unit * 0.035, offsetY: unit * 0.025))
                shadow.closeSubpath()
                context.fill(shadow, with: .color(paperShadow.opacity(isDark ? 0.46 : 0.24)))

                // Cyan exposure: a hard-edged transparent sheet with one
                // long vertical gesture and a cut-like diagonal ending.
                var cyanExposure = Path()
                cyanExposure.move(to: point(0.20, 0.72))
                cyanExposure.addLine(to: point(0.25, 0.20))
                cyanExposure.addLine(to: point(0.45, 0.20))
                cyanExposure.addLine(to: point(0.39, 0.43))
                cyanExposure.addLine(to: point(0.54, 0.68))
                cyanExposure.addLine(to: point(0.43, 0.76))
                cyanExposure.closeSubpath()
                context.fill(cyanExposure, with: .color(cyan.opacity(isDark ? 0.28 : 0.18)))
                context.stroke(
                    cyanExposure,
                    with: .color(cyan.opacity(0.92 * pulse)),
                    style: StrokeStyle(lineWidth: max(1.5, unit * 0.018), lineJoin: .miter)
                )

                // Second exposure, offset just enough to create a ghost edge.
                var cyanGhost = Path()
                cyanGhost.move(to: point(0.23, 0.72, offsetX: exposureShift))
                cyanGhost.addLine(to: point(0.28, 0.20, offsetX: exposureShift))
                cyanGhost.addLine(to: point(0.48, 0.20, offsetX: exposureShift))
                cyanGhost.addLine(to: point(0.42, 0.43, offsetX: exposureShift))
                context.stroke(cyanGhost, with: .color(cyanLight.opacity(0.42)), lineWidth: max(1, unit * 0.010))

                // Magenta exposure: a soft oval plus an angular plate crossing it.
                let magentaOval = CGRect(
                    x: canvas.width * 0.47,
                    y: canvas.height * 0.20,
                    width: canvas.width * 0.30,
                    height: canvas.height * 0.42
                )
                context.fill(Path(ellipseIn: magentaOval), with: .color(magenta.opacity(isDark ? 0.25 : 0.16)))
                context.stroke(
                    Path(ellipseIn: magentaOval),
                    with: .color(magenta.opacity(0.92 * pulse)),
                    style: StrokeStyle(lineWidth: max(1.5, unit * 0.016))
                )

                var magentaPlate = Path()
                magentaPlate.move(to: point(0.53, 0.26))
                magentaPlate.addLine(to: point(0.76, 0.26))
                magentaPlate.addLine(to: point(0.69, 0.51))
                magentaPlate.addLine(to: point(0.49, 0.51))
                magentaPlate.closeSubpath()
                context.fill(magentaPlate, with: .color(magenta.opacity(isDark ? 0.18 : 0.12)))
                context.stroke(magentaPlate, with: .color(magenta.opacity(0.82)), lineWidth: max(1, unit * 0.012))

                // A violet ring and acid block read like transparent objects
                // placed on the paper, not like windows on a facade.
                let ringRect = CGRect(
                    x: canvas.width * 0.55,
                    y: canvas.height * 0.40,
                    width: canvas.width * 0.25,
                    height: canvas.height * 0.25
                )
                context.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(violet.opacity(0.78)),
                    style: StrokeStyle(lineWidth: max(1.5, unit * 0.018))
                )
                context.stroke(
                    Path(ellipseIn: ringRect.insetBy(dx: unit * 0.045, dy: unit * 0.025)),
                    with: .color(violet.opacity(0.30)),
                    lineWidth: max(1, unit * 0.010)
                )

                let acidRect = CGRect(
                    x: canvas.width * 0.27,
                    y: canvas.height * 0.54,
                    width: canvas.width * 0.16,
                    height: canvas.height * 0.12
                )
                context.fill(Path(acidRect), with: .color(acid.opacity(isDark ? 0.52 : 0.34)))
                context.stroke(Path(acidRect), with: .color(acid.opacity(0.95)), lineWidth: max(1, unit * 0.012))

                // Fine parallel lines are the analogue of multiple negatives:
                // they supply rhythm without turning the image into scenery.
                for index in 0..<6 {
                    let x = canvas.width * (0.16 + CGFloat(index) * 0.115)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: canvas.height * 0.18))
                    line.addLine(to: CGPoint(x: x + canvas.width * 0.08, y: canvas.height * 0.79))
                    context.stroke(line, with: .color(cyan.opacity(0.20)), lineWidth: 0.7)
                }

                for index in 0..<5 {
                    let y = canvas.height * (0.25 + CGFloat(index) * 0.105)
                    var line = Path()
                    line.move(to: CGPoint(x: canvas.width * 0.16, y: y))
                    line.addLine(to: CGPoint(x: canvas.width * 0.82, y: y + canvas.height * 0.025))
                    context.stroke(line, with: .color(magenta.opacity(0.18)), lineWidth: 0.7)
                }
            }

            // Small light leaks keep the neon identity while staying abstract.
            Rectangle()
                .fill(cyanLight.opacity(0.80 * pulse))
                .frame(width: max(2, unit * 0.018), height: unit * 0.16)
                .rotationEffect(.degrees(-7))
                .position(x: size.width * 0.26, y: size.height * 0.27)
                .shadow(color: cyan.opacity(0.75), radius: unit * 0.04)

            Rectangle()
                .fill(magenta.opacity(0.86 * pulse))
                .frame(width: max(2, unit * 0.018), height: unit * 0.20)
                .rotationEffect(.degrees(12))
                .position(x: size.width * 0.70, y: size.height * 0.30)
                .shadow(color: magenta.opacity(0.80), radius: unit * 0.04)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct NeonArchitectureStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let unit = min(size.width, size.height)
        let isDark = colorScheme == .dark
        let cyan = isDark ? palette.primary : Color(hex: "#00D7E6")
        let cyanLight = isDark ? palette.primaryLight : Color(hex: "#75F6FF")
        let magenta = isDark ? palette.accent : Color(hex: "#F6008D")
        let violet = Color(hex: isDark ? "#A88CFF" : "#7C63F4")
        let acid = Color(hex: isDark ? "#B8FF5A" : "#9BDD32")
        let skyTop = Color(hex: isDark ? "#050811" : "#DCEAF0")
        let skyMiddle = Color(hex: isDark ? "#101A31" : "#AFC7D2")
        let skyBottom = Color(hex: isDark ? "#1B1230" : "#E8EEF0")
        let concrete = Color(hex: isDark ? "#131A2A" : "#344052")
        let metal = Color(hex: isDark ? "#20283A" : "#566477")
        let streetTop = Color(hex: isDark ? "#0E1728" : "#788E9A")
        let streetBottom = Color(hex: isDark ? "#080B14" : "#394752")
        let flicker = 0.78 + ((sin(time * 2.7) + 1) * 0.5) * 0.22
        let rainDrift = CGFloat(sin(time * 0.42)) * unit * 0.04
        let skyline: [(CGFloat, CGFloat, Color)] = isDark
            ? [
                (0.03, 0.43, Color(hex: "#0E1422")),
                (0.17, 0.31, Color(hex: "#10182A")),
                (0.77, 0.37, Color(hex: "#11172A")),
                (0.90, 0.48, Color(hex: "#0D1320"))
            ]
            : [
                (0.03, 0.43, Color(hex: "#B3C2CC")),
                (0.17, 0.31, Color(hex: "#A5B8C3")),
                (0.77, 0.37, Color(hex: "#A9BBC5")),
                (0.90, 0.48, Color(hex: "#94A9B5"))
            ]

        ZStack {
            LinearGradient(
                colors: [skyTop, skyMiddle, skyBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(magenta.opacity(isDark ? 0.15 : 0.10))
                .frame(width: unit * 1.10, height: unit * 1.10)
                .blur(radius: unit * 0.26)
                .offset(x: size.width * 0.30, y: -size.height * 0.15)

            Canvas { context, canvas in
                for (x, height, fill) in skyline {
                    let rect = CGRect(
                        x: canvas.width * x,
                        y: canvas.height * (0.72 - height * 0.48),
                        width: canvas.width * 0.17,
                        height: canvas.height * height
                    )
                    context.fill(Path(rect), with: .color(fill))
                    context.stroke(
                        Path(rect),
                        with: .color(cyan.opacity(0.24)),
                        style: StrokeStyle(lineWidth: 1)
                    )
                }

                for index in 0..<20 {
                    let x = CGFloat((index * 37) % 101) / 100 * canvas.width + rainDrift
                    let y = CGFloat((index * 23) % 70) / 100 * canvas.height
                    var rain = Path()
                    rain.move(to: CGPoint(x: x, y: y))
                    rain.addLine(to: CGPoint(x: x - 3, y: y + canvas.height * 0.11))
                    context.stroke(rain, with: .color(cyan.opacity(0.16)), lineWidth: 0.7)
                }
            }

            // Orthogonal masses give the scene a clear vertical axis and a
            // stable horizontal street line at the bottom.
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.79))
                    path.addLine(to: CGPoint(x: size.width * 0.08, y: size.height * 0.46))
                    path.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.46))
                    path.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.41))
                    path.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.41))
                    path.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.79))
                    path.closeSubpath()
                }
                .fill(metal)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.79))
                    path.addLine(to: CGPoint(x: size.width * 0.08, y: size.height * 0.46))
                    path.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.46))
                    path.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.41))
                    path.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.41))
                    path.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.79))
                }
                .stroke(cyan, style: StrokeStyle(lineWidth: max(2, unit * 0.020), lineCap: .square, lineJoin: .miter))
                .shadow(color: cyan.opacity(0.82), radius: unit * 0.06)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.64, y: size.height * 0.79))
                    path.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.35))
                    path.addLine(to: CGPoint(x: size.width * 0.91, y: size.height * 0.35))
                    path.addLine(to: CGPoint(x: size.width * 0.91, y: size.height * 0.79))
                    path.closeSubpath()
                }
                .fill(concrete)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.64, y: size.height * 0.79))
                    path.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.35))
                    path.addLine(to: CGPoint(x: size.width * 0.91, y: size.height * 0.35))
                    path.addLine(to: CGPoint(x: size.width * 0.91, y: size.height * 0.79))
                }
                .stroke(magenta, style: StrokeStyle(lineWidth: max(2, unit * 0.020), lineCap: .square, lineJoin: .miter))
                .shadow(color: magenta.opacity(0.88), radius: unit * 0.06)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.39, y: size.height * 0.79))
                    path.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.19))
                    path.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.19))
                    path.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.60, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.60, y: size.height * 0.17))
                    path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.17))
                    path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.79))
                    path.closeSubpath()
                }
                .fill(concrete)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.39, y: size.height * 0.79))
                    path.addLine(to: CGPoint(x: size.width * 0.39, y: size.height * 0.19))
                    path.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.19))
                    path.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.60, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.60, y: size.height * 0.17))
                    path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.17))
                    path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.79))
                }
                .stroke(cyan, style: StrokeStyle(lineWidth: max(2, unit * 0.022), lineCap: .square, lineJoin: .miter))
                .shadow(color: cyan.opacity(0.90), radius: unit * 0.07)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.60, y: size.height * 0.17))
                    path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.17))
                    path.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.79))
                }
                .stroke(magenta, style: StrokeStyle(lineWidth: max(2, unit * 0.022), lineCap: .square, lineJoin: .miter))
                .shadow(color: magenta.opacity(0.9), radius: unit * 0.07)
            }

            // Bright floor bands and window grids reinforce the architecture.
            ForEach(0..<6, id: \.self) { row in
                Rectangle()
                    .fill((row % 2 == 0 ? cyan : magenta).opacity(0.64 * flicker))
                    .frame(width: size.width * 0.19, height: max(1, unit * 0.012))
                    .position(x: size.width * 0.52, y: size.height * (0.23 + CGFloat(row) * 0.085))
                    .shadow(color: (row % 2 == 0 ? cyan : magenta).opacity(0.65), radius: unit * 0.025)
            }

            ForEach(0..<4, id: \.self) { column in
                ForEach(0..<5, id: \.self) { row in
                    let pinkWindow = (column + row) % 5 == 0
                    Rectangle()
                        .fill((pinkWindow ? magenta : cyan).opacity(pinkWindow ? 0.84 : 0.70 * flicker))
                        .frame(width: max(2, unit * 0.021), height: max(3, unit * 0.038))
                        .shadow(color: (pinkWindow ? magenta : cyan).opacity(0.7), radius: unit * 0.025)
                        .position(
                            x: size.width * 0.44 + CGFloat(column) * size.width * 0.045,
                            y: size.height * 0.25 + CGFloat(row) * unit * 0.082
                        )
                }
            }

            ForEach(0..<3, id: \.self) { row in
                Rectangle()
                    .fill(cyan.opacity(0.60 * flicker))
                    .frame(width: size.width * 0.19, height: max(1, unit * 0.011))
                    .position(x: size.width * 0.22, y: size.height * (0.51 + CGFloat(row) * 0.085))
            }

            ForEach(0..<3, id: \.self) { row in
                Rectangle()
                    .fill(magenta.opacity(0.64 * flicker))
                    .frame(width: size.width * 0.18, height: max(1, unit * 0.011))
                    .position(x: size.width * 0.78, y: size.height * (0.44 + CGFloat(row) * 0.085))
            }

            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(violet.opacity(0.72))
                    .frame(width: max(2, unit * 0.020), height: unit * 0.10)
                    .shadow(color: violet.opacity(0.72), radius: unit * 0.03)
                    .position(
                        x: size.width * 0.70 + CGFloat(index) * size.width * 0.045,
                        y: size.height * 0.43 + CGFloat(index % 2) * unit * 0.10
                    )
            }

            // The wet street is a single calm horizontal base for the three masses.
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [streetTop, streetBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size.height * 0.25)
            }

            Canvas { context, canvas in
                let streetY = canvas.height * 0.77
                for index in 0..<11 {
                    let progress = CGFloat(index) / 10
                    let x = canvas.width * (0.16 + progress * 0.72)
                    let width = canvas.width * (0.04 + (1 - progress) * 0.09)
                    var reflection = Path()
                    reflection.move(to: CGPoint(x: x, y: streetY))
                    reflection.addLine(to: CGPoint(x: x - width * 0.35, y: canvas.height + 4))
                    context.stroke(
                        reflection,
                        with: .color((index % 3 == 0 ? magenta : cyan).opacity(isDark ? 0.19 : 0.34)),
                        style: StrokeStyle(lineWidth: max(1, width * 0.11), lineCap: .round)
                    )
                }

                for index in 0..<7 {
                    let y = streetY + CGFloat(index) * canvas.height * 0.025
                    var puddle = Path()
                    puddle.move(to: CGPoint(x: canvas.width * 0.05, y: y))
                    puddle.addQuadCurve(
                        to: CGPoint(x: canvas.width * 0.95, y: y + 1),
                        control: CGPoint(x: canvas.width * 0.50, y: y - 2)
                    )
                    context.stroke(puddle, with: .color(cyan.opacity(isDark ? 0.13 : 0.22)), lineWidth: 0.7)
                }
            }

            // Signs are horizontal and physically attached to a facade.
            NeonBuildingSign(title: "NIGHT//08", tint: cyan, text: cyanLight, width: unit * 0.43, height: unit * 0.17)
                .position(x: size.width * 0.52, y: size.height * 0.42)

            NeonBuildingSign(title: "雨夜", tint: magenta, text: magenta, width: unit * 0.25, height: unit * 0.20)
                .position(x: size.width * 0.79, y: size.height * 0.48)

            NeonBuildingSign(title: "BYTE", tint: acid, text: acid, width: unit * 0.27, height: unit * 0.16)
                .position(x: size.width * 0.22, y: size.height * 0.58)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct LegacyNeonStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let unit = min(size.width, size.height)
        let cyan = colorScheme == .dark ? palette.primary : Color(hex: "#00D7E6")
        let cyanLight = colorScheme == .dark ? palette.primaryLight : Color(hex: "#75F6FF")
        let magenta = colorScheme == .dark ? palette.accent : Color(hex: "#F6008D")
        let violet = Color(hex: colorScheme == .dark ? "#A88CFF" : "#7C63F4")
        let acid = Color(hex: colorScheme == .dark ? "#B8FF5A" : "#9BDD32")
        let skyTop = Color(hex: colorScheme == .dark ? "#050811" : "#DCEAF0")
        let skyMiddle = Color(hex: colorScheme == .dark ? "#101A31" : "#AFC7D2")
        let skyBottom = Color(hex: colorScheme == .dark ? "#1B1230" : "#E8EEF0")
        let concrete = Color(hex: colorScheme == .dark ? "#131A2A" : "#344052")
        let metal = Color(hex: colorScheme == .dark ? "#20283A" : "#566477")
        let streetTop = Color(hex: colorScheme == .dark ? "#0E1728" : "#788E9A")
        let streetBottom = Color(hex: colorScheme == .dark ? "#080B14" : "#394752")
        let flicker = 0.78 + ((sin(time * 2.7) + 1) * 0.5) * 0.22
        let rainDrift = CGFloat(sin(time * 0.42)) * unit * 0.04
        let skyline: [(CGFloat, CGFloat, Color)] = colorScheme == .dark
            ? [
                (0.04, 0.47, Color(hex: "#0E1422")),
                (0.17, 0.34, Color(hex: "#10182A")),
                (0.78, 0.40, Color(hex: "#11172A")),
                (0.91, 0.52, Color(hex: "#0D1320"))
            ]
            : [
                (0.04, 0.47, Color(hex: "#B3C2CC")),
                (0.17, 0.34, Color(hex: "#A5B8C3")),
                (0.78, 0.40, Color(hex: "#A9BBC5")),
                (0.91, 0.52, Color(hex: "#94A9B5"))
            ]

        ZStack {
            LinearGradient(
                colors: [skyTop, skyMiddle, skyBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // Distant high-rises and a hazy magenta city glow.
            Circle()
                .fill(magenta.opacity(colorScheme == .dark ? 0.15 : 0.10))
                .frame(width: unit * 1.18, height: unit * 1.18)
                .blur(radius: unit * 0.28)
                .offset(x: size.width * 0.30, y: -size.height * 0.15)

            Canvas { context, canvas in
                for (x, height, fill) in skyline {
                    let width = canvas.width * 0.18
                    let rect = CGRect(
                        x: canvas.width * x,
                        y: canvas.height * (0.72 - height * 0.48),
                        width: width,
                        height: canvas.height * height
                    )
                    context.fill(Path(rect), with: .color(fill))
                    context.stroke(
                        Path(rect),
                        with: .color(cyan.opacity(0.24)),
                        style: StrokeStyle(lineWidth: 1)
                    )
                }

                // Rain streaks establish the wet-night atmosphere without
                // becoming noisy at the compact card size.
                for index in 0..<22 {
                    let x = CGFloat((index * 37) % 101) / 100 * canvas.width + rainDrift
                    let y = CGFloat((index * 23) % 70) / 100 * canvas.height
                    var rain = Path()
                    rain.move(to: CGPoint(x: x, y: y))
                    rain.addLine(to: CGPoint(x: x - 3, y: y + canvas.height * 0.12))
                    context.stroke(rain, with: .color(cyan.opacity(0.18)), lineWidth: 0.7)
                }
            }

            // Main tower: a dark concrete mass with an irregular cantilever.
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.84))
                    path.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.20))
                    path.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.27))
                    path.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.84))
                    path.closeSubpath()
                }
                .fill(concrete)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.84))
                    path.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.20))
                    path.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.27))
                    path.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.84))
                }
                .stroke(cyan, style: StrokeStyle(lineWidth: max(2, unit * 0.028), lineCap: .square, lineJoin: .miter))
                .shadow(color: cyan.opacity(0.85), radius: unit * 0.07)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.56, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.87, y: size.height * 0.22))
                    path.addLine(to: CGPoint(x: size.width * 0.83, y: size.height * 0.58))
                    path.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.50))
                    path.closeSubpath()
                }
                .fill(metal)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.56, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.87, y: size.height * 0.22))
                    path.addLine(to: CGPoint(x: size.width * 0.83, y: size.height * 0.58))
                    path.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.50))
                }
                .stroke(magenta, style: StrokeStyle(lineWidth: max(2, unit * 0.024), lineCap: .square, lineJoin: .miter))
                .shadow(color: magenta.opacity(0.88), radius: unit * 0.065)
            }

            // Dense cyan window columns and a magenta LED curtain.
            ForEach(0..<5, id: \.self) { column in
                ForEach(0..<5, id: \.self) { row in
                    let isPink = (column + row) % 4 == 0
                    Rectangle()
                        .fill((isPink ? magenta : cyan).opacity(isPink ? 0.82 : 0.70 * flicker))
                        .frame(width: max(2, unit * 0.027), height: max(3, unit * 0.052))
                        .shadow(color: (isPink ? magenta : cyan).opacity(0.7), radius: unit * 0.025)
                        .position(
                            x: size.width * 0.35 + CGFloat(column) * unit * 0.052,
                            y: size.height * 0.29 + CGFloat(row) * unit * 0.085
                        )
                }
            }

            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(violet.opacity(0.78))
                    .frame(width: max(2, unit * 0.022), height: unit * 0.13)
                    .shadow(color: violet.opacity(0.72), radius: unit * 0.03)
                    .rotationEffect(.degrees(-8))
                    .position(
                        x: size.width * 0.70 + CGFloat(index) * unit * 0.044,
                        y: size.height * 0.34 + CGFloat(index % 2) * unit * 0.10
                    )
            }

            // Layered signage is intentionally asymmetrical, like a dense
            // street facade instead of a centred abstract logo.
            NeonBuildingSign(title: "NIGHT//08", tint: cyan, text: cyanLight, width: unit * 0.48, height: unit * 0.18)
                .rotationEffect(.degrees(-4))
                .position(x: size.width * 0.35, y: size.height * 0.48)

            NeonBuildingSign(title: "雨夜", tint: magenta, text: magenta, width: unit * 0.27, height: unit * 0.22)
                .rotationEffect(.degrees(7))
                .position(x: size.width * 0.70, y: size.height * 0.49)

            NeonBuildingSign(title: "BYTE", tint: acid, text: acid, width: unit * 0.29, height: unit * 0.17)
                .rotationEffect(.degrees(-7))
                .position(x: size.width * 0.75, y: size.height * 0.68)

            // Rain-slick street and compressed neon reflections.
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [streetTop, streetBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size.height * 0.25)
            }

            Canvas { context, canvas in
                let streetY = canvas.height * 0.77
                for index in 0..<11 {
                    let progress = CGFloat(index) / 10
                    let x = canvas.width * (0.16 + progress * 0.72)
                    let width = canvas.width * (0.04 + (1 - progress) * 0.09)
                    var reflection = Path()
                    reflection.move(to: CGPoint(x: x, y: streetY))
                    reflection.addLine(to: CGPoint(x: x - width * 0.35, y: canvas.height + 4))
                    context.stroke(
                        reflection,
                        with: .color((index % 3 == 0 ? magenta : cyan).opacity(colorScheme == .dark ? 0.19 : 0.34)),
                        style: StrokeStyle(lineWidth: max(1, width * 0.11), lineCap: .round)
                    )
                }

                for index in 0..<7 {
                    let y = streetY + CGFloat(index) * canvas.height * 0.025
                    var puddle = Path()
                    puddle.move(to: CGPoint(x: canvas.width * 0.05, y: y))
                    puddle.addQuadCurve(
                        to: CGPoint(x: canvas.width * 0.95, y: y + 1),
                        control: CGPoint(x: canvas.width * 0.50, y: y - 2)
                    )
                    context.stroke(puddle, with: .color(cyan.opacity(colorScheme == .dark ? 0.13 : 0.22)), lineWidth: 0.7)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct NeonBuildingSign: View {
    let title: String
    let tint: Color
    let text: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(tint)
                .frame(width: max(2, height * 0.10))

            Text(title)
                .font(.system(size: max(7, height * 0.34), weight: .bold, design: .monospaced))
                .foregroundStyle(text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, max(4, height * 0.20))
        .frame(width: width, height: height)
        .background(Color(hex: "#070B16").opacity(0.90))
        .overlay {
            Rectangle()
                .stroke(tint, lineWidth: max(1, height * 0.07))
        }
        .shadow(color: tint.opacity(0.88), radius: max(3, height * 0.35))
    }
}

private struct PaperStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    var body: some View {
        let unit = min(size.width, size.height)
        let paperDrift = CGFloat(sin(time * 0.40)) * 1.8

        ZStack {
            palette.backgroundSecondary

            Rectangle()
                .fill(palette.backgroundTertiary.opacity(0.72))
                .frame(width: size.width * 0.71, height: size.height * 0.74)
                .rotationEffect(.degrees(-5))
                .offset(x: -size.width * 0.10, y: size.height * 0.03)

            Rectangle()
                .fill(palette.backgroundPrimary)
                .frame(width: size.width * 0.67, height: size.height * 0.72)
                .overlay(Rectangle().stroke(palette.textSecondary.opacity(0.48), lineWidth: 1))
                .rotationEffect(.degrees(4 + Double(paperDrift)))
                .offset(x: size.width * 0.06, y: -size.height * 0.02)

            Rectangle()
                .fill(palette.primary.opacity(0.92))
                .frame(width: unit * 0.18, height: unit * 0.60)
                .rotationEffect(.degrees(-3))
                .offset(x: -unit * 0.22, y: -unit * 0.04)

            Rectangle()
                .fill(palette.accent.opacity(0.82))
                .frame(width: unit * 0.14, height: unit * 0.43)
                .rotationEffect(.degrees(5))
                .offset(x: unit * 0.14, y: unit * 0.07)

            Circle()
                .stroke(palette.primary, lineWidth: max(1, unit * 0.016))
                .frame(width: unit * 0.31, height: unit * 0.31)
                .overlay {
                    Circle()
                        .stroke(palette.accent.opacity(0.64), lineWidth: max(1, unit * 0.01))
                        .padding(unit * 0.045)
                }
                .offset(x: unit * 0.21, y: -unit * 0.19)

            Path { path in
                path.move(to: CGPoint(x: size.width * 0.20, y: size.height * 0.77))
                path.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.77))
            }
            .stroke(palette.textSecondary.opacity(0.58), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct TerminalStatusScene: View {
    let size: CGSize
    let time: TimeInterval
    let palette: ThemeArtworkPalette

    var body: some View {
        let unit = min(size.width, size.height)
        let cursorOpacity = 0.35 + ((sin(time * 3.2) + 1) * 0.5) * 0.65

        ZStack {
            palette.backgroundPrimary

            Canvas { context, canvas in
                for index in 0..<12 {
                    let y = CGFloat(index) / 11 * canvas.height
                    var scanline = Path()
                    scanline.move(to: CGPoint(x: 0, y: y))
                    scanline.addLine(to: CGPoint(x: canvas.width, y: y))
                    context.stroke(scanline, with: .color(palette.primary.opacity(0.08)), lineWidth: 1)
                }
            }

            RoundedRectangle(cornerRadius: unit * 0.05, style: .continuous)
                .fill(palette.backgroundSecondary)
                .frame(width: size.width * 0.72, height: size.height * 0.70)
                .overlay {
                    RoundedRectangle(cornerRadius: unit * 0.05, style: .continuous)
                        .stroke(palette.primary.opacity(0.78), lineWidth: max(1, unit * 0.016))
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Circle().fill(palette.accent).frame(width: 5, height: 5)
                        Circle().fill(palette.primary).frame(width: 5, height: 5)
                        Circle().fill(palette.primaryLight).frame(width: 5, height: 5)
                    }
                    .padding(.leading, unit * 0.08)
                    .padding(.top, unit * 0.07)
                }

            VStack(alignment: .leading, spacing: unit * 0.055) {
                Text("> weekyii")
                Text("// focus")
                    .foregroundStyle(palette.accent)

                HStack(spacing: unit * 0.035) {
                    Rectangle().fill(palette.primary).frame(width: unit * 0.20, height: max(3, unit * 0.035))
                    Rectangle().fill(palette.primaryLight.opacity(0.55)).frame(width: unit * 0.10, height: max(3, unit * 0.035))
                }

                HStack(spacing: unit * 0.02) {
                    Text(">_")
                    Rectangle()
                        .fill(palette.primaryLight.opacity(cursorOpacity))
                        .frame(width: max(3, unit * 0.04), height: unit * 0.14)
                }
            }
            .font(.system(size: max(11, unit * 0.13), weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.primary)
            .offset(x: -unit * 0.13, y: unit * 0.06)
        }
        .frame(width: size.width, height: size.height)
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
                            : [Color(hex: "#E8DFD0"), Color(hex: "#B7A995"), Color(hex: "#755A48")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color(hex: "#D94A2E").opacity(colorScheme == .dark ? 0.24 : 0.16))
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
                    .fill(Color(hex: colorScheme == .dark ? "#08090A" : "#4B4642").opacity(0.94))

                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.75, y: size.height * 0.42))
                        path.addCurve(
                            to: CGPoint(x: size.width * 0.82, y: size.height),
                            control1: CGPoint(x: size.width * 0.73, y: size.height * 0.60),
                            control2: CGPoint(x: size.width * 0.86, y: size.height * 0.74)
                        )
                    }
                    .stroke(
                        LinearGradient(colors: [Color(hex: "#FFB14E"), Color(hex: "#B52B1D")], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )

                    WeatheredRingView(glint: glint, colorScheme: colorScheme)
                        .position(x: ringX, y: ringY)

                    Canvas { context, canvas in
                        for index in 0..<8 {
                            let phase = time * 0.42 + Double(index) * 0.73
                            let x = canvas.width * (0.55 + CGFloat((index * 11) % 37) / 100)
                            let rise = CGFloat((phase.truncatingRemainder(dividingBy: 1.0))) * canvas.height * 0.58
                            let y = canvas.height * 0.96 - rise
                            let ember = Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8))
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
