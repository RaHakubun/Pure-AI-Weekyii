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
        color: Color.black.opacity(0.05),
        radius: 8,
        x: 0,
        y: 2
    )
    
    /// 中等阴影 - 用于浮动元素
    static let medium = WeekShadow(
        color: Color.black.opacity(0.1),
        radius: 16,
        x: 0,
        y: 4
    )
    
    /// 强阴影 - 用于 Modal
    static let strong = WeekShadow(
        color: Color.black.opacity(0.15),
        radius: 24,
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
