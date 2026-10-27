import SwiftUI
import UIKit

// MARK: - 魔戒 glyph set

/// Hand-drawn icons for the 魔戒 theme. Each glyph is a prop seen in the films,
/// authored on a 24 × 24 grid with round caps so it reads like an engraved line
/// at any size and takes the current foreground style (ink, status colour, gold).
/// No glyph glows; only the ring artwork on 当下 is lit.
enum LotrGlyph: String, CaseIterable {
    /// 当下 / focus: the One Ring, a band with visible thickness.
    case ring
    /// 过去: the Red Book of Westmarch.
    case redBook
    /// 未来 / 本周 / postpone: a rolled map of Middle-earth with a route.
    case map
    /// 扩展: the Phial of Galadriel.
    case phial
    /// 我的 / settings: the leaf-of-Lórien brooch.
    case brooch
    /// Regular tasks: Sting.
    case sting
    /// DDL tasks: Mount Doom.
    case mountDoom
    /// Leisure tasks: a hobbit's long-stemmed pipe.
    case pipe
    /// Frozen tasks: the snow-bound peak of Caradhras.
    case caradhras
    /// In progress: a lit beacon of Gondor.
    case beacon
    /// Completed / done: the White Tree of Gondor.
    case whiteTree
    /// Start time: the hourglass on Bilbo's desk.
    case hourglass
    /// Date line / drafting: Bilbo's quill.
    case quill
    /// Origin chips: a letter under a wax seal.
    case letter

    /// The SF Symbols a call site may pass that this set redraws.
    init?(systemName: String) {
        switch systemName {
        case "target": self = .ring
        case "sun.max", "sun.max.fill": self = .ring
        case "clock.arrow.circlepath": self = .redBook
        case "clock", "clock.fill": self = .hourglass
        case "calendar", "calendar.badge.clock": self = .map
        case "square.grid.2x2": self = .phial
        case "gearshape": self = .brooch
        case "snowflake": self = .caradhras
        case "checkmark.circle", "checkmark.circle.fill": self = .whiteTree
        case "leaf", "leaf.fill": self = .pipe
        case "flame", "flame.fill": self = .beacon
        case "folder", "folder.fill": self = .letter
        case "hourglass", "hourglass.circle", "hourglass.circle.fill": self = .hourglass
        case "repeat", "repeat.circle", "repeat.circle.fill": self = .pipe
        case "bandage", "bandage.fill": self = .brooch
        default: return nil
        }
    }

    /// The glyph for a built-in task type that still uses its shipped icon.
    init?(builtInType kind: TaskType, iconName: String) {
        guard iconName == kind.iconName else { return nil }
        switch kind {
        case .regular: self = .sting
        case .ddl: self = .mountDoom
        case .leisure: self = .pipe
        }
    }

    /// The glyph pressed into a day-status wax seal.
    init(status: DayStatus) {
        switch status {
        case .empty: self = .hourglass
        case .draft: self = .quill
        case .execute: self = .beacon
        case .completed: self = .whiteTree
        case .expired: self = .mountDoom
        }
    }

    /// Stroke width on the 24 pt grid.
    fileprivate var lineWidth: CGFloat { 1.6 }
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

    private func dot(_ path: inout Path, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private var strokePath: Path {
        var path = Path()
        switch glyph {
        case .ring:
            path.addEllipse(in: CGRect(x: 2.8, y: 6.2, width: 18.4, height: 12.8))
            path.addEllipse(in: CGRect(x: 5.6, y: 7.7, width: 12.8, height: 7.4))
        case .redBook:
            // Cover, spine, raised bands, strap clasp, tooled lozenge, title lines.
            path.move(to: p(6.5, 3))
            path.addLine(to: p(17.5, 3))
            path.addQuadCurve(to: p(19, 4.5), control: p(19, 3))
            path.addLine(to: p(19, 19.5))
            path.addQuadCurve(to: p(17.5, 21), control: p(19, 21))
            path.addLine(to: p(6.5, 21))
            path.move(to: p(6.5, 3))
            path.addQuadCurve(to: p(4.5, 5), control: p(4.5, 3))
            path.addLine(to: p(4.5, 19))
            path.addQuadCurve(to: p(6.5, 21), control: p(4.5, 21))
            path.closeSubpath()
            line(&path, [p(4.6, 7.5), p(6.5, 7.5)])
            line(&path, [p(4.6, 16.5), p(6.5, 16.5)])
            line(&path, [p(19, 10.2), p(15.8, 10.2), p(15.8, 13.8), p(19, 13.8)])
            line(&path, [p(10, 8.2), p(12.2, 6.2), p(14.4, 8.2), p(12.2, 10.2)])
            path.closeSubpath()
            line(&path, [p(9.5, 13.5), p(14.7, 13.5)])
            line(&path, [p(9.5, 16), p(13.1, 16)])
        case .map:
            line(&path, [p(5, 5.5), p(19, 5.5)])
            line(&path, [p(5, 18.5), p(19, 18.5)])
            path.addRoundedRect(in: CGRect(x: 2.8, y: 4.2, width: 2.6, height: 15.6), cornerSize: CGSize(width: 1.3, height: 1.3))
            path.addRoundedRect(in: CGRect(x: 18.6, y: 4.2, width: 2.6, height: 15.6), cornerSize: CGSize(width: 1.3, height: 1.3))
            line(&path, [p(8, 11.5), p(9.8, 8.9), p(11.4, 11.2), p(12.8, 9.4), p(14.4, 11.5)])
            // Dashed route towards the destination mark.
            line(&path, [p(8.2, 15.8), p(9.2, 15.65)])
            line(&path, [p(10.4, 15.3), p(11.2, 14.9)])
            line(&path, [p(12.2, 14.5), p(13.1, 14.4)])
            line(&path, [p(14.6, 13.4), p(16.4, 15.2)])
            line(&path, [p(16.4, 13.4), p(14.6, 15.2)])
        case .phial:
            line(&path, [p(9.6, 3.2), p(14.4, 3.2)])
            line(&path, [p(10.6, 3.2), p(10.6, 6.8)])
            line(&path, [p(13.4, 3.2), p(13.4, 6.8)])
            path.move(to: p(10.6, 6.8))
            path.addCurve(to: p(5.8, 13.6), control1: p(7.3, 8), control2: p(5.8, 10.7))
            path.addCurve(to: p(12, 19.8), control1: p(5.8, 17.02), control2: p(8.58, 19.8))
            path.addCurve(to: p(18.2, 13.6), control1: p(15.42, 19.8), control2: p(18.2, 17.02))
            path.addCurve(to: p(13.4, 6.8), control1: p(18.2, 10.7), control2: p(16.7, 8))
        case .brooch:
            path.move(to: p(12, 5.2))
            path.addCurve(to: p(12, 21), control1: p(16.4, 7.8), control2: p(18.1, 12.3))
            path.addCurve(to: p(12, 5.2), control1: p(5.9, 12.3), control2: p(7.6, 7.8))
            path.closeSubpath()
            line(&path, [p(12, 7.5), p(12, 19.5)])
            line(&path, [p(10, 9.6), p(12, 11.2), p(14, 9.6)])
            line(&path, [p(9.6, 12.8), p(12, 14.6), p(14.4, 12.8)])
            path.move(to: p(12, 5.2))
            path.addCurve(to: p(14.8, 2.8), control1: p(12, 3.6), control2: p(13.2, 2.6))
        case .sting:
            line(&path, [p(12, 2.2), p(13.7, 6), p(13.3, 14.6), p(10.7, 14.6), p(10.3, 6)])
            path.closeSubpath()
            line(&path, [p(12, 5), p(12, 13.4)])
            path.move(to: p(7.4, 16.8))
            path.addCurve(to: p(12, 14.6), control1: p(8.6, 15.2), control2: p(10.2, 14.6))
            path.addCurve(to: p(16.6, 16.8), control1: p(13.8, 14.6), control2: p(15.4, 15.2))
            line(&path, [p(12, 15), p(12, 19.2)])
            path.addEllipse(in: CGRect(x: 10.7, y: 19.3, width: 2.6, height: 2.6))
        case .mountDoom:
            line(&path, [p(2.5, 20.5), p(9.4, 8.2), p(14.6, 8.2), p(21.5, 20.5)])
            path.closeSubpath()
            line(&path, [p(12, 8.2), p(11.2, 11.2), p(12.8, 13.6), p(11.6, 16.8), p(12.5, 19.4)])
            path.move(to: p(11, 5.6))
            path.addCurve(to: p(12.2, 4), control1: p(9.8, 4.6), control2: p(11.2, 3.4))
            path.addCurve(to: p(14.8, 4.8), control1: p(13, 2.6), control2: p(15.2, 3.2))
        case .pipe:
            path.move(to: p(2.6, 10.4))
            path.addCurve(to: p(14.2, 13.5), control1: p(7, 12.8), control2: p(10.6, 13.7))
            line(&path, [p(14, 13.6), p(14, 10.2), p(20.2, 10.2), p(20.2, 13.6)])
            path.addCurve(to: p(17.1, 16.7), control1: p(20.2, 15.31), control2: p(18.81, 16.7))
            path.addCurve(to: p(14, 13.6), control1: p(15.39, 16.7), control2: p(14, 15.31))
            path.move(to: p(17.1, 8))
            path.addCurve(to: p(16.9, 4.4), control1: p(15.7, 6.8), control2: p(17.9, 5.8))
            path.addCurve(to: p(16.7, 1.4), control1: p(16.1, 3.3), control2: p(17.5, 2.4))
        case .caradhras:
            line(&path, [p(2.5, 20.5), p(10, 8), p(13, 12.6), p(15, 9.8), p(21.5, 20.5)])
            path.closeSubpath()
            line(&path, [p(7.6, 12), p(9.2, 13.2), p(10.6, 11.8), p(12.2, 13.2), p(13.2, 12.1)])
        case .beacon:
            line(&path, [p(5, 16.8), p(19, 16.8), p(16.8, 20.5), p(7.2, 20.5)])
            path.closeSubpath()
            line(&path, [p(12, 20.5), p(12, 22.1)])
            line(&path, [p(8.5, 22.1), p(15.5, 22.1)])
        case .whiteTree:
            line(&path, [p(12, 21), p(12, 8.4)])
            path.move(to: p(12, 17.2))
            path.addCurve(to: p(5.6, 11), control1: p(9, 16.6), control2: p(6.6, 14.6))
            path.move(to: p(12, 17.2))
            path.addCurve(to: p(18.4, 11), control1: p(15, 16.6), control2: p(17.4, 14.6))
            path.move(to: p(12, 13.6))
            path.addCurve(to: p(8.3, 9.2), control1: p(10.2, 13), control2: p(8.8, 11.6))
            path.move(to: p(12, 13.6))
            path.addCurve(to: p(15.7, 9.2), control1: p(13.8, 13), control2: p(15.2, 11.6))
            line(&path, [p(6.6, 13.4), p(4.6, 13.8)])
            line(&path, [p(17.4, 13.4), p(19.4, 13.8)])
            line(&path, [p(9, 21), p(15, 21)])
        case .hourglass:
            line(&path, [p(5.5, 3), p(18.5, 3)])
            line(&path, [p(5.5, 21), p(18.5, 21)])
            path.move(to: p(9, 4.5))
            path.addLine(to: p(15, 4.5))
            path.addCurve(to: p(12, 12), control1: p(15, 8.5), control2: p(12, 10))
            path.addCurve(to: p(15, 19.5), control1: p(12, 14), control2: p(15, 15.5))
            path.addLine(to: p(9, 19.5))
            path.addCurve(to: p(12, 12), control1: p(9, 15.5), control2: p(12, 14))
            path.addCurve(to: p(9, 4.5), control1: p(12, 10), control2: p(9, 8.5))
            path.closeSubpath()
        case .quill:
            path.move(to: p(20.5, 3))
            path.addCurve(to: p(7.2, 16.6), control1: p(13, 4), control2: p(8.4, 9.2))
            path.addLine(to: p(8.8, 16))
            path.addCurve(to: p(20.5, 3), control1: p(15, 14.6), control2: p(19, 9.6))
            path.closeSubpath()
            line(&path, [p(7.2, 16.6), p(4.5, 20.8)])
            line(&path, [p(11, 12.6), p(14.2, 11.4)])
            line(&path, [p(12.8, 9.6), p(15.8, 8.6)])
            line(&path, [p(9.5, 21), p(19.5, 21)])
        case .letter:
            path.addRoundedRect(in: CGRect(x: 3, y: 6, width: 18, height: 12.5), cornerSize: CGSize(width: 1.2, height: 1.2))
            line(&path, [p(3.4, 6.6), p(12, 12.4)])
            line(&path, [p(20.6, 6.6), p(12, 12.4)])
        }
        return path
    }

    /// Filled with the even-odd rule, so an inner shape punches a hole.
    private var fillPath: Path {
        var path = Path()
        switch glyph {
        case .phial:
            line(&path, [p(12, 10.4), p(12.9, 12.7), p(15.2, 13.6), p(12.9, 14.5), p(12, 16.8), p(11.1, 14.5), p(8.8, 13.6), p(11.1, 12.7)])
            path.closeSubpath()
        case .caradhras:
            dot(&path, 16.5, 4.2, 0.9)
            dot(&path, 19.6, 6.6, 0.8)
            dot(&path, 5, 5.4, 0.8)
        case .beacon:
            path.move(to: p(12, 2.5))
            path.addCurve(to: p(16.6, 11.3), control1: p(12.8, 5.5), control2: p(16.6, 7.1))
            path.addCurve(to: p(12, 15.9), control1: p(16.6, 13.84), control2: p(14.54, 15.9))
            path.addCurve(to: p(7.4, 11.3), control1: p(9.46, 15.9), control2: p(7.4, 13.84))
            path.addCurve(to: p(9.6, 6.9), control1: p(7.4, 9.1), control2: p(8.8, 7.7))
            path.addCurve(to: p(11.2, 9.3), control1: p(9.6, 8.4), control2: p(10.4, 9.3))
            path.addCurve(to: p(12, 2.5), control1: p(11.2, 6.9), control2: p(10.6, 4.7))
            path.closeSubpath()
        case .whiteTree:
            dot(&path, 12, 4.6, 1.1)
            dot(&path, 7.6, 5.8, 0.9)
            dot(&path, 16.4, 5.8, 0.9)
        case .hourglass:
            line(&path, [p(10.2, 18.6), p(13.8, 18.6), p(12, 16.4)])
            path.closeSubpath()
        case .letter:
            // Wax seal with a pressed ring.
            dot(&path, 12, 13.6, 3)
            dot(&path, 12, 13.6, 1.2)
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
                    .fill(style: FillStyle(eoFill: true))
                if glyph == .ring, side >= 14 {
                    // Fire-letter inscription along the near side of the band.
                    Path { path in
                        let s = side / 24
                        let ox = proxy.size.width / 2 - 12 * s
                        let oy = proxy.size.height / 2 - 12 * s
                        path.move(to: CGPoint(x: ox + 6.2 * s, y: oy + 15.6 * s))
                        path.addQuadCurve(
                            to: CGPoint(x: ox + 17.8 * s, y: oy + 15.6 * s),
                            control: CGPoint(x: ox + 12 * s, y: oy + 18.2 * s)
                        )
                    }
                    .stroke(style: StrokeStyle(lineWidth: max(0.6, side / 24 * 0.9), lineCap: .round, dash: [side / 24 * 1.1, side / 24 * 1.2]))
                    .opacity(0.75)
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
