import SwiftUI

// MARK: - Weekyii Design System - Typography

extension Font {
    // MARK: Display - 超大标题
    
    /// 超大标题 - 用于品牌标识
    static let displayLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    
    // MARK: Titles - 标题系列
    
    /// 大标题 - 用于页面标题
    static let titleLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    
    /// 中标题 - 用于 Section 标题
    static let titleMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
    
    /// 小标题 - 用于卡片标题
    static let titleSmall = Font.system(size: 18, weight: .semibold, design: .rounded)
    
    // MARK: Body - 正文系列
    
    /// 大正文
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    
    /// 中正文
    static let bodyMedium = Font.system(size: 15, weight: .regular, design: .default)
    
    /// 小正文
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
    
    // MARK: Caption - 辅助文字
    
    /// 说明文字
    static let caption = Font.system(size: 13, weight: .regular, design: .default)
    
    /// 粗体说明文字
    static let captionBold = Font.system(size: 13, weight: .semibold, design: .default)
    
    /// 小说明文字
    static let captionSmall = Font.system(size: 11, weight: .regular, design: .default)
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
