import SwiftUI

// MARK: - Weekyii Design System - Spacing & Layout

enum WeekSpacing {
    /// 2pt - 最小间距
    static let xxs: CGFloat = 2
    
    /// 4pt - 极小间距
    static let xs: CGFloat = 4
    
    /// 8pt - 小间距
    static let sm: CGFloat = 8
    
    /// 12pt - 中小间距
    static let md: CGFloat = 12
    
    /// 16pt - 中等间距(默认)
    static let base: CGFloat = 16
    
    /// 20pt - 中大间距
    static let lg: CGFloat = 20
    
    /// 24pt - 大间距
    static let xl: CGFloat = 24
    
    /// 32pt - 超大间距
    static let xxl: CGFloat = 32
    
    /// 40pt - 巨大间距
    static let xxxl: CGFloat = 40
}

// MARK: - Responsive Layout

/// Weekyii responds to the width of its current window rather than the device
/// model. This keeps iPad split view and Stage Manager layouts usable when the
/// app is resized down to an iPhone-like width.
enum WeekLayoutClass: String, Sendable {
    case compact
    case regular
    case wide

    init(availableWidth: CGFloat) {
        switch availableWidth {
        case ..<650:
            self = .compact
        case ..<1000:
            self = .regular
        default:
            self = .wide
        }
    }

    var supportsSidebar: Bool {
        self != .compact
    }

    var supportsTwoColumns: Bool {
        self != .compact
    }
}

struct WeekLayoutMetrics: Equatable, Sendable {
    let availableWidth: CGFloat
    let layoutClass: WeekLayoutClass

    init(availableWidth: CGFloat) {
        self.availableWidth = max(availableWidth, 0)
        self.layoutClass = WeekLayoutClass(availableWidth: availableWidth)
    }

    static let compact = WeekLayoutMetrics(availableWidth: 390)

    var pageHorizontalPadding: CGFloat {
        switch layoutClass {
        case .compact:
            return WeekSpacing.base
        case .regular:
            return WeekSpacing.xl
        case .wide:
            return WeekSpacing.xxl
        }
    }

    var pageMaxWidth: CGFloat {
        switch layoutClass {
        case .compact:
            return .infinity
        case .regular:
            return 920
        case .wide:
            return 1240
        }
    }

    var auxiliaryColumnWidth: CGFloat {
        switch layoutClass {
        case .compact:
            return availableWidth
        case .regular:
            return 286
        case .wide:
            return 332
        }
    }

    var formMaxWidth: CGFloat {
        layoutClass == .compact ? .infinity : 680
    }
}

private struct WeekLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = WeekLayoutMetrics.compact
}

extension EnvironmentValues {
    var weekLayoutMetrics: WeekLayoutMetrics {
        get { self[WeekLayoutMetricsKey.self] }
        set { self[WeekLayoutMetricsKey.self] = newValue }
    }
}

// MARK: - Corner Radius

enum WeekRadius {
    /// 8pt - 小圆角
    static let small: CGFloat = 8
    
    /// 12pt - 中等圆角
    static let medium: CGFloat = 12
    
    /// 16pt - 大圆角
    static let large: CGFloat = 16
    
    /// 24pt - 超大圆角
    static let xlarge: CGFloat = 24
    
    /// 完全圆角
    static let full: CGFloat = 999
}

// MARK: - Shadows

struct WeekShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    /// 轻微阴影 - 用于卡片
    static let light = WeekShadow(
        color: Color.dynamic(lightHex: "#3A2A22", darkHex: "#000000").opacity(0.08),
        radius: 10,
        x: 0,
        y: 3
    )
    
    /// 中等阴影 - 用于浮动元素
    static let medium = WeekShadow(
        color: Color.dynamic(lightHex: "#3A2A22", darkHex: "#000000").opacity(0.16),
        radius: 18,
        x: 0,
        y: 5
    )
    
    /// 强阴影 - 用于 Modal
    static let strong = WeekShadow(
        color: Color.dynamic(lightHex: "#3A2A22", darkHex: "#000000").opacity(0.24),
        radius: 26,
        x: 0,
        y: 8
    )
}

// MARK: - View Extensions

extension View {
    /// 应用 Weekyii 卡片样式
    func weekCardStyle(shadow: WeekShadow = .light) -> some View {
        self
            .background(Color.backgroundSecondary)
            .cornerRadius(WeekRadius.large)
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    /// 应用标准内边距
    func weekPadding(_ size: CGFloat = WeekSpacing.base) -> some View {
        self.padding(size)
    }
    
    /// 应用水平内边距
    func weekPaddingHorizontal(_ size: CGFloat = WeekSpacing.base) -> some View {
        self.padding(.horizontal, size)
    }
    
    /// 应用垂直内边距
    func weekPaddingVertical(_ size: CGFloat = WeekSpacing.base) -> some View {
        self.padding(.vertical, size)
    }
}
