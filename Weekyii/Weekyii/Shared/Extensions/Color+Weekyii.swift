import SwiftUI

// MARK: - Weekyii Design System - Colors

extension Color {
    // MARK: Primary Colors - 主品牌色
    
    /// 深邃蓝紫 - 主品牌色
    static let weekyiiPrimary = Color(hex: "#5B4FE9")
    
    /// 浅紫蓝 - 主品牌色(浅色)
    static let weekyiiPrimaryLight = Color(hex: "#7C6FF2")
    
    /// 暗紫蓝 - 主品牌色(深色)
    static let weekyiiPrimaryDark = Color(hex: "#4A3FD8")
    
    // MARK: Accent Colors - 强调色
    
    /// 温暖橙 - 强调色,用于重要操作
    static let accentOrange = Color(hex: "#FF8A5B")
    
    /// 浅橙色
    static let accentOrangeLight = Color(hex: "#FFA07A")
    
    /// 清新绿 - 成功/完成状态
    static let accentGreen = Color(hex: "#4ECDC4")
    
    /// 浅绿色
    static let accentGreenLight = Color(hex: "#6EDDD5")
    
    /// 柔和粉 - 休闲/轻松元素
    static let accentPink = Color(hex: "#FF6B9D")
    
    // MARK: Background Colors - 背景色系
    
    /// 主背景色
    static let backgroundPrimary = Color(hex: "#F8F9FA")
    
    /// 卡片背景色
    static let backgroundSecondary = Color(hex: "#FFFFFF")
    
    /// 次级区域背景色
    static let backgroundTertiary = Color(hex: "#F0F2F5")
    
    // MARK: Text Colors - 文字色系
    
    /// 主文字颜色
    static let textPrimary = Color(hex: "#1A1A1A")
    
    /// 次要文字颜色
    static let textSecondary = Color(hex: "#6B7280")
    
    /// 辅助文字颜色
    static let textTertiary = Color(hex: "#9CA3AF")
    
    // MARK: Task Type Colors - 任务类型色彩
    
    /// Regular 任务 - 蓝色系
    static let taskRegular = Color(hex: "#3B82F6")
    static let taskRegularBg = Color(hex: "#DBEAFE")
    
    /// DDL 任务 - 红橙色系
    static let taskDDL = Color(hex: "#EF4444")
    static let taskDDLBg = Color(hex: "#FEE2E2")
    
    /// Leisure 任务 - 紫粉色系
    static let taskLeisure = Color(hex: "#A855F7")
    static let taskLeisureBg = Color(hex: "#F3E8FF")
    
    // MARK: Gradients - 渐变
    
    /// Weekyii 主渐变
    static let weekyiiGradient = LinearGradient(
        colors: [Color.weekyiiPrimary, Color.weekyiiPrimaryLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// 橙色渐变
    static let orangeGradient = LinearGradient(
        colors: [Color.accentOrange, Color.accentOrangeLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// 绿色渐变
    static let greenGradient = LinearGradient(
        colors: [Color.accentGreen, Color.accentGreenLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Helper: Hex Color Initializer
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
