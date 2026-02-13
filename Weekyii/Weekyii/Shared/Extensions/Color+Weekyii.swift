import SwiftUI

// MARK: - Weekyii Design System - Colors

extension Color {
    // MARK: Primary Colors - 主品牌色
    
    /// 深琥珀 - 主品牌色
    static let weekyiiPrimary = Color(hex: "#C46A1A")
    
    /// 亮琥珀 - 主品牌色(浅色)
    static let weekyiiPrimaryLight = Color(hex: "#E0A35B")
    
    /// 深琥珀 - 主品牌色(深色)
    static let weekyiiPrimaryDark = Color(hex: "#8A4A13")
    
    // MARK: Accent Colors - 强调色
    
    /// 温暖橙 - 强调色,用于重要操作
    static let accentOrange = Color(hex: "#F08A3C")
    
    /// 浅橙色
    static let accentOrangeLight = Color(hex: "#F4AE77")
    
    /// 温润绿 - 成功/完成状态
    static let accentGreen = Color(hex: "#3FA67A")
    
    /// 浅绿色
    static let accentGreenLight = Color(hex: "#6DC7A3")
    
    /// 柔和珊瑚 - 休闲/轻松元素
    static let accentPink = Color(hex: "#D97A6C")
    
    // MARK: Background Colors - 背景色系
    
    /// 主背景色
    static let backgroundPrimary = Color(hex: "#FFF7EE")
    
    /// 卡片背景色
    static let backgroundSecondary = Color(hex: "#FFFDF9")
    
    /// 次级区域背景色
    static let backgroundTertiary = Color(hex: "#F6EDE3")
    
    // MARK: Text Colors - 文字色系
    
    /// 主文字颜色
    static let textPrimary = Color(hex: "#2A1D16")
    
    /// 次要文字颜色
    static let textSecondary = Color(hex: "#6B5A4F")
    
    /// 辅助文字颜色
    static let textTertiary = Color(hex: "#9B887C")
    
    // MARK: Task Type Colors - 任务类型色彩
    
    /// Regular 任务 - 青蓝色系
    static let taskRegular = Color(hex: "#2F7E79")
    static let taskRegularBg = Color(hex: "#D9F0EC")
    
    /// DDL 任务 - 锈橙色系
    static let taskDDL = Color(hex: "#D05C3E")
    static let taskDDLBg = Color(hex: "#F8E1DB")
    
    /// Leisure 任务 - 李子色系
    static let taskLeisure = Color(hex: "#8C6AD9")
    static let taskLeisureBg = Color(hex: "#EFE8FB")
    
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
