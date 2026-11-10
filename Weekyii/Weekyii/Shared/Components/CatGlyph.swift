import SwiftUI
import UIKit

// MARK: - 猫猫 glyph set

/// The 猫猫 (Catnap) icon set: solid silhouettes on a 24 × 24 grid with the
/// eyes, nose and folds punched out, like die-cut stickers. A 1.5 pt pencil
/// outline turned into a smudge at 18–25 pt; a filled shape with negative-space
/// features still reads as a cat at tab-bar size. Every glyph takes the current
/// foreground style, so it tints like an SF Symbol and renders as a template
/// image in the tab bar.
enum CatGlyph: String, CaseIterable {
    /// 正脸，醒着。当下 / 今日 / 进行中。
    case face
    /// 正脸，眯着眼打盹。草稿。
    case doze
    /// 蜷成一团睡觉。过去 / 冻结 / 空白。
    case curl
    /// 坐着的背影，望着一颗星。未来。
    case gaze
    /// 纸箱里探出一颗头。扩展 / 项目。
    case box
    /// 项圈上的铃铛。我的 / 设置 / VIP。
    case bell
    /// 一只肉垫。常规任务 / 有记录。
    case paw
    /// 长着猫耳的闹钟。截止任务 / 时间。
    case alarm
    /// 毛线球，拖着一截线头。休闲任务 / 习惯。
    case yarn
    /// 吃干净的鱼骨。已完成。
    case bone
    /// 一条完整的小鱼。还没吃的，留给奖励和空状态。
    case fish

    /// SF Symbol names a call site may pass that this set redraws. Anything not
    /// listed keeps its system symbol, so plain calendars and chevrons stay crisp.
    init?(systemName: String) {
        switch systemName {
        case "target", "sun.max", "sun.max.fill", "flame", "flame.fill":
            self = .face
        case "clock", "clock.fill", "hourglass", "hourglass.circle", "hourglass.circle.fill":
            self = .alarm
        case "clock.arrow.circlepath", "snowflake":
            self = .curl
        case "square.grid.2x2", "folder", "folder.fill":
            self = .box
        case "gearshape", "gearshape.fill":
            self = .bell
        case "checkmark.circle", "checkmark.circle.fill", "checkmark.seal", "checkmark.seal.fill":
            self = .bone
        case "leaf", "leaf.fill", "repeat", "repeat.circle", "repeat.circle.fill":
            self = .yarn
        default:
            return nil
        }
    }

    /// Tab-bar icons. 未来 is the cat looking out at a star; elsewhere a
    /// calendar stays a calendar.
    init?(tabSystemName systemName: String) {
        switch systemName {
        case "calendar":
            self = .gaze
        default:
            self.init(systemName: systemName)
        }
    }

    /// Built-in task types that still wear their shipped icon.
    init?(builtInType kind: TaskType, iconName: String) {
        guard iconName == kind.iconName else { return nil }
        switch kind {
        case .regular: self = .paw
        case .ddl: self = .alarm
        case .leisure: self = .yarn
        }
    }

    /// The mark inside a day-status pill.
    init(status: DayStatus) {
        switch status {
        case .empty: self = .curl
        case .draft: self = .doze
        case .execute: self = .face
        case .completed: self = .bone
        case .expired: self = .curl
        }
    }
}

// MARK: - Drawing

/// One drawing step of a glyph, in 24 × 24 grid units.
struct CatGlyphLayer {
    enum Paint {
        case fill
        case stroke(CGFloat)
    }

    let paint: Paint
    /// Punches the path out of everything drawn before it (eyes, nose, folds).
    let cuts: Bool
    let path: Path
}

extension CatGlyph {
    /// Drawn in order: the silhouette, then the cut-outs, then any strokes that
    /// sit on top (tails, alarm legs). Generated from the approved v2 preview.
    var layers: [CatGlyphLayer] {
        switch self {
        case .face:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 4.6, y: 13.6))
                p.addCurve(to: CGPoint(x: 5.8, y: 8.7), control1: CGPoint(x: 4.6, y: 11.3), control2: CGPoint(x: 5.1, y: 9.7))
                p.addLine(to: CGPoint(x: 5.4, y: 4.2))
                p.addQuadCurve(to: CGPoint(x: 6.2, y: 3.7), control: CGPoint(x: 5.4, y: 3.2))
                p.addLine(to: CGPoint(x: 9.7, y: 6.6))
                p.addQuadCurve(to: CGPoint(x: 14.3, y: 6.6), control: CGPoint(x: 12, y: 6))
                p.addLine(to: CGPoint(x: 17.8, y: 3.7))
                p.addQuadCurve(to: CGPoint(x: 18.6, y: 4.2), control: CGPoint(x: 18.6, y: 3.2))
                p.addLine(to: CGPoint(x: 18.2, y: 8.7))
                p.addCurve(to: CGPoint(x: 19.4, y: 13.6), control1: CGPoint(x: 18.9, y: 9.7), control2: CGPoint(x: 19.4, y: 11.3))
                p.addCurve(to: CGPoint(x: 12, y: 20.6), control1: CGPoint(x: 19.4, y: 18), control2: CGPoint(x: 16.2, y: 20.6))
                p.addCurve(to: CGPoint(x: 4.6, y: 13.6), control1: CGPoint(x: 7.8, y: 20.6), control2: CGPoint(x: 4.6, y: 18))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .fill, cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 7.9, y: 13.1))
                p.addCurve(to: CGPoint(x: 8.42, y: 14.27), control1: CGPoint(x: 7.9, y: 13.58), control2: CGPoint(x: 8.1, y: 14.03))
                p.addCurve(to: CGPoint(x: 9.48, y: 14.27), control1: CGPoint(x: 8.75, y: 14.51), control2: CGPoint(x: 9.15, y: 14.51))
                p.addCurve(to: CGPoint(x: 10, y: 13.1), control1: CGPoint(x: 9.8, y: 14.03), control2: CGPoint(x: 10, y: 13.58))
                p.addCurve(to: CGPoint(x: 9.48, y: 11.93), control1: CGPoint(x: 10, y: 12.62), control2: CGPoint(x: 9.8, y: 12.17))
                p.addCurve(to: CGPoint(x: 8.42, y: 11.93), control1: CGPoint(x: 9.15, y: 11.69), control2: CGPoint(x: 8.75, y: 11.69))
                p.addCurve(to: CGPoint(x: 7.9, y: 13.1), control1: CGPoint(x: 8.1, y: 12.17), control2: CGPoint(x: 7.9, y: 12.62))
                p.closeSubpath()
                p.move(to: CGPoint(x: 14, y: 13.1))
                p.addCurve(to: CGPoint(x: 14.52, y: 14.27), control1: CGPoint(x: 14, y: 13.58), control2: CGPoint(x: 14.2, y: 14.03))
                p.addCurve(to: CGPoint(x: 15.58, y: 14.27), control1: CGPoint(x: 14.85, y: 14.51), control2: CGPoint(x: 15.25, y: 14.51))
                p.addCurve(to: CGPoint(x: 16.1, y: 13.1), control1: CGPoint(x: 15.9, y: 14.03), control2: CGPoint(x: 16.1, y: 13.58))
                p.addCurve(to: CGPoint(x: 15.58, y: 11.93), control1: CGPoint(x: 16.1, y: 12.62), control2: CGPoint(x: 15.9, y: 12.17))
                p.addCurve(to: CGPoint(x: 14.52, y: 11.93), control1: CGPoint(x: 15.25, y: 11.69), control2: CGPoint(x: 14.85, y: 11.69))
                p.addCurve(to: CGPoint(x: 14, y: 13.1), control1: CGPoint(x: 14.2, y: 12.17), control2: CGPoint(x: 14, y: 12.62))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .fill, cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 11, y: 15.6))
                p.addLine(to: CGPoint(x: 13, y: 15.6))
                p.addLine(to: CGPoint(x: 12, y: 16.7))
                p.closeSubpath()
            })
            ]
        case .doze:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 4.6, y: 13.6))
                p.addCurve(to: CGPoint(x: 5.8, y: 8.7), control1: CGPoint(x: 4.6, y: 11.3), control2: CGPoint(x: 5.1, y: 9.7))
                p.addLine(to: CGPoint(x: 5.4, y: 4.2))
                p.addQuadCurve(to: CGPoint(x: 6.2, y: 3.7), control: CGPoint(x: 5.4, y: 3.2))
                p.addLine(to: CGPoint(x: 9.7, y: 6.6))
                p.addQuadCurve(to: CGPoint(x: 14.3, y: 6.6), control: CGPoint(x: 12, y: 6))
                p.addLine(to: CGPoint(x: 17.8, y: 3.7))
                p.addQuadCurve(to: CGPoint(x: 18.6, y: 4.2), control: CGPoint(x: 18.6, y: 3.2))
                p.addLine(to: CGPoint(x: 18.2, y: 8.7))
                p.addCurve(to: CGPoint(x: 19.4, y: 13.6), control1: CGPoint(x: 18.9, y: 9.7), control2: CGPoint(x: 19.4, y: 11.3))
                p.addCurve(to: CGPoint(x: 12, y: 20.6), control1: CGPoint(x: 19.4, y: 18), control2: CGPoint(x: 16.2, y: 20.6))
                p.addCurve(to: CGPoint(x: 4.6, y: 13.6), control1: CGPoint(x: 7.8, y: 20.6), control2: CGPoint(x: 4.6, y: 18))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.1), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 7.8, y: 13.4))
                p.addQuadCurve(to: CGPoint(x: 10.2, y: 13.4), control: CGPoint(x: 9, y: 14.4))
                p.move(to: CGPoint(x: 13.8, y: 13.4))
                p.addQuadCurve(to: CGPoint(x: 16.2, y: 13.4), control: CGPoint(x: 15, y: 14.4))
            }),
            CatGlyphLayer(paint: .fill, cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 11, y: 15.6))
                p.addLine(to: CGPoint(x: 13, y: 15.6))
                p.addLine(to: CGPoint(x: 12, y: 16.7))
                p.closeSubpath()
            })
            ]
        case .curl:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 12.6, y: 6.4))
                p.addCurve(to: CGPoint(x: 21, y: 13.8), control1: CGPoint(x: 17.6, y: 6.4), control2: CGPoint(x: 21, y: 9.6))
                p.addCurve(to: CGPoint(x: 12.4, y: 20.8), control1: CGPoint(x: 21, y: 18), control2: CGPoint(x: 17.4, y: 20.8))
                p.addCurve(to: CGPoint(x: 3.2, y: 14.6), control1: CGPoint(x: 7.6, y: 20.8), control2: CGPoint(x: 3.2, y: 18.6))
                p.addCurve(to: CGPoint(x: 4.3, y: 11), control1: CGPoint(x: 3.2, y: 13.2), control2: CGPoint(x: 3.6, y: 12))
                p.addLine(to: CGPoint(x: 3.9, y: 6.9))
                p.addQuadCurve(to: CGPoint(x: 4.7, y: 6.5), control: CGPoint(x: 3.9, y: 6))
                p.addLine(to: CGPoint(x: 7.6, y: 8.6))
                p.addCurve(to: CGPoint(x: 12.6, y: 6.4), control1: CGPoint(x: 9, y: 7.2), control2: CGPoint(x: 10.6, y: 6.4))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.0), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 5.3, y: 13.2))
                p.addQuadCurve(to: CGPoint(x: 7.5, y: 13.2), control: CGPoint(x: 6.4, y: 14.1))
            }),
            CatGlyphLayer(paint: .stroke(1.15), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 8.6, y: 18.3))
                p.addCurve(to: CGPoint(x: 19, y: 15), control1: CGPoint(x: 12.6, y: 19.4), control2: CGPoint(x: 17.4, y: 18.4))
            }),
            CatGlyphLayer(paint: .stroke(1.0), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 11, y: 9.2))
                p.addQuadCurve(to: CGPoint(x: 12, y: 13.2), control: CGPoint(x: 10.6, y: 11.6))
            })
            ]
        case .gaze:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 9.6, y: 3.9))
                p.addLine(to: CGPoint(x: 9.8, y: 6.4))
                p.addCurve(to: CGPoint(x: 9, y: 8.6), control1: CGPoint(x: 9.28, y: 7.02), control2: CGPoint(x: 9, y: 7.8))
                p.addCurve(to: CGPoint(x: 10.2, y: 11.2), control1: CGPoint(x: 8.98, y: 9.6), control2: CGPoint(x: 9.43, y: 10.56))
                p.addCurve(to: CGPoint(x: 6.8, y: 21), control1: CGPoint(x: 7.8, y: 12.4), control2: CGPoint(x: 6.6, y: 15.4))
                p.addLine(to: CGPoint(x: 16.6, y: 21))
                p.addCurve(to: CGPoint(x: 13.2, y: 11.2), control1: CGPoint(x: 16.9, y: 15.4), control2: CGPoint(x: 15.6, y: 12.4))
                p.addCurve(to: CGPoint(x: 14.4, y: 8.6), control1: CGPoint(x: 13.97, y: 10.56), control2: CGPoint(x: 14.42, y: 9.6))
                p.addCurve(to: CGPoint(x: 13.6, y: 6.4), control1: CGPoint(x: 14.4, y: 7.8), control2: CGPoint(x: 14.12, y: 7.02))
                p.addLine(to: CGPoint(x: 13.8, y: 3.9))
                p.addLine(to: CGPoint(x: 11.9, y: 5.4))
                p.addLine(to: CGPoint(x: 11.5, y: 5.4))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.9), cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 16.2, y: 20.6))
                p.addCurve(to: CGPoint(x: 20.4, y: 15.6), control1: CGPoint(x: 19.6, y: 20.6), control2: CGPoint(x: 21, y: 18.6))
            }),
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 19.4, y: 2.6))
                p.addLine(to: CGPoint(x: 20, y: 4.2))
                p.addLine(to: CGPoint(x: 21.6, y: 4.8))
                p.addLine(to: CGPoint(x: 20, y: 5.4))
                p.addLine(to: CGPoint(x: 19.4, y: 7))
                p.addLine(to: CGPoint(x: 18.8, y: 5.4))
                p.addLine(to: CGPoint(x: 17.2, y: 4.8))
                p.addLine(to: CGPoint(x: 18.8, y: 4.2))
                p.closeSubpath()
            })
            ]
        case .box:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 3.4, y: 12.2))
                p.addLine(to: CGPoint(x: 20.6, y: 12.2))
                p.addLine(to: CGPoint(x: 20.6, y: 19.4))
                p.addQuadCurve(to: CGPoint(x: 19, y: 21), control: CGPoint(x: 20.6, y: 21))
                p.addLine(to: CGPoint(x: 5, y: 21))
                p.addQuadCurve(to: CGPoint(x: 3.4, y: 19.4), control: CGPoint(x: 3.4, y: 21))
                p.closeSubpath()
                p.move(to: CGPoint(x: 7, y: 12.2))
                p.addCurve(to: CGPoint(x: 12, y: 8), control1: CGPoint(x: 7, y: 9.6), control2: CGPoint(x: 8.6, y: 8))
                p.addCurve(to: CGPoint(x: 17, y: 12.2), control1: CGPoint(x: 15.4, y: 8), control2: CGPoint(x: 17, y: 9.6))
                p.closeSubpath()
                p.move(to: CGPoint(x: 7.4, y: 9.6))
                p.addLine(to: CGPoint(x: 7.1, y: 5.6))
                p.addQuadCurve(to: CGPoint(x: 7.8, y: 5.2), control: CGPoint(x: 7.1, y: 4.8))
                p.addLine(to: CGPoint(x: 10.2, y: 7.3))
                p.closeSubpath()
                p.move(to: CGPoint(x: 16.6, y: 9.6))
                p.addLine(to: CGPoint(x: 16.9, y: 5.6))
                p.addQuadCurve(to: CGPoint(x: 16.2, y: 5.2), control: CGPoint(x: 16.9, y: 4.8))
                p.addLine(to: CGPoint(x: 13.8, y: 7.3))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.3), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 2.6, y: 12.6))
                p.addLine(to: CGPoint(x: 21.4, y: 12.6))
            }),
            CatGlyphLayer(paint: .fill, cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 9.3, y: 10.4))
                p.addCurve(to: CGPoint(x: 9.72, y: 11.22), control1: CGPoint(x: 9.3, y: 10.74), control2: CGPoint(x: 9.46, y: 11.05))
                p.addCurve(to: CGPoint(x: 10.58, y: 11.22), control1: CGPoint(x: 9.99, y: 11.39), control2: CGPoint(x: 10.31, y: 11.39))
                p.addCurve(to: CGPoint(x: 11, y: 10.4), control1: CGPoint(x: 10.84, y: 11.05), control2: CGPoint(x: 11, y: 10.74))
                p.addCurve(to: CGPoint(x: 10.58, y: 9.58), control1: CGPoint(x: 11, y: 10.06), control2: CGPoint(x: 10.84, y: 9.75))
                p.addCurve(to: CGPoint(x: 9.72, y: 9.58), control1: CGPoint(x: 10.31, y: 9.41), control2: CGPoint(x: 9.99, y: 9.41))
                p.addCurve(to: CGPoint(x: 9.3, y: 10.4), control1: CGPoint(x: 9.46, y: 9.75), control2: CGPoint(x: 9.3, y: 10.06))
                p.closeSubpath()
                p.move(to: CGPoint(x: 13, y: 10.4))
                p.addCurve(to: CGPoint(x: 13.42, y: 11.22), control1: CGPoint(x: 13, y: 10.74), control2: CGPoint(x: 13.16, y: 11.05))
                p.addCurve(to: CGPoint(x: 14.28, y: 11.22), control1: CGPoint(x: 13.69, y: 11.39), control2: CGPoint(x: 14.01, y: 11.39))
                p.addCurve(to: CGPoint(x: 14.7, y: 10.4), control1: CGPoint(x: 14.54, y: 11.05), control2: CGPoint(x: 14.7, y: 10.74))
                p.addCurve(to: CGPoint(x: 14.28, y: 9.58), control1: CGPoint(x: 14.7, y: 10.06), control2: CGPoint(x: 14.54, y: 9.75))
                p.addCurve(to: CGPoint(x: 13.42, y: 9.58), control1: CGPoint(x: 14.01, y: 9.41), control2: CGPoint(x: 13.69, y: 9.41))
                p.addCurve(to: CGPoint(x: 13, y: 10.4), control1: CGPoint(x: 13.16, y: 9.75), control2: CGPoint(x: 13, y: 10.06))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.0), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 8.6, y: 16.4))
                p.addLine(to: CGPoint(x: 15.4, y: 16.4))
            })
            ]
        case .bell:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 12, y: 7.2))
                p.addCurve(to: CGPoint(x: 18.59, y: 13.8), control1: CGPoint(x: 15.64, y: 7.2), control2: CGPoint(x: 18.6, y: 10.16))
                p.addCurve(to: CGPoint(x: 12, y: 20.4), control1: CGPoint(x: 18.59, y: 17.45), control2: CGPoint(x: 15.64, y: 20.4))
                p.addCurve(to: CGPoint(x: 5.4, y: 13.8), control1: CGPoint(x: 8.35, y: 20.4), control2: CGPoint(x: 5.4, y: 17.45))
                p.addCurve(to: CGPoint(x: 11.99, y: 7.2), control1: CGPoint(x: 5.39, y: 10.16), control2: CGPoint(x: 8.35, y: 7.2))
                p.closeSubpath()
                p.move(to: CGPoint(x: 10.4, y: 7.4))
                p.addLine(to: CGPoint(x: 10.6, y: 5.6))
                p.addQuadCurve(to: CGPoint(x: 13.4, y: 5.6), control: CGPoint(x: 12, y: 4.6))
                p.addLine(to: CGPoint(x: 13.6, y: 7.4))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.2), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 5.8, y: 13.3))
                p.addLine(to: CGPoint(x: 18.2, y: 13.3))
            }),
            CatGlyphLayer(paint: .fill, cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 10.9, y: 16.4))
                p.addCurve(to: CGPoint(x: 12, y: 17.5), control1: CGPoint(x: 10.9, y: 17.01), control2: CGPoint(x: 11.39, y: 17.5))
                p.addCurve(to: CGPoint(x: 13.1, y: 16.4), control1: CGPoint(x: 12.61, y: 17.5), control2: CGPoint(x: 13.1, y: 17.01))
                p.addCurve(to: CGPoint(x: 12.55, y: 15.45), control1: CGPoint(x: 13.1, y: 16.01), control2: CGPoint(x: 12.89, y: 15.64))
                p.addCurve(to: CGPoint(x: 11.45, y: 15.45), control1: CGPoint(x: 12.21, y: 15.25), control2: CGPoint(x: 11.79, y: 15.25))
                p.addCurve(to: CGPoint(x: 10.9, y: 16.4), control1: CGPoint(x: 11.11, y: 15.64), control2: CGPoint(x: 10.9, y: 16.01))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.0), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 12, y: 17.2))
                p.addLine(to: CGPoint(x: 12, y: 19.6))
            })
            ]
        case .paw:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 12, y: 12.2))
                p.addCurve(to: CGPoint(x: 17.8, y: 17.6), control1: CGPoint(x: 15.4, y: 12.2), control2: CGPoint(x: 17.8, y: 15.2))
                p.addCurve(to: CGPoint(x: 14.4, y: 20.2), control1: CGPoint(x: 17.8, y: 19.6), control2: CGPoint(x: 16.2, y: 20.6))
                p.addQuadCurve(to: CGPoint(x: 9.6, y: 20.2), control: CGPoint(x: 12, y: 19.6))
                p.addCurve(to: CGPoint(x: 6.2, y: 17.6), control1: CGPoint(x: 7.8, y: 20.6), control2: CGPoint(x: 6.2, y: 19.6))
                p.addCurve(to: CGPoint(x: 12, y: 12.2), control1: CGPoint(x: 6.2, y: 15.2), control2: CGPoint(x: 8.6, y: 12.2))
                p.closeSubpath()
                p.move(to: CGPoint(x: 4.2, y: 10.4))
                p.addCurve(to: CGPoint(x: 5.35, y: 12.9), control1: CGPoint(x: 4.15, y: 11.37), control2: CGPoint(x: 4.61, y: 12.36))
                p.addCurve(to: CGPoint(x: 7.6, y: 12.9), control1: CGPoint(x: 6.09, y: 13.45), control2: CGPoint(x: 6.98, y: 13.45))
                p.addCurve(to: CGPoint(x: 8.2, y: 10.4), control1: CGPoint(x: 8.22, y: 12.36), control2: CGPoint(x: 8.46, y: 11.37))
                p.addCurve(to: CGPoint(x: 7.05, y: 7.9), control1: CGPoint(x: 8.25, y: 9.43), control2: CGPoint(x: 7.79, y: 8.44))
                p.addCurve(to: CGPoint(x: 4.8, y: 7.9), control1: CGPoint(x: 6.31, y: 7.35), control2: CGPoint(x: 5.42, y: 7.35))
                p.addCurve(to: CGPoint(x: 4.2, y: 10.4), control1: CGPoint(x: 4.18, y: 8.44), control2: CGPoint(x: 3.94, y: 9.43))
                p.closeSubpath()
                p.move(to: CGPoint(x: 8, y: 6.4))
                p.addCurve(to: CGPoint(x: 10, y: 9), control1: CGPoint(x: 8, y: 7.84), control2: CGPoint(x: 8.9, y: 9))
                p.addCurve(to: CGPoint(x: 12, y: 6.4), control1: CGPoint(x: 11.1, y: 9), control2: CGPoint(x: 12, y: 7.84))
                p.addCurve(to: CGPoint(x: 10, y: 3.8), control1: CGPoint(x: 12, y: 4.96), control2: CGPoint(x: 11.1, y: 3.8))
                p.addCurve(to: CGPoint(x: 8, y: 6.4), control1: CGPoint(x: 8.9, y: 3.8), control2: CGPoint(x: 8, y: 4.96))
                p.closeSubpath()
                p.move(to: CGPoint(x: 12, y: 6.4))
                p.addCurve(to: CGPoint(x: 14, y: 9), control1: CGPoint(x: 12, y: 7.84), control2: CGPoint(x: 12.9, y: 9))
                p.addCurve(to: CGPoint(x: 16, y: 6.4), control1: CGPoint(x: 15.1, y: 9), control2: CGPoint(x: 16, y: 7.84))
                p.addCurve(to: CGPoint(x: 14, y: 3.8), control1: CGPoint(x: 16, y: 4.96), control2: CGPoint(x: 15.1, y: 3.8))
                p.addCurve(to: CGPoint(x: 12, y: 6.4), control1: CGPoint(x: 12.9, y: 3.8), control2: CGPoint(x: 12, y: 4.96))
                p.closeSubpath()
                p.move(to: CGPoint(x: 15.8, y: 10.4))
                p.addCurve(to: CGPoint(x: 16.4, y: 12.9), control1: CGPoint(x: 15.54, y: 11.37), control2: CGPoint(x: 15.78, y: 12.36))
                p.addCurve(to: CGPoint(x: 18.65, y: 12.9), control1: CGPoint(x: 17.02, y: 13.45), control2: CGPoint(x: 17.91, y: 13.45))
                p.addCurve(to: CGPoint(x: 19.8, y: 10.4), control1: CGPoint(x: 19.39, y: 12.36), control2: CGPoint(x: 19.85, y: 11.37))
                p.addCurve(to: CGPoint(x: 19.2, y: 7.9), control1: CGPoint(x: 20.06, y: 9.43), control2: CGPoint(x: 19.82, y: 8.44))
                p.addCurve(to: CGPoint(x: 16.95, y: 7.9), control1: CGPoint(x: 18.58, y: 7.35), control2: CGPoint(x: 17.69, y: 7.35))
                p.addCurve(to: CGPoint(x: 15.8, y: 10.4), control1: CGPoint(x: 16.21, y: 8.44), control2: CGPoint(x: 15.75, y: 9.43))
                p.closeSubpath()
            })
            ]
        case .alarm:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 12, y: 6.2))
                p.addCurve(to: CGPoint(x: 19.39, y: 13.6), control1: CGPoint(x: 16.09, y: 6.2), control2: CGPoint(x: 19.4, y: 9.52))
                p.addCurve(to: CGPoint(x: 11.99, y: 21), control1: CGPoint(x: 19.39, y: 17.69), control2: CGPoint(x: 16.08, y: 21))
                p.addCurve(to: CGPoint(x: 4.6, y: 13.6), control1: CGPoint(x: 7.91, y: 21), control2: CGPoint(x: 4.6, y: 17.69))
                p.addCurve(to: CGPoint(x: 11.99, y: 6.2), control1: CGPoint(x: 4.59, y: 9.52), control2: CGPoint(x: 7.9, y: 6.2))
                p.closeSubpath()
                p.move(to: CGPoint(x: 4.6, y: 8.6))
                p.addLine(to: CGPoint(x: 4, y: 3.6))
                p.addQuadCurve(to: CGPoint(x: 4.8, y: 3.2), control: CGPoint(x: 4, y: 2.8))
                p.addLine(to: CGPoint(x: 8.8, y: 5.8))
                p.closeSubpath()
                p.move(to: CGPoint(x: 19.4, y: 8.6))
                p.addLine(to: CGPoint(x: 20, y: 3.6))
                p.addQuadCurve(to: CGPoint(x: 19.2, y: 3.2), control: CGPoint(x: 20, y: 2.8))
                p.addLine(to: CGPoint(x: 15.2, y: 5.8))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.6), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 12, y: 9.6))
                p.addLine(to: CGPoint(x: 12, y: 13.6))
                p.addLine(to: CGPoint(x: 14.6, y: 15.4))
            }),
            CatGlyphLayer(paint: .stroke(1.6), cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 7.2, y: 20.6))
                p.addLine(to: CGPoint(x: 6, y: 22))
                p.move(to: CGPoint(x: 16.8, y: 20.6))
                p.addLine(to: CGPoint(x: 18, y: 22))
            })
            ]
        case .yarn:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 11.4, y: 4.6))
                p.addCurve(to: CGPoint(x: 18.99, y: 12.2), control1: CGPoint(x: 15.6, y: 4.6), control2: CGPoint(x: 19, y: 8.01))
                p.addCurve(to: CGPoint(x: 11.4, y: 19.8), control1: CGPoint(x: 18.99, y: 16.4), control2: CGPoint(x: 15.59, y: 19.8))
                p.addCurve(to: CGPoint(x: 3.8, y: 12.2), control1: CGPoint(x: 7.2, y: 19.8), control2: CGPoint(x: 3.8, y: 16.4))
                p.addCurve(to: CGPoint(x: 11.39, y: 4.6), control1: CGPoint(x: 3.79, y: 8.01), control2: CGPoint(x: 7.19, y: 4.6))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.05), cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 5.4, y: 9.4))
                p.addCurve(to: CGPoint(x: 16.6, y: 15.8), control1: CGPoint(x: 9, y: 9), control2: CGPoint(x: 13.6, y: 11))
                p.move(to: CGPoint(x: 4.6, y: 13.4))
                p.addCurve(to: CGPoint(x: 13, y: 19.4), control1: CGPoint(x: 8, y: 13.2), control2: CGPoint(x: 11.6, y: 15.6))
                p.move(to: CGPoint(x: 9.6, y: 5))
                p.addCurve(to: CGPoint(x: 18.8, y: 9.2), control1: CGPoint(x: 13, y: 6.4), control2: CGPoint(x: 17.6, y: 7.4))
            }),
            CatGlyphLayer(paint: .stroke(1.5), cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 17.6, y: 16.6))
                p.addCurve(to: CGPoint(x: 21.6, y: 20.6), control1: CGPoint(x: 19.6, y: 18), control2: CGPoint(x: 21, y: 18.6))
            })
            ]
        case .bone:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 2.6, y: 12))
                p.addLine(to: CGPoint(x: 6, y: 8.8))
                p.addLine(to: CGPoint(x: 6, y: 15.2))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .stroke(1.7), cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 6, y: 12))
                p.addLine(to: CGPoint(x: 17.2, y: 12))
                p.move(to: CGPoint(x: 8.8, y: 8.6))
                p.addLine(to: CGPoint(x: 8.8, y: 15.4))
                p.move(to: CGPoint(x: 11.6, y: 8))
                p.addLine(to: CGPoint(x: 11.6, y: 16))
                p.move(to: CGPoint(x: 14.4, y: 8.6))
                p.addLine(to: CGPoint(x: 14.4, y: 15.4))
            }),
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 17, y: 12))
                p.addCurve(to: CGPoint(x: 18.6, y: 14.94), control1: CGPoint(x: 17, y: 13.21), control2: CGPoint(x: 17.61, y: 14.34))
                p.addCurve(to: CGPoint(x: 21.8, y: 14.94), control1: CGPoint(x: 19.59, y: 15.55), control2: CGPoint(x: 20.81, y: 15.55))
                p.addCurve(to: CGPoint(x: 23.4, y: 12), control1: CGPoint(x: 22.79, y: 14.34), control2: CGPoint(x: 23.4, y: 13.21))
                p.addCurve(to: CGPoint(x: 21.8, y: 9.06), control1: CGPoint(x: 23.4, y: 10.79), control2: CGPoint(x: 22.79, y: 9.66))
                p.addCurve(to: CGPoint(x: 18.6, y: 9.06), control1: CGPoint(x: 20.81, y: 8.45), control2: CGPoint(x: 19.59, y: 8.45))
                p.addCurve(to: CGPoint(x: 17, y: 12), control1: CGPoint(x: 17.61, y: 9.66), control2: CGPoint(x: 17, y: 10.79))
                p.closeSubpath()
            })
            ]
        case .fish:
            return [
            CatGlyphLayer(paint: .fill, cuts: false, path: Path { p in
                p.move(to: CGPoint(x: 3, y: 12))
                p.addCurve(to: CGPoint(x: 16.6, y: 10.4), control1: CGPoint(x: 6, y: 7.6), control2: CGPoint(x: 12, y: 6.6))
                p.addLine(to: CGPoint(x: 20.6, y: 7.4))
                p.addQuadCurve(to: CGPoint(x: 21.2, y: 7.8), control: CGPoint(x: 21.4, y: 7))
                p.addLine(to: CGPoint(x: 20.2, y: 12))
                p.addLine(to: CGPoint(x: 21.2, y: 16.2))
                p.addQuadCurve(to: CGPoint(x: 20.6, y: 16.6), control: CGPoint(x: 21.4, y: 17))
                p.addLine(to: CGPoint(x: 16.6, y: 13.6))
                p.addCurve(to: CGPoint(x: 3, y: 12), control1: CGPoint(x: 12, y: 17.4), control2: CGPoint(x: 6, y: 16.4))
                p.closeSubpath()
            }),
            CatGlyphLayer(paint: .fill, cuts: true, path: Path { p in
                p.move(to: CGPoint(x: 6.6, y: 11.2))
                p.addCurve(to: CGPoint(x: 7.55, y: 12.15), control1: CGPoint(x: 6.6, y: 11.72), control2: CGPoint(x: 7.03, y: 12.15))
                p.addCurve(to: CGPoint(x: 8.5, y: 11.2), control1: CGPoint(x: 8.07, y: 12.15), control2: CGPoint(x: 8.5, y: 11.72))
                p.addCurve(to: CGPoint(x: 7.55, y: 10.25), control1: CGPoint(x: 8.5, y: 10.68), control2: CGPoint(x: 8.07, y: 10.25))
                p.addCurve(to: CGPoint(x: 6.6, y: 11.2), control1: CGPoint(x: 7.03, y: 10.25), control2: CGPoint(x: 6.6, y: 10.68))
                p.closeSubpath()
            })
            ]
        }
    }
}

/// One glyph sized by its frame, drawn in the current foreground style.
struct CatGlyphView: View {
    let glyph: CatGlyph

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            guard side > 0 else { return }
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 24, y: side / 24)
            // One transparency layer, so a die cut only erases this glyph and
            // never punches through to whatever is drawn behind the view.
            context.drawLayer { layerContext in
                for layer in glyph.layers {
                    var step = layerContext
                    step.blendMode = layer.cuts ? .destinationOut : .normal
                    switch layer.paint {
                    case .fill:
                        step.fill(layer.path, with: .foreground)
                    case .stroke(let width):
                        step.stroke(
                            layer.path,
                            with: .foreground,
                            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
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
                .frame(width: 26, height: 26)
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

/// Two ears, each a rounded triangle with its base on the bottom edge of the
/// rect. Used on the focus panel (the panel is the cat) and over the wordmark.
struct CatEarPairShape: Shape {
    /// Draw only the smaller inner ear, inset from the outer one.
    var inner: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        func ear(baseLeft: CGFloat, tip: CGFloat, baseRight: CGFloat) {
            let tipPoint = CGPoint(x: rect.minX + w * tip, y: rect.minY + h * (inner ? 0.42 : 0.0))
            let left = CGPoint(x: rect.minX + w * baseLeft, y: rect.maxY)
            let right = CGPoint(x: rect.minX + w * baseRight, y: rect.maxY)
            // A short rounded cap at the tip instead of a sharp point.
            let capIn = h * (inner ? 0.08 : 0.14)
            path.move(to: left)
            path.addLine(to: CGPoint(x: tipPoint.x - (tipPoint.x - left.x) * 0.1, y: tipPoint.y + capIn))
            path.addQuadCurve(
                to: CGPoint(x: tipPoint.x + (right.x - tipPoint.x) * 0.1, y: tipPoint.y + capIn),
                control: tipPoint
            )
            path.addLine(to: right)
            path.closeSubpath()
        }
        if inner {
            ear(baseLeft: 0.12, tip: 0.15, baseRight: 0.24)
            ear(baseLeft: 0.76, tip: 0.85, baseRight: 0.88)
        } else {
            ear(baseLeft: 0.02, tip: 0.13, baseRight: 0.35)
            ear(baseLeft: 0.65, tip: 0.87, baseRight: 0.98)
        }
        return path
    }
}

/// A tail that drops out of the panel's bottom trailing corner and curls back.
/// Stroked with a round cap at roughly the width of the panel's corner radius.
struct CatTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 60 * rect.width, y: rect.minY + y / 30 * rect.height)
        }
        path.move(to: q(4, 2))
        path.addCurve(to: q(46, 20), control1: q(14, 20), control2: q(34, 26))
        path.addCurve(to: q(50, 6), control1: q(54, 16), control2: q(56, 8))
        return path
    }
}
