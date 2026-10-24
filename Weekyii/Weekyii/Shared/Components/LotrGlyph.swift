import SwiftUI
import UIKit

// MARK: - 魔戒 glyph set

/// Hand-drawn icons for the 魔戒 theme. Each glyph is authored on a 24 × 24
/// grid with round caps, so it reads like an engraved line at any size and
/// takes the current foreground style (tint, gradient, opacity).
enum LotrGlyph: String, CaseIterable {
    /// Focus: a gold ring.
    case ring
    /// Past / time: an hourglass.
    case hourglass
    /// Today: the sun rising over a ridge.
    case dawn
    /// Future / postpone: a folded map.
    case map
    /// Extensions: four rune stones.
    case runes
    /// Settings: a shield.
    case shield
    /// Frozen tasks: a six-armed frost star.
    case frost
    /// DDL tasks: an anvil throwing sparks.
    case anvil
    /// Regular tasks / done: a mithril diamond with a check.
    case mithril
    /// Leisure tasks: an elven leaf.
    case leaf
    /// In progress: a flame.
    case flame
    /// Origin chips: a scroll.
    case scroll
    /// Date line: a candle.
    case candle
    /// Completed section: first light on the horizon.
    case sunrise

    /// The SF Symbols a call site may pass that this set redraws.
    init?(systemName: String) {
        switch systemName {
        case "target": self = .ring
        case "clock", "clock.fill", "clock.arrow.circlepath": self = .hourglass
        case "sun.max", "sun.max.fill": self = .dawn
        case "calendar", "calendar.badge.clock": self = .map
        case "square.grid.2x2": self = .runes
        case "gearshape": self = .shield
        case "snowflake": self = .frost
        case "checkmark.circle", "checkmark.circle.fill": self = .mithril
        case "leaf", "leaf.fill": self = .leaf
        case "flame", "flame.fill": self = .flame
        case "folder", "folder.fill": self = .scroll
        default: return nil
        }
    }

    /// The glyph for a built-in task type that still uses its shipped icon.
    init?(builtInType kind: TaskType, iconName: String) {
        guard iconName == kind.iconName else { return nil }
        switch kind {
        case .regular: self = .mithril
        case .ddl: self = .anvil
        case .leisure: self = .leaf
        }
    }

    /// Stroke width on the 24 pt grid.
    fileprivate var lineWidth: CGFloat {
        switch self {
        case .ring: return 2.6
        case .frost: return 1.6
        default: return 1.7
        }
    }
}

// MARK: - Drawing

private struct LotrGlyphShape: Shape {
    enum Layer {
        case stroke
        case fill
    }

    let glyph: LotrGlyph
    let layer: Layer

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard side > 0 else { return Path() }
        let scale = side / 24
        let path = layer == .stroke ? strokePath : fillPath
        let transform = CGAffineTransform(
            translationX: rect.midX - 12 * scale,
            y: rect.midY - 12 * scale
        )
        .scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    private func line(_ path: inout Path, _ points: [CGPoint]) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
    }

    private func diamond(_ path: inout Path, center: CGPoint, radius: CGFloat) {
        line(&path, [
            p(center.x, center.y - radius),
            p(center.x + radius, center.y),
            p(center.x, center.y + radius),
            p(center.x - radius, center.y)
        ])
        path.closeSubpath()
    }

    private var strokePath: Path {
        var path = Path()
        switch glyph {
        case .ring:
            path.addEllipse(in: CGRect(x: 3, y: 5.8, width: 18, height: 12.4))
        case .hourglass:
            line(&path, [p(6, 3), p(18, 3)])
            line(&path, [p(6, 21), p(18, 21)])
            path.move(to: p(7, 3))
            path.addCurve(to: p(17, 12), control1: p(7, 8), control2: p(17, 8))
            path.addCurve(to: p(7, 21), control1: p(17, 16), control2: p(7, 16))
            path.move(to: p(17, 3))
            path.addCurve(to: p(7, 12), control1: p(17, 8), control2: p(7, 8))
            path.addCurve(to: p(17, 21), control1: p(7, 16), control2: p(17, 16))
        case .dawn:
            line(&path, [p(2, 19), p(8, 12), p(12, 16), p(15, 13), p(22, 19)])
            path.addEllipse(in: CGRect(x: 9, y: 5, width: 6, height: 6))
            line(&path, [p(12, 1.8), p(12, 3.2)])
            line(&path, [p(6.6, 4.2), p(7.6, 5.2)])
            line(&path, [p(17.4, 4.2), p(16.4, 5.2)])
        case .map:
            line(&path, [p(3, 6), p(9, 4), p(15, 6), p(21, 4), p(21, 18), p(15, 20), p(9, 18), p(3, 20)])
            path.closeSubpath()
            line(&path, [p(9, 4), p(9, 18)])
            line(&path, [p(15, 6), p(15, 20)])
        case .runes:
            diamond(&path, center: p(7, 6.5), radius: 4)
            diamond(&path, center: p(17, 6.5), radius: 4)
            diamond(&path, center: p(7, 17.5), radius: 4)
            diamond(&path, center: p(17, 17.5), radius: 4)
        case .shield:
            line(&path, [p(12, 2.5), p(20, 5.5), p(20, 11.5)])
            path.addCurve(to: p(12, 21.5), control1: p(20, 16.5), control2: p(16.5, 20))
            path.addCurve(to: p(4, 11.5), control1: p(7.5, 20), control2: p(4, 16.5))
            path.addLine(to: p(4, 5.5))
            path.closeSubpath()
            line(&path, [p(12, 7), p(12, 17)])
            line(&path, [p(8.5, 10.5), p(15.5, 10.5)])
        case .frost:
            line(&path, [p(12, 2), p(12, 22)])
            line(&path, [p(3.3, 7), p(20.7, 17)])
            line(&path, [p(3.3, 17), p(20.7, 7)])
            line(&path, [p(10, 3.6), p(12, 5.2), p(14, 3.6)])
            line(&path, [p(10, 20.4), p(12, 18.8), p(14, 20.4)])
            line(&path, [p(4, 9.6), p(6.5, 9.2), p(5.6, 6.8)])
            line(&path, [p(20, 14.4), p(17.5, 14.8), p(18.4, 17.2)])
            line(&path, [p(4, 14.4), p(6.5, 14.8), p(5.6, 17.2)])
            line(&path, [p(20, 9.6), p(17.5, 9.2), p(18.4, 6.8)])
        case .anvil:
            path.move(to: p(3, 8))
            path.addLine(to: p(16, 8))
            path.addCurve(to: p(21, 12), control1: p(16, 11), control2: p(18, 12))
            path.addCurve(to: p(15, 14), control1: p(20, 14), control2: p(18, 14))
            path.addLine(to: p(16, 17))
            path.addLine(to: p(8, 17))
            path.addLine(to: p(9, 14))
            path.addCurve(to: p(3, 8), control1: p(5, 14), control2: p(3, 12))
            path.closeSubpath()
            line(&path, [p(6, 20.5), p(18, 20.5)])
            line(&path, [p(14, 3), p(15.6, 4.6)])
            line(&path, [p(18, 1.8), p(18, 3.8)])
            line(&path, [p(20.2, 5), p(22, 5)])
        case .mithril:
            diamond(&path, center: p(12, 12), radius: 9.5)
            line(&path, [p(8.5, 12.3), p(10.9, 14.7), p(15.5, 9.7)])
        case .leaf:
            path.move(to: p(5, 19))
            path.addCurve(to: p(20, 4), control1: p(4, 10), control2: p(10, 4))
            path.addCurve(to: p(5, 19), control1: p(20, 14), control2: p(14, 20))
            path.closeSubpath()
            line(&path, [p(5, 19), p(14, 10)])
            line(&path, [p(10, 14), p(7, 14)])
            line(&path, [p(12, 12), p(12, 9)])
        case .flame:
            break
        case .scroll:
            line(&path, [p(6, 4), p(18, 4), p(18, 17)])
            path.addQuadCurve(to: p(15, 20), control: p(18, 20))
            path.addLine(to: p(6, 20))
            path.addQuadCurve(to: p(3, 17), control: p(3, 20))
            path.addQuadCurve(to: p(6, 14), control: p(3, 14))
            path.addLine(to: p(15, 14))
            path.move(to: p(6, 4))
            path.addQuadCurve(to: p(4, 6), control: p(4, 4))
            path.addQuadCurve(to: p(6, 8), control: p(4, 8))
            path.addLine(to: p(8, 8))
            line(&path, [p(10, 9), p(15, 9)])
            line(&path, [p(10, 11.5), p(14, 11.5)])
        case .candle:
            path.addRect(CGRect(x: 9, y: 11, width: 6, height: 10))
            line(&path, [p(6, 21), p(18, 21)])
        case .sunrise:
            line(&path, [p(4, 18), p(20, 18)])
            path.move(to: p(7, 14))
            path.addCurve(to: p(12, 9), control1: p(7, 11.2), control2: p(9.2, 9))
            path.addCurve(to: p(17, 14), control1: p(14.8, 9), control2: p(17, 11.2))
            line(&path, [p(12, 3.5), p(12, 6.5)])
            line(&path, [p(5, 8), p(6.5, 9.5)])
            line(&path, [p(19, 8), p(17.5, 9.5)])
            line(&path, [p(8, 21), p(16, 21)])
        }
        return path
    }

    private var fillPath: Path {
        var path = Path()
        switch glyph {
        case .hourglass:
            path.addRoundedRect(in: CGRect(x: 9.5, y: 17.4, width: 5, height: 2.2), cornerSize: CGSize(width: 1.1, height: 1.1))
        case .frost:
            diamond(&path, center: p(12, 12), radius: 1.8)
        case .flame:
            path.move(to: p(12, 2))
            path.addCurve(to: p(18, 14), control1: p(13, 6), control2: p(18, 8))
            path.addCurve(to: p(12, 20), control1: p(18, 17.3), control2: p(15.3, 20))
            path.addCurve(to: p(6, 14), control1: p(8.7, 20), control2: p(6, 17.3))
            path.addCurve(to: p(9, 8), control1: p(6, 11), control2: p(8, 9))
            path.addCurve(to: p(11, 11), control1: p(9, 10), control2: p(10, 11))
            path.addCurve(to: p(12, 2), control1: p(11, 8), control2: p(10, 5))
            path.closeSubpath()
        case .candle:
            path.move(to: p(12, 3))
            path.addCurve(to: p(14, 7.2), control1: p(13.5, 5), control2: p(14, 6))
            path.addQuadCurve(to: p(12, 9.2), control: p(14, 9.2))
            path.addQuadCurve(to: p(10, 7.2), control: p(10, 9.2))
            path.addCurve(to: p(12, 3), control1: p(10, 6), control2: p(10.8, 5))
            path.closeSubpath()
        default:
            break
        }
        return path
    }
}

/// One glyph sized by its frame, drawn in the current foreground style.
struct LotrGlyphView: View {
    let glyph: LotrGlyph

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let width = max(1, side / 24 * glyph.lineWidth)
            ZStack {
                LotrGlyphShape(glyph: glyph, layer: .stroke)
                    .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                LotrGlyphShape(glyph: glyph, layer: .fill)
                    .fill()
                if glyph == .ring {
                    // Engraved highlight along the upper band.
                    Path { path in
                        let s = side / 24
                        let ox = proxy.size.width / 2 - 12 * s
                        let oy = proxy.size.height / 2 - 12 * s
                        path.move(to: CGPoint(x: ox + 6.5 * s, y: oy + 9.8 * s))
                        path.addQuadCurve(
                            to: CGPoint(x: ox + 17.5 * s, y: oy + 9.8 * s),
                            control: CGPoint(x: ox + 12 * s, y: oy + 6.8 * s)
                        )
                    }
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: max(0.6, side / 24 * 0.9), lineCap: .round))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Theme-aware symbol

/// Draws a 魔戒 glyph when the active skin uses that set and the symbol has a
/// redrawn counterpart; otherwise the plain SF Symbol, which keeps inheriting
/// the caller's font, so every other theme renders exactly as before.
struct ThemedSymbol: View {
    let systemName: String
    var glyph: LotrGlyph? = nil
    /// Glyph size in points. SF Symbols keep sizing from `.font`.
    var size: CGFloat = 16
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if skin.glyphs == .lotr, let resolved = glyph ?? LotrGlyph(systemName: systemName) {
            LotrGlyphView(glyph: resolved)
                .frame(width: size, height: size)
        } else {
            Image(systemName: systemName)
        }
    }
}

// MARK: - Tab bar images

/// `tabItem` only takes an `Image`, so the glyphs are rendered once into
/// template images that the tab bar tints like SF Symbols.
@MainActor
enum LotrTabIcon {
    private static var cache: [LotrGlyph: UIImage] = [:]

    static func image(_ glyph: LotrGlyph, fallbackSystemName: String) -> Image {
        if let cached = cache[glyph] {
            return Image(uiImage: cached)
        }
        let renderer = ImageRenderer(
            content: LotrGlyphView(glyph: glyph)
                .foregroundStyle(Color.black)
                .frame(width: 25, height: 25)
        )
        renderer.scale = 3
        guard let rendered = renderer.uiImage else {
            return Image(systemName: fallbackSystemName)
        }
        let template = rendered.withRenderingMode(.alwaysTemplate)
        cache[glyph] = template
        return Image(uiImage: template)
    }
}
