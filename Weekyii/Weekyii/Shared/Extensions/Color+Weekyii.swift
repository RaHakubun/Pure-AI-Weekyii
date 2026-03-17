import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum WeekTheme: String, CaseIterable, Codable, Identifiable {
    case amber
    case ocean
    case forest
    case rose
    case lavender
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amber: return "琥珀"
        case .ocean: return "海蓝"
        case .forest: return "森绿"
        case .rose: return "玫瑰"
        case .lavender: return "薰紫"
        case .graphite: return "石墨"
        }
    }

    var primaryColor: Color {
        Color(hex: palettePair.light.primary)
    }

    var accentColor: Color {
        Color(hex: palettePair.light.accentOrange)
    }

    var backgroundColor: Color {
        Color(hex: palettePair.light.backgroundSecondary)
    }

    var primaryThemeHex: String {
        palettePair.light.primary
    }

    var primaryThemeLightHex: String {
        palettePair.light.primaryLight
    }

    var widgetAccentHex: String {
        palettePair.light.accentOrange
    }

    var widgetBackgroundHex: String {
        palettePair.light.backgroundSecondary
    }

    var widgetTextPrimaryHex: String {
        palettePair.light.textPrimary
    }

    var widgetTextSecondaryHex: String {
        palettePair.light.textSecondary
    }

    var suspendedModulePalette: SemanticModulePalette {
        SemanticModulePalette(
            tintHex: primaryThemeHex,
            tintLightHex: primaryThemeLightHex
        )
    }

    func palette(for appearanceMode: AppearanceMode, systemIsDark: Bool) -> WeekThemePalette {
        switch appearanceMode {
        case .light:
            return palettePair.light
        case .dark:
            return palettePair.dark
        case .system:
            return systemIsDark ? palettePair.dark : palettePair.light
        }
    }

    func widgetThemeSnapshot(appearanceMode: AppearanceMode) -> WidgetThemeSnapshot {
        WidgetThemeSnapshot(
            primaryHex: palettePair.light.primary,
            primaryLightHex: palettePair.light.primaryLight,
            accentHex: palettePair.light.accentOrange,
            backgroundHex: palettePair.light.backgroundSecondary,
            textPrimaryHex: palettePair.light.textPrimary,
            textSecondaryHex: palettePair.light.textSecondary,
            darkPrimaryHex: palettePair.dark.primary,
            darkPrimaryLightHex: palettePair.dark.primaryLight,
            darkAccentHex: palettePair.dark.accentOrange,
            darkBackgroundHex: palettePair.dark.backgroundSecondary,
            darkTextPrimaryHex: palettePair.dark.textPrimary,
            darkTextSecondaryHex: palettePair.dark.textSecondary,
            appearanceModeRaw: appearanceMode.rawValue
        )
    }

    private var palettePair: WeekThemePalettePair {
        WeekThemePalettePair.forTheme(self)
    }
}

struct SemanticModulePalette: Equatable {
    let tintHex: String
    let tintLightHex: String
}

struct WeekThemePalette {
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
}

private struct WeekThemePalettePair {
    let light: WeekThemePalette
    let dark: WeekThemePalette

    static func forTheme(_ theme: WeekTheme) -> WeekThemePalettePair {
        switch theme {
        case .amber:
            return WeekThemePalettePair(
                light: WeekThemePalette(
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
                ),
                dark: WeekThemePalette(
                    primary: "#E0A35B",
                    primaryLight: "#F2C284",
                    primaryDark: "#8A4A13",
                    accentOrange: "#F4AE77",
                    accentOrangeLight: "#F7C9A5",
                    accentGreen: "#62C9A0",
                    accentGreenLight: "#8FDCBC",
                    accentPink: "#E39B8E",
                    backgroundPrimary: "#18120E",
                    backgroundSecondary: "#221A14",
                    backgroundTertiary: "#2E241D",
                    textPrimary: "#F7EBDD",
                    textSecondary: "#D2BDA9",
                    textTertiary: "#A98F79",
                    taskRegular: "#6ECBC3",
                    taskRegularBg: "#1E3C3A",
                    taskDDL: "#F18B70",
                    taskDDLBg: "#3D241F",
                    taskLeisure: "#B99AF0",
                    taskLeisureBg: "#2F2644"
                )
            )
        case .ocean:
            return WeekThemePalettePair(
                light: WeekThemePalette(
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
                ),
                dark: WeekThemePalette(
                    primary: "#5AA3D1",
                    primaryLight: "#8EC5E6",
                    primaryDark: "#1D4F73",
                    accentOrange: "#F7B787",
                    accentOrangeLight: "#F9CCAB",
                    accentGreen: "#5BC4B2",
                    accentGreenLight: "#85D8CB",
                    accentPink: "#E59BB0",
                    backgroundPrimary: "#0F1A24",
                    backgroundSecondary: "#15222F",
                    backgroundTertiary: "#1E2F40",
                    textPrimary: "#EAF4FC",
                    textSecondary: "#BED3E3",
                    textTertiary: "#8BA4B8",
                    taskRegular: "#73C8DE",
                    taskRegularBg: "#183543",
                    taskDDL: "#F19174",
                    taskDDLBg: "#3A2520",
                    taskLeisure: "#98A0EE",
                    taskLeisureBg: "#252B45"
                )
            )
        case .forest:
            return WeekThemePalettePair(
                light: WeekThemePalette(
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
                ),
                dark: WeekThemePalette(
                    primary: "#5BA879",
                    primaryLight: "#83C59A",
                    primaryDark: "#205737",
                    accentOrange: "#E8B37A",
                    accentOrangeLight: "#EEC79D",
                    accentGreen: "#63C995",
                    accentGreenLight: "#8BDCB3",
                    accentPink: "#DFA090",
                    backgroundPrimary: "#111B15",
                    backgroundSecondary: "#18251D",
                    backgroundTertiary: "#223328",
                    textPrimary: "#E8F5EC",
                    textSecondary: "#B6CFBC",
                    textTertiary: "#869E8B",
                    taskRegular: "#74CEBE",
                    taskRegularBg: "#173833",
                    taskDDL: "#E98669",
                    taskDDLBg: "#3A2520",
                    taskLeisure: "#A39AE8",
                    taskLeisureBg: "#272544"
                )
            )
        case .rose:
            return WeekThemePalettePair(
                light: WeekThemePalette(
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
                ),
                dark: WeekThemePalette(
                    primary: "#D98EA8",
                    primaryLight: "#EAB4C6",
                    primaryDark: "#7E3F54",
                    accentOrange: "#F0B88D",
                    accentOrangeLight: "#F4CCAD",
                    accentGreen: "#67C3A2",
                    accentGreenLight: "#90D8BE",
                    accentPink: "#EB9EB5",
                    backgroundPrimary: "#1C1217",
                    backgroundSecondary: "#261920",
                    backgroundTertiary: "#33222B",
                    textPrimary: "#F9EAF0",
                    textSecondary: "#D8B8C6",
                    textTertiary: "#AA8796",
                    taskRegular: "#73C1C7",
                    taskRegularBg: "#1B363B",
                    taskDDL: "#EE8F73",
                    taskDDLBg: "#3C2521",
                    taskLeisure: "#B49CE8",
                    taskLeisureBg: "#2C2842"
                )
            )
        case .lavender:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#7C5295",
                    primaryLight: "#9E7BB5",
                    primaryDark: "#5A3870",
                    accentOrange: "#E68C55",
                    accentOrangeLight: "#F2B99C",
                    accentGreen: "#4B9A84",
                    accentGreenLight: "#7DC4B1",
                    accentPink: "#CF729C",
                    backgroundPrimary: "#F8F5FA",
                    backgroundSecondary: "#FEFDFE",
                    backgroundTertiary: "#EFEAF4",
                    textPrimary: "#291F2F",
                    textSecondary: "#605068",
                    textTertiary: "#8C7B94",
                    taskRegular: "#4B7C95",
                    taskRegularBg: "#E0EFF5",
                    taskDDL: "#C36154",
                    taskDDLBg: "#F8E6E3",
                    taskLeisure: "#9162CC",
                    taskLeisureBg: "#F2EBFC"
                ),
                dark: WeekThemePalette(
                    primary: "#9E7BB5",
                    primaryLight: "#B89BCC",
                    primaryDark: "#5A3870",
                    accentOrange: "#F2B99C",
                    accentOrangeLight: "#F5CDB7",
                    accentGreen: "#77C8AF",
                    accentGreenLight: "#9ADDC8",
                    accentPink: "#E09EBE",
                    backgroundPrimary: "#16131B",
                    backgroundSecondary: "#201A28",
                    backgroundTertiary: "#2B2336",
                    textPrimary: "#EFE8F6",
                    textSecondary: "#C9BCD8",
                    textTertiary: "#9888AA",
                    taskRegular: "#8CBEDC",
                    taskRegularBg: "#1D3340",
                    taskDDL: "#E58679",
                    taskDDLBg: "#392523",
                    taskLeisure: "#B79AEF",
                    taskLeisureBg: "#2E2745"
                )
            )
        case .graphite:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#444A52",
                    primaryLight: "#6B727A",
                    primaryDark: "#2B3036",
                    accentOrange: "#D48B4C",
                    accentOrangeLight: "#E8B78C",
                    accentGreen: "#449277",
                    accentGreenLight: "#77BB9F",
                    accentPink: "#C56877",
                    backgroundPrimary: "#F5F6F8",
                    backgroundSecondary: "#FFFFFF",
                    backgroundTertiary: "#EBECEF",
                    textPrimary: "#1C1F22",
                    textSecondary: "#565D65",
                    textTertiary: "#828991",
                    taskRegular: "#4A7885",
                    taskRegularBg: "#E2F0F4",
                    taskDDL: "#C55B51",
                    taskDDLBg: "#F7E6E5",
                    taskLeisure: "#7A6CB8",
                    taskLeisureBg: "#EDEAF6"
                ),
                dark: WeekThemePalette(
                    primary: "#8D96A1",
                    primaryLight: "#B0B7C0",
                    primaryDark: "#2B3036",
                    accentOrange: "#E8B78C",
                    accentOrangeLight: "#F1CFB0",
                    accentGreen: "#74C7A7",
                    accentGreenLight: "#9ADABD",
                    accentPink: "#DA9DA8",
                    backgroundPrimary: "#111214",
                    backgroundSecondary: "#181A1E",
                    backgroundTertiary: "#24272D",
                    textPrimary: "#E7EAF0",
                    textSecondary: "#BDC4CF",
                    textTertiary: "#8E97A5",
                    taskRegular: "#84B8C8",
                    taskRegularBg: "#1C3139",
                    taskDDL: "#E6847A",
                    taskDDLBg: "#372423",
                    taskLeisure: "#A99EE0",
                    taskLeisureBg: "#2B2840"
                )
            )
        }
    }
}

private enum WeekThemeRuntime {
    private static var cachedThemeRaw = ""
    private static var cachedPalettePair = WeekThemePalettePair.forTheme(.amber)

    private static var selectedTheme: WeekTheme {
        let raw = UserDefaults.standard.string(forKey: "selectedTheme") ?? WeekTheme.amber.rawValue
        if raw != cachedThemeRaw {
            cachedThemeRaw = raw
            cachedPalettePair = WeekThemePalettePair.forTheme(WeekTheme(rawValue: raw) ?? .amber)
        }
        return WeekTheme(rawValue: raw) ?? .amber
    }

    private static var appearanceMode: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: WeekyiiWidgetBridge.appearanceModeKey) ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }

    private static var palettePair: WeekThemePalettePair {
        _ = selectedTheme
        return cachedPalettePair
    }

    static func semanticColor(_ keyPath: KeyPath<WeekThemePalette, String>) -> Color {
        let lightHex = palettePair.light[keyPath: keyPath]
        let darkHex = palettePair.dark[keyPath: keyPath]

        switch appearanceMode {
        case .light:
            return Color(hex: lightHex)
        case .dark:
            return Color(hex: darkHex)
        case .system:
            return Color.dynamic(lightHex: lightHex, darkHex: darkHex)
        }
    }
}

// MARK: - Weekyii Design System - Colors

extension Color {
    // MARK: Primary Colors - 主品牌色

    /// 深琥珀 - 主品牌色
    static var weekyiiPrimary: Color { WeekThemeRuntime.semanticColor(\.primary) }

    /// 亮琥珀 - 主品牌色(浅色)
    static var weekyiiPrimaryLight: Color { WeekThemeRuntime.semanticColor(\.primaryLight) }

    /// 深琥珀 - 主品牌色(深色)
    static var weekyiiPrimaryDark: Color { WeekThemeRuntime.semanticColor(\.primaryDark) }

    /// 悬置箱模块主色，跟随应用主题主色切换
    static var suspendedModuleTint: Color { .weekyiiPrimary }

    /// 悬置箱模块浅色停靠点
    static var suspendedModuleTintLight: Color { .weekyiiPrimaryLight }

    // MARK: Accent Colors - 强调色

    /// 温暖橙 - 强调色,用于重要操作
    static var accentOrange: Color { WeekThemeRuntime.semanticColor(\.accentOrange) }

    /// 浅橙色
    static var accentOrangeLight: Color { WeekThemeRuntime.semanticColor(\.accentOrangeLight) }

    /// 温润绿 - 成功/完成状态
    static var accentGreen: Color { WeekThemeRuntime.semanticColor(\.accentGreen) }

    /// 浅绿色
    static var accentGreenLight: Color { WeekThemeRuntime.semanticColor(\.accentGreenLight) }

    /// 柔和珊瑚 - 休闲/轻松元素
    static var accentPink: Color { WeekThemeRuntime.semanticColor(\.accentPink) }

    // MARK: Background Colors - 背景色系

    /// 主背景色
    static var backgroundPrimary: Color { WeekThemeRuntime.semanticColor(\.backgroundPrimary) }

    /// 卡片背景色
    static var backgroundSecondary: Color { WeekThemeRuntime.semanticColor(\.backgroundSecondary) }

    /// 次级区域背景色
    static var backgroundTertiary: Color { WeekThemeRuntime.semanticColor(\.backgroundTertiary) }

    // MARK: Text Colors - 文字色系

    /// 主文字颜色
    static var textPrimary: Color { WeekThemeRuntime.semanticColor(\.textPrimary) }

    /// 次要文字颜色
    static var textSecondary: Color { WeekThemeRuntime.semanticColor(\.textSecondary) }

    /// 辅助文字颜色
    static var textTertiary: Color { WeekThemeRuntime.semanticColor(\.textTertiary) }

    // MARK: Task Type Colors - 任务类型色彩

    /// Regular 任务 - 青蓝色系
    static var taskRegular: Color { WeekThemeRuntime.semanticColor(\.taskRegular) }
    static var taskRegularBg: Color { WeekThemeRuntime.semanticColor(\.taskRegularBg) }

    /// DDL 任务 - 锈橙色系
    static var taskDDL: Color { WeekThemeRuntime.semanticColor(\.taskDDL) }
    static var taskDDLBg: Color { WeekThemeRuntime.semanticColor(\.taskDDLBg) }

    /// Leisure 任务 - 李子色系
    static var taskLeisure: Color { WeekThemeRuntime.semanticColor(\.taskLeisure) }
    static var taskLeisureBg: Color { WeekThemeRuntime.semanticColor(\.taskLeisureBg) }

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

    /// 悬置箱模块渐变，跟随应用主题主色切换
    static var suspendedModuleGradient: LinearGradient {
        LinearGradient(
            colors: [Color.suspendedModuleTint, Color.suspendedModuleTintLight],
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

    static func dynamic(lightHex: String, darkHex: String) -> Color {
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { trait in
                UIColor(hex: trait.userInterfaceStyle == .dark ? darkHex : lightHex)
            }
        )
        #else
        return Color(hex: lightHex)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}
#endif
