import SwiftUI
import UIKit

// MARK: - 猫猫 glyph set

/// Hand-drawn cat line art for the 猫猫 theme. Each glyph sits on a 24 × 24
/// grid with a 2 pt margin, a 1.5 pt round stroke and no fill, so it reads like
/// a pencil sketch and takes the current foreground style.
enum CatGlyph: String, CaseIterable {
    /// 今日 / 专注：正面趴着，两只前爪收在身下。
    case loaf
    /// 过去 / 冻结 / 空白：蜷成一团睡觉。
    case curl
    /// 完成：前低后高地伸懒腰。
    case stretch
    /// 草稿 / 截止：打哈欠，眼睛闭成两道弧。
    case yawn
    /// 常规任务：单只爪印。
    case paw
    /// 卷起来的尾巴。
    case tailCurl
    /// 休闲：毛线球。
    case yarnBall
    /// 截止任务：鱼骨。
    case fishBone
    /// 周 / 月：猫窝坐垫。
    case cushion
    /// 时间：牛奶碟。
    case saucer
    /// 扩展：纸箱。
    case box
    /// 设置：三根胡须。
    case whisker

    /// SF Symbol names a call site may pass that this set redraws.
    init?(systemName: String) {
        switch systemName {
        case "target", "sun.max", "sun.max.fill":
            self = .loaf
        case "clock", "clock.fill", "hourglass", "hourglass.circle", "hourglass.circle.fill":
            self = .saucer
        case "clock.arrow.circlepath":
            self = .curl
        case "calendar", "calendar.badge.clock", "calendar.badge.checkmark", "calendar.badge.plus":
            self = .cushion
        case "square.grid.2x2":
            self = .box
        case "folder", "folder.fill":
            self = .box
        case "gearshape", "gearshape.fill":
            self = .whisker
        case "checkmark.circle", "checkmark.circle.fill", "checkmark.seal", "checkmark.seal.fill":
            self = .stretch
        case "flame", "flame.fill":
            self = .yawn
        case "leaf", "leaf.fill":
            self = .yarnBall
        case "snowflake":
            self = .curl
        default:
            return nil
        }
    }

    /// Built-in task types that still wear their shipped icon.
    init?(builtInType kind: TaskType, iconName: String) {
        guard iconName == kind.iconName else { return nil }
        switch kind {
        case .regular: self = .paw
        case .ddl: self = .fishBone
        case .leisure: self = .yarnBall
        }
    }

    /// The mark tucked into a day-status badge.
    init(status: DayStatus) {
        switch status {
        case .empty: self = .curl
        case .draft: self = .yawn
        case .execute: self = .loaf
        case .completed: self = .stretch
        case .expired: self = .curl
        }
    }
}

// MARK: - Drawing

private struct CatGlyphShape: Shape {
    enum Layer {
        case stroke
        case fill
    }

    let glyph: CatGlyph
    let layer: Layer

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard side > 0 else { return Path() }
        let scale = side / 24
        let path = layer == .stroke ? strokePath : fillPath
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -12, y: -12)
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

    private func dot(_ path: inout Path, _ x: CGFloat, _ y: CGFloat) {
        let r: CGFloat = 0.6
        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func curve(_ path: inout Path, _ to: CGPoint, _ c1: CGPoint, _ c2: CGPoint) {
        path.addCurve(to: to, control1: c1, control2: c2)
    }

    private var strokePath: Path {
        var path = Path()
        switch glyph {
        case .loaf:
            // Ears and cheeks in one stroke. The chin stops where the loaf starts.
            path.move(to: p(7.6, 13.8))
            curve(&path, p(9.0, 8.6), p(6.2, 11.6), p(6.6, 9.4))
            line(&path, [p(9.0, 8.6), p(6.5, 3.3), p(11.3, 8.0)])
            curve(&path, p(13.1, 8.0), p(12.0, 6.7), p(12.4, 6.7))
            line(&path, [p(13.1, 8.0), p(17.7, 3.5), p(15.4, 8.7)])
            curve(&path, p(16.6, 13.9), p(17.6, 9.6), p(18.0, 12.0))
            path.move(to: p(4.0, 15.2))
            curve(&path, p(4.4, 19.6), p(2.6, 16.6), p(2.8, 19.2))
            curve(&path, p(19.6, 19.7), p(8.0, 21.2), p(16.2, 21.3))
            curve(&path, p(20.0, 15.1), p(21.4, 19.2), p(21.6, 16.6))
            curve(&path, p(4.0, 15.2), p(16.4, 13.2), p(7.6, 13.1))
            path.move(to: p(8.4, 19.2))
            curve(&path, p(10.8, 19.3), p(8.8, 17.4), p(10.4, 17.4))
            path.move(to: p(12.6, 19.2))
            curve(&path, p(15.0, 19.4), p(13.0, 17.3), p(14.6, 17.4))
            path.move(to: p(18.2, 16.6))
            curve(&path, p(21.2, 11.4), p(21.2, 16.4), p(21.8, 13.2))
            curve(&path, p(19.2, 10.8), p(20.6, 10.2), p(19.6, 10.2))
            line(&path, [p(7.2, 12.2), p(3.6, 11.2)])
            line(&path, [p(7.0, 13.2), p(3.4, 13.4)])
            line(&path, [p(7.2, 14.2), p(3.8, 15.2)])
            line(&path, [p(16.6, 12.3), p(20.2, 11.2)])
            line(&path, [p(16.8, 13.3), p(20.4, 13.5)])
            line(&path, [p(16.6, 14.3), p(20.0, 15.3)])
            path.move(to: p(11.2, 13.3))
            curve(&path, p(12.8, 13.4), p(11.6, 14.2), p(12.4, 14.2))
            line(&path, [p(8.2, 7.6), p(7.6, 5.0), p(10.2, 7.4)])
            line(&path, [p(14.0, 7.4), p(16.4, 5.2), p(15.2, 8.0)])
        case .curl:
            path.addEllipse(in: CGRect(x: 6.4, y: 7.6, width: 13.2, height: 12.4))
            path.move(to: p(16.8, 16.4))
            curve(&path, p(19.6, 8.2), p(21.2, 15.2), p(21.6, 10.4))
            curve(&path, p(15.2, 6.6), p(17.6, 5.6), p(15.4, 5.4))
            path.addEllipse(in: CGRect(x: 3.2, y: 5.2, width: 8.4, height: 7.6))
            line(&path, [p(5.0, 7.2), p(3.8, 3.2), p(6.8, 6.4)])
            line(&path, [p(6.6, 6.2), p(8.6, 3.0), p(9.2, 6.8)])
            path.move(to: p(5.2, 8.4))
            curve(&path, p(6.8, 8.5), p(5.6, 7.5), p(6.4, 7.5))
            path.move(to: p(7.4, 8.2))
            curve(&path, p(9.0, 8.4), p(7.8, 7.3), p(8.6, 7.3))
        case .stretch:
            line(&path, [p(2.2, 18.6), p(2.2, 16.2)])
            line(&path, [p(4.4, 18.8), p(4.4, 16.4)])
            path.move(to: p(2.4, 16.4))
            curve(&path, p(7.2, 13.2), p(2.6, 14.6), p(4.8, 13.6))
            curve(&path, p(6.2, 8.6), p(5.4, 12.2), p(4.2, 10.2))
            line(&path, [p(6.2, 8.6), p(5.2, 5.2), p(8.0, 8.2), p(9.6, 5.4), p(9.8, 8.8)])
            curve(&path, p(12.4, 12.6), p(12.2, 8.4), p(12.6, 10.6))
            curve(&path, p(20.2, 8.4), p(14.8, 9.2), p(17.2, 6.6))
            curve(&path, p(19.2, 15.6), p(21.8, 10.2), p(21.6, 14.2))
            curve(&path, p(5.2, 16.8), p(15.2, 17.4), p(9.4, 18.2))
            line(&path, [p(18.2, 15.4), p(18.0, 18.6)])
            line(&path, [p(20.2, 14.8), p(21.2, 17.6)])
            path.move(to: p(19.6, 9.2))
            curve(&path, p(21.4, 3.8), p(21.6, 7.6), p(21.8, 4.8))
            curve(&path, p(19.4, 4.6), p(20.6, 2.8), p(19.6, 3.4))
            path.move(to: p(7.2, 10.4))
            curve(&path, p(9.0, 10.6), p(7.8, 9.6), p(8.4, 9.6))
        case .yawn:
            // Open face: the cheeks do not close into a ring under the mouth.
            path.move(to: p(8.2, 8.6))
            line(&path, [p(8.2, 8.6), p(6.4, 3.4), p(11.2, 8.0)])
            curve(&path, p(13.2, 7.9), p(12.0, 6.6), p(12.4, 6.6))
            line(&path, [p(13.2, 7.9), p(17.8, 3.6), p(15.6, 8.8)])
            curve(&path, p(16.4, 14.4), p(18.0, 10.6), p(17.6, 13.2))
            path.move(to: p(8.2, 8.6))
            curve(&path, p(7.4, 14.2), p(5.6, 10.2), p(5.8, 13.0))
            path.move(to: p(9.0, 11.0))
            curve(&path, p(11.2, 11.1), p(9.6, 9.8), p(10.6, 9.8))
            path.move(to: p(12.8, 11.0))
            curve(&path, p(15.0, 11.2), p(13.4, 9.8), p(14.4, 9.8))
            path.move(to: p(10.2, 13.2))
            curve(&path, p(13.8, 13.3), p(10.6, 15.4), p(13.4, 15.5))
            line(&path, [p(11.2, 13.4), p(12.0, 14.6), p(12.8, 13.5)])
            path.move(to: p(5.4, 16.4))
            curve(&path, p(6.2, 20.4), p(3.6, 17.6), p(3.8, 20.0))
            curve(&path, p(17.8, 20.2), p(9.4, 21.6), p(14.8, 21.4))
            curve(&path, p(18.4, 16.2), p(20.2, 19.4), p(20.4, 16.8))
            path.move(to: p(8.6, 19.6))
            curve(&path, p(11.0, 19.8), p(9.0, 18.2), p(10.6, 18.2))
            path.move(to: p(12.8, 19.6))
            curve(&path, p(15.2, 19.8), p(13.2, 18.2), p(14.8, 18.2))
        case .paw:
            path.addEllipse(in: CGRect(x: 7.4, y: 11.2, width: 9.2, height: 8.0))
            path.addEllipse(in: CGRect(x: 5.2, y: 6.6, width: 3.3, height: 4.0))
            path.addEllipse(in: CGRect(x: 8.8, y: 4.2, width: 3.2, height: 3.8))
            path.addEllipse(in: CGRect(x: 12.2, y: 4.3, width: 3.2, height: 3.8))
            path.addEllipse(in: CGRect(x: 15.6, y: 6.8, width: 3.2, height: 3.8))
        case .tailCurl:
            path.move(to: p(5.0, 18.4))
            curve(&path, p(16.8, 16.2), p(8.0, 18.8), p(12.4, 19.6))
            curve(&path, p(18.4, 7.2), p(21.4, 12.2), p(21.6, 7.6))
            curve(&path, p(12.6, 8.8), p(15.6, 4.2), p(12.2, 5.4))
            curve(&path, p(13.8, 12.6), p(13.0, 11.2), p(14.8, 11.6))
        case .yarnBall:
            path.addEllipse(in: CGRect(x: 4.2, y: 5.6, width: 14.2, height: 14.0))
            path.move(to: p(5.6, 12.4))
            curve(&path, p(17.2, 11.2), p(8.4, 7.2), p(13.6, 7.0))
            path.move(to: p(6.4, 16.0))
            curve(&path, p(16.2, 15.2), p(9.6, 13.2), p(13.2, 12.6))
            path.move(to: p(8.6, 7.2))
            curve(&path, p(14.8, 6.8), p(10.4, 5.4), p(13.0, 5.2))
            path.move(to: p(16.8, 8.6))
            curve(&path, p(21.2, 4.6), p(19.4, 9.4), p(21.4, 6.6))
            curve(&path, p(19.6, 4.2), p(20.6, 3.4), p(19.8, 3.6))
        case .fishBone:
            path.addEllipse(in: CGRect(x: 2.2, y: 9.6, width: 4.4, height: 4.6))
            line(&path, [p(6.2, 11.9), p(18.6, 11.8)])
            line(&path, [p(8.4, 11.9), p(6.6, 8.2)])
            line(&path, [p(8.4, 11.9), p(6.8, 15.6)])
            line(&path, [p(11.6, 11.9), p(10.2, 7.8)])
            line(&path, [p(11.6, 11.9), p(10.4, 16.0)])
            line(&path, [p(14.8, 11.8), p(13.8, 8.2)])
            line(&path, [p(14.8, 11.8), p(14.0, 15.4)])
            line(&path, [p(18.6, 11.8), p(21.4, 8.4)])
            line(&path, [p(18.6, 11.8), p(21.4, 15.2)])
            path.move(to: p(3.4, 11.2))
            curve(&path, p(4.6, 12.2), p(3.8, 11.8), p(4.2, 12.0))
        case .cushion:
            path.move(to: p(3.2, 12.4))
            curve(&path, p(4.6, 18.8), p(2.2, 15.2), p(2.6, 18.4))
            curve(&path, p(19.6, 18.6), p(8.0, 21.0), p(16.0, 20.8))
            curve(&path, p(20.6, 12.2), p(21.6, 17.6), p(21.8, 14.4))
            curve(&path, p(3.2, 12.4), p(16.4, 9.2), p(7.2, 9.4))
            path.move(to: p(5.2, 14.6))
            curve(&path, p(18.6, 14.4), p(9.0, 16.8), p(14.8, 16.6))
            path.addEllipse(in: CGRect(x: 11.1, y: 14.8, width: 1.8, height: 1.8))
        case .saucer:
            path.addEllipse(in: CGRect(x: 2.6, y: 10.4, width: 18.8, height: 7.6))
            path.move(to: p(5.4, 13.6))
            curve(&path, p(18.6, 13.4), p(9.0, 16.2), p(15.2, 16.0))
            path.move(to: p(7.2, 12.2))
            curve(&path, p(16.6, 12.0), p(10.0, 10.2), p(14.0, 10.0))
        case .box:
            line(&path, [p(3.4, 10.2), p(3.6, 20.2), p(20.4, 20.0), p(20.2, 10.0), p(3.4, 10.2)])
            line(&path, [p(3.4, 10.2), p(6.2, 5.2), p(11.6, 8.6)])
            line(&path, [p(20.2, 10.0), p(17.6, 5.0), p(12.0, 8.4)])
            path.move(to: p(14.2, 10.2))
            curve(&path, p(19.2, 6.4), p(16.6, 10.4), p(18.6, 8.2))
            curve(&path, p(17.6, 5.8), p(19.6, 5.2), p(18.2, 5.0))
        case .whisker:
            path.move(to: p(10.6, 11.2))
            curve(&path, p(13.4, 11.4), p(11.2, 13.4), p(12.8, 13.6))
            line(&path, [p(10.4, 11.4), p(2.8, 8.4)])
            line(&path, [p(10.2, 12.2), p(2.6, 12.4)])
            line(&path, [p(10.4, 13.0), p(3.0, 16.2)])
            line(&path, [p(13.6, 11.6), p(21.2, 8.4)])
            line(&path, [p(13.8, 12.4), p(21.4, 12.6)])
            line(&path, [p(13.6, 13.2), p(21.0, 16.4)])
            path.addEllipse(in: CGRect(x: 11.5, y: 11.2, width: 1.2, height: 1.2))
        }
        return path
    }

    private var fillPath: Path {
        var path = Path()
        switch glyph {
        case .loaf:
            dot(&path, 10.4, 11.4)
            dot(&path, 14.0, 11.6)
        default:
            break
        }
        return path
    }
}

/// One glyph sized by its frame, drawn in the current foreground style.
struct CatGlyphView: View {
    let glyph: CatGlyph

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let width = max(0.8, side / 24 * 1.5)
            ZStack {
                CatGlyphShape(glyph: glyph, layer: .stroke)
                    .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                CatGlyphShape(glyph: glyph, layer: .fill)
                    .fill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Tab bar images

/// `tabItem` only accepts an `Image`, so the cat glyphs are rendered once into
/// template images the tab bar can tint.
@MainActor
enum CatTabIcon {
    private static var cache: [CatGlyph: UIImage] = [:]

    static func image(_ glyph: CatGlyph, fallbackSystemName: String) -> Image {
        if let cached = cache[glyph] {
            return Image(uiImage: cached)
        }
        let renderer = ImageRenderer(
            content: CatGlyphView(glyph: glyph)
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

/// SF Symbol at call sites that are not on the shared `ThemedSymbol` path.
/// Cat redraws the symbol when this set has one; every other theme keeps the
/// system image, including its font, so those themes do not move.
struct CatCoveredSymbol: View {
    let systemName: String
    var pointSize: CGFloat
    @Environment(\.themeSkin) private var skin

    var body: some View {
        if skin.glyphs == .cat, let glyph = CatGlyph(systemName: systemName) {
            CatGlyphView(glyph: glyph)
                .frame(width: pointSize, height: pointSize)
        } else {
            Image(systemName: systemName)
        }
    }
}

// MARK: - Ornaments

/// A lazy tail drawn across the focus cover, in the same slot as the Ring's
/// letter band. Ornament only: it is a curve, not lettering.
struct CatTailInscription: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX + 2, y: y + 1.2))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.46, y: y - 1.6),
            control1: CGPoint(x: rect.minX + rect.width * 0.16, y: y + 4.2),
            control2: CGPoint(x: rect.minX + rect.width * 0.30, y: y - 4.4)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.18, y: y + 1.4),
            control1: CGPoint(x: rect.minX + rect.width * 0.62, y: y + 2.8),
            control2: CGPoint(x: rect.maxX - rect.width * 0.32, y: y - 3.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 4, y: y - 1.2),
            control: CGPoint(x: rect.maxX - rect.width * 0.06, y: y + 4.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.14, y: y + 2.2),
            control: CGPoint(x: rect.maxX - 1, y: y - 3.4)
        )
        return path
    }
}

/// The small paw that closes a section rule. Drawn in the same 10 × 7 slot as
/// the Ring theme's ellipse, so the header row does not grow.
struct CatPawMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
            path.addEllipse(in: CGRect(
                x: rect.minX + cx - rx,
                y: rect.minY + cy - ry,
                width: rx * 2,
                height: ry * 2
            ))
        }
        let w = rect.width
        let h = rect.height
        oval(w * 0.28, h * 0.30, w * 0.10, h * 0.14)
        oval(w * 0.50, h * 0.18, w * 0.10, h * 0.13)
        oval(w * 0.72, h * 0.32, w * 0.09, h * 0.13)
        oval(w * 0.50, h * 0.68, w * 0.24, h * 0.22)
        return path
    }
}
