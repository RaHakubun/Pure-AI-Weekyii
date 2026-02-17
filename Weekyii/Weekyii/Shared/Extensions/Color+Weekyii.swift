import SwiftUI

enum WeekTheme: String, CaseIterable, Codable, Identifiable {
    case amber
    case ocean
    case forest
    case rose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amber: return "琥珀"
        case .ocean: return "海蓝"
        case .forest: return "森绿"
        case .rose: return "玫瑰"
        }
    }
}

private struct WeekThemePalette {
    let primary: String
    let primaryLight: String
    let primaryDark: String
    let accentOrange: String
    let accentOrangeLight: String
    let accentGreen: String
    let accentGreenLight: String
    let accentPink: String
    let backgroundPrimary: String
    let backgroundSecondary: String
    let backgroundTertiary: String
    let textPrimary: String
    let textSecondary: String
    let textTertiary: String
    let taskRegular: String
    let taskRegularBg: String
    let taskDDL: String
    let taskDDLBg: String
    let taskLeisure: String
    let taskLeisureBg: String

    static func forTheme(_ theme: WeekTheme) -> WeekThemePalette {
        switch theme {
        case .amber:
            return WeekThemePalette(
                primary: "#C46A1A",
                primaryLight: "#E0A35B",
                primaryDark: "#8A4A13",
                accentOrange: "#F08A3C",
                accentOrangeLight: "#F4AE77",
                accentGreen: "#3FA67A",
                accentGreenLight: "#6DC7A3",
                accentPink: "#D97A6C",
                backgroundPrimary: "#FFF7EE",
                backgroundSecondary: "#FFFDF9",
                backgroundTertiary: "#F6EDE3",
                textPrimary: "#2A1D16",
                textSecondary: "#6B5A4F",
                textTertiary: "#9B887C",
                taskRegular: "#2F7E79",
                taskRegularBg: "#D9F0EC",
                taskDDL: "#D05C3E",
                taskDDLBg: "#F8E1DB",
                taskLeisure: "#8C6AD9",
                taskLeisureBg: "#EFE8FB"
            )
        case .ocean:
            return WeekThemePalette(
                primary: "#2A6FA1",
                primaryLight: "#5AA3D1",
                primaryDark: "#1D4F73",
                accentOrange: "#F28D49",
                accentOrangeLight: "#F7B787",
                accentGreen: "#2E9B8C",
                accentGreenLight: "#66C3B7",
                accentPink: "#D86F8B",
                backgroundPrimary: "#F2F8FD",
                backgroundSecondary: "#FCFEFF",
                backgroundTertiary: "#E7F0F7",
                textPrimary: "#172A3A",
                textSecondary: "#4B667A",
                textTertiary: "#7D93A2",
                taskRegular: "#2A7A91",
                taskRegularBg: "#D8EDF4",
                taskDDL: "#D36345",
                taskDDLBg: "#F9E3DC",
                taskLeisure: "#6E78D8",
                taskLeisureBg: "#E8EBFB"
            )
        case .forest:
            return WeekThemePalette(
                primary: "#2E7D4E",
                primaryLight: "#5BA879",
                primaryDark: "#205737",
                accentOrange: "#D9903D",
                accentOrangeLight: "#E8B37A",
                accentGreen: "#2F9B6A",
                accentGreenLight: "#66C394",
                accentPink: "#C97563",
                backgroundPrimary: "#F4FAF6",
                backgroundSecondary: "#FEFFFE",
                backgroundTertiary: "#E8F1EA",
                textPrimary: "#1E2C22",
                textSecondary: "#4F6657",
                textTertiary: "#7A8F80",
                taskRegular: "#2E8071",
                taskRegularBg: "#D7EFE9",
                taskDDL: "#C95D3E",
                taskDDLBg: "#F5E2DB",
                taskLeisure: "#7B70CC",
                taskLeisureBg: "#EAE7F7"
            )
        case .rose:
            return WeekThemePalette(
                primary: "#B85C7A",
                primaryLight: "#D98EA8",
                primaryDark: "#7E3F54",
                accentOrange: "#E18A4E",
                accentOrangeLight: "#F0B88D",
                accentGreen: "#3A9A7B",
                accentGreenLight: "#70C2A6",
                accentPink: "#D86B87",
                backgroundPrimary: "#FFF5F8",
                backgroundSecondary: "#FFFDFE",
                backgroundTertiary: "#F6EAF0",
                textPrimary: "#321D27",
                textSecondary: "#6E4D5B",
                textTertiary: "#9B7C89",
                taskRegular: "#337E83",
                taskRegularBg: "#DDF0F1",
                taskDDL: "#D16449",
                taskDDLBg: "#F9E5DF",
                taskLeisure: "#8A69CB",
                taskLeisureBg: "#EFE8FA"
            )
        }
    }
}

private enum WeekThemeRuntime {
    private static var cachedThemeRaw = ""
    private static var cachedPalette = WeekThemePalette.forTheme(.amber)

    static func palette() -> WeekThemePalette {
        let raw = UserDefaults.standard.string(forKey: "selectedTheme") ?? WeekTheme.amber.rawValue
        if raw != cachedThemeRaw {
            cachedThemeRaw = raw
            cachedPalette = WeekThemePalette.forTheme(WeekTheme(rawValue: raw) ?? .amber)
        }
        return cachedPalette
    }
}

// MARK: - Weekyii Design System - Colors

extension Color {
    // MARK: Primary Colors - 主品牌色
    
    /// 深琥珀 - 主品牌色
    static var weekyiiPrimary: Color { Color(hex: WeekThemeRuntime.palette().primary) }
    
    /// 亮琥珀 - 主品牌色(浅色)
    static var weekyiiPrimaryLight: Color { Color(hex: WeekThemeRuntime.palette().primaryLight) }
    
    /// 深琥珀 - 主品牌色(深色)
    static var weekyiiPrimaryDark: Color { Color(hex: WeekThemeRuntime.palette().primaryDark) }
    
    // MARK: Accent Colors - 强调色
    
    /// 温暖橙 - 强调色,用于重要操作
    static var accentOrange: Color { Color(hex: WeekThemeRuntime.palette().accentOrange) }
    
    /// 浅橙色
    static var accentOrangeLight: Color { Color(hex: WeekThemeRuntime.palette().accentOrangeLight) }
    
    /// 温润绿 - 成功/完成状态
    static var accentGreen: Color { Color(hex: WeekThemeRuntime.palette().accentGreen) }
    
    /// 浅绿色
    static var accentGreenLight: Color { Color(hex: WeekThemeRuntime.palette().accentGreenLight) }
    
    /// 柔和珊瑚 - 休闲/轻松元素
    static var accentPink: Color { Color(hex: WeekThemeRuntime.palette().accentPink) }
    
    // MARK: Background Colors - 背景色系
    
    /// 主背景色
    static var backgroundPrimary: Color { Color(hex: WeekThemeRuntime.palette().backgroundPrimary) }
    
    /// 卡片背景色
    static var backgroundSecondary: Color { Color(hex: WeekThemeRuntime.palette().backgroundSecondary) }
    
    /// 次级区域背景色
    static var backgroundTertiary: Color { Color(hex: WeekThemeRuntime.palette().backgroundTertiary) }
    
    // MARK: Text Colors - 文字色系
    
    /// 主文字颜色
    static var textPrimary: Color { Color(hex: WeekThemeRuntime.palette().textPrimary) }
    
    /// 次要文字颜色
    static var textSecondary: Color { Color(hex: WeekThemeRuntime.palette().textSecondary) }
    
    /// 辅助文字颜色
    static var textTertiary: Color { Color(hex: WeekThemeRuntime.palette().textTertiary) }
    
    // MARK: Task Type Colors - 任务类型色彩
    
    /// Regular 任务 - 青蓝色系
    static var taskRegular: Color { Color(hex: WeekThemeRuntime.palette().taskRegular) }
    static var taskRegularBg: Color { Color(hex: WeekThemeRuntime.palette().taskRegularBg) }
    
    /// DDL 任务 - 锈橙色系
    static var taskDDL: Color { Color(hex: WeekThemeRuntime.palette().taskDDL) }
    static var taskDDLBg: Color { Color(hex: WeekThemeRuntime.palette().taskDDLBg) }
    
    /// Leisure 任务 - 李子色系
    static var taskLeisure: Color { Color(hex: WeekThemeRuntime.palette().taskLeisure) }
    static var taskLeisureBg: Color { Color(hex: WeekThemeRuntime.palette().taskLeisureBg) }
    
    // MARK: Gradients - 渐变
    
    /// Weekyii 主渐变
    static var weekyiiGradient: LinearGradient {
        LinearGradient(
            colors: [Color.weekyiiPrimary, Color.weekyiiPrimaryLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// 橙色渐变
    static var orangeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentOrange, Color.accentOrangeLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// 绿色渐变
    static var greenGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentGreen, Color.accentGreenLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
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
