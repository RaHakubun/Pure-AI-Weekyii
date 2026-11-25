import SwiftUI

// MARK: - Weekyii Design System - Typography

extension Font {
    // MARK: Display - 超大标题
    
    /// 超大标题 - 用于品牌标识
    static var displayLarge: Font { WeekTypography.title(size: 46, weight: .bold) }
    
    // MARK: Titles - 标题系列
    
    /// 大标题 - 用于页面标题
    static var titleLarge: Font { WeekTypography.title(size: 32, weight: .bold) }
    
    /// 中标题 - 用于 Section 标题
    static var titleMedium: Font { WeekTypography.title(size: 22, weight: .semibold) }
    
    /// 小标题 - 用于卡片标题
    static var titleSmall: Font { WeekTypography.title(size: 18, weight: .semibold) }
    
    // MARK: Body - 正文系列
    
    /// 大正文
    static var bodyLarge: Font { WeekTypography.body(size: 17, weight: .regular) }
    
    /// 中正文
    static var bodyMedium: Font { WeekTypography.body(size: 15, weight: .regular) }
    
    /// 小正文
    static var bodySmall: Font { WeekTypography.body(size: 13, weight: .regular) }
    
    // MARK: Caption - 辅助文字
    
    /// 说明文字
    static var caption: Font { WeekTypography.body(size: 13, weight: .regular) }
    
    /// 粗体说明文字
    static var captionBold: Font { WeekTypography.body(size: 13, weight: .semibold) }
    
    /// 小说明文字
    static var captionSmall: Font { WeekTypography.body(size: 11, weight: .regular) }
}

// MARK: - Theme-aware font resolution

/// Resolves the design-system fonts against the active theme's typography, so a
/// personalised theme can swap serif titles for monospaced or black grotesque
/// faces without any call site changing. Classic themes resolve to exactly the
/// fonts these tokens always produced (serif titles, default body).
enum WeekTypography {
    static func title(size: CGFloat, weight: Font.Weight) -> Font {
        let typography = ThemeSkin.active.typography
        return .system(size: size, weight: typography.titleWeight ?? weight, design: typography.titleDesign)
    }

    static func body(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: ThemeSkin.active.typography.bodyDesign)
    }
}

// MARK: - Text Styles

extension Text {
    /// 应用品牌标题样式
    func brandTitleStyle() -> some View {
        self
            .font(.displayLarge)
            .foregroundStyle(Color.weekyiiGradient)
    }
    
    /// 应用页面标题样式
    func pageTitleStyle() -> some View {
        self
            .font(.titleLarge)
            .foregroundColor(.textPrimary)
    }
    
    /// 应用 Section 标题样式
    func sectionTitleStyle() -> some View {
        self
            .font(.titleMedium)
            .foregroundColor(.textPrimary)
    }
    
    /// 应用卡片标题样式
    func cardTitleStyle() -> some View {
        self
            .font(.titleSmall)
            .foregroundColor(.textPrimary)
    }
    
    /// 应用次要文字样式
    func secondaryTextStyle() -> some View {
        self
            .font(.bodyMedium)
            .foregroundColor(.textSecondary)
    }
    
    /// 应用说明文字样式
    func captionStyle() -> some View {
        self
            .font(.caption)
            .foregroundColor(.textTertiary)
    }
}
