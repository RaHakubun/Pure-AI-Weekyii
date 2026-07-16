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
        case .sunset, .lotr:
            Color.clear
        }
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
