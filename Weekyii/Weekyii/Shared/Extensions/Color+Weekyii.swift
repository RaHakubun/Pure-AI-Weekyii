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
    case sunset
    case mint
    case midnight
    case lotr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amber: return "琥珀"
        case .ocean: return "海蓝"
        case .forest: return "森绿"
        case .rose: return "玫瑰"
        case .lavender: return "薰紫"
        case .graphite: return "石墨"
        case .sunset: return "落日"
        case .mint: return "薄荷"
        case .midnight: return "极夜"
        case .lotr: return "魔戒"
        }
    }

    var isPremiumTheme: Bool {
        self == .lotr
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

    static func resolvedTheme(rawValue: String?, premiumThemeUnlocked: Bool) -> WeekTheme {
        let requestedTheme = WeekTheme(rawValue: rawValue ?? "") ?? .amber
        guard requestedTheme.isPremiumTheme, !premiumThemeUnlocked else {
            return requestedTheme
        }
        return .amber
    }

    static var activeTheme: WeekTheme {
        let defaults = WeekyiiWidgetBridge.sharedDefaults()
        return resolvedTheme(
            rawValue: defaults.string(forKey: WeekyiiWidgetBridge.selectedThemeKey),
            premiumThemeUnlocked: defaults.bool(forKey: WeekyiiWidgetBridge.premiumThemeUnlockedKey)
        )
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
        case .sunset:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#C8643A",
                    primaryLight: "#E49368",
                    primaryDark: "#8E4227",
                    accentOrange: "#F0974E",
                    accentOrangeLight: "#F7BE89",
                    accentGreen: "#4C9B7C",
                    accentGreenLight: "#7CC3A7",
                    accentPink: "#D86F7D",
                    backgroundPrimary: "#FFF4ED",
                    backgroundSecondary: "#FFFDFC",
                    backgroundTertiary: "#F8E9E0",
                    textPrimary: "#311F19",
                    textSecondary: "#71584D",
                    textTertiary: "#9D8376",
                    taskRegular: "#327F8A",
                    taskRegularBg: "#DDF0F3",
                    taskDDL: "#D56244",
                    taskDDLBg: "#FAE4DC",
                    taskLeisure: "#8D66CC",
                    taskLeisureBg: "#F0E9FB"
                ),
                dark: WeekThemePalette(
                    primary: "#E49368",
                    primaryLight: "#F1B189",
                    primaryDark: "#8E4227",
                    accentOrange: "#F7BE89",
                    accentOrangeLight: "#F9CFAD",
                    accentGreen: "#76C8A6",
                    accentGreenLight: "#9CDBBD",
                    accentPink: "#E7A2AD",
                    backgroundPrimary: "#1A120F",
                    backgroundSecondary: "#241915",
                    backgroundTertiary: "#32221D",
                    textPrimary: "#F8ECE6",
                    textSecondary: "#D8BEB2",
                    textTertiary: "#AC8F82",
                    taskRegular: "#7BC8D7",
                    taskRegularBg: "#1B3640",
                    taskDDL: "#F09579",
                    taskDDLBg: "#3B2520",
                    taskLeisure: "#B79BEF",
                    taskLeisureBg: "#2E2746"
                )
            )
        case .mint:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#2E8F84",
                    primaryLight: "#61B6A8",
                    primaryDark: "#1F5F58",
                    accentOrange: "#DF8D48",
                    accentOrangeLight: "#EDB987",
                    accentGreen: "#349F79",
                    accentGreenLight: "#6FCAA5",
                    accentPink: "#CC718A",
                    backgroundPrimary: "#F2FBF8",
                    backgroundSecondary: "#FCFFFE",
                    backgroundTertiary: "#E5F3EF",
                    textPrimary: "#1B2D2A",
                    textSecondary: "#4A6A64",
                    textTertiary: "#79968F",
                    taskRegular: "#2E7E93",
                    taskRegularBg: "#D8EEF4",
                    taskDDL: "#C9644B",
                    taskDDLBg: "#F8E4DE",
                    taskLeisure: "#7A6ED0",
                    taskLeisureBg: "#ECE9FB"
                ),
                dark: WeekThemePalette(
                    primary: "#61B6A8",
                    primaryLight: "#8BD0C4",
                    primaryDark: "#1F5F58",
                    accentOrange: "#EDB987",
                    accentOrangeLight: "#F2CAA6",
                    accentGreen: "#65CEAB",
                    accentGreenLight: "#8FE0C1",
                    accentPink: "#E2A6B8",
                    backgroundPrimary: "#0F1917",
                    backgroundSecondary: "#162421",
                    backgroundTertiary: "#20332E",
                    textPrimary: "#E8F6F2",
                    textSecondary: "#BCD9D1",
                    textTertiary: "#8EA9A2",
                    taskRegular: "#7CCBE0",
                    taskRegularBg: "#183542",
                    taskDDL: "#EA8D78",
                    taskDDLBg: "#392522",
                    taskLeisure: "#AA9CEE",
                    taskLeisureBg: "#282643"
                )
            )
        case .midnight:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#33558C",
                    primaryLight: "#678BC6",
                    primaryDark: "#223A60",
                    accentOrange: "#D98A49",
                    accentOrangeLight: "#EAB88D",
                    accentGreen: "#3F8F79",
                    accentGreenLight: "#73BDA4",
                    accentPink: "#B76C8D",
                    backgroundPrimary: "#F2F5FB",
                    backgroundSecondary: "#FCFDFF",
                    backgroundTertiary: "#E6EBF5",
                    textPrimary: "#1A2334",
                    textSecondary: "#4B5D79",
                    textTertiary: "#7688A4",
                    taskRegular: "#3B7894",
                    taskRegularBg: "#DCECF4",
                    taskDDL: "#C45D4C",
                    taskDDLBg: "#F8E5E1",
                    taskLeisure: "#7668C7",
                    taskLeisureBg: "#EBE8FA"
                ),
                dark: WeekThemePalette(
                    primary: "#7DA2DF",
                    primaryLight: "#A2BDEB",
                    primaryDark: "#223A60",
                    accentOrange: "#EAB88D",
                    accentOrangeLight: "#F0CAAA",
                    accentGreen: "#73C2A8",
                    accentGreenLight: "#98D7BF",
                    accentPink: "#DAA1B8",
                    backgroundPrimary: "#070C14",
                    backgroundSecondary: "#0E1521",
                    backgroundTertiary: "#172235",
                    textPrimary: "#E8F0FF",
                    textSecondary: "#BDCCE6",
                    textTertiary: "#8999B5",
                    taskRegular: "#7FBFDC",
                    taskRegularBg: "#173243",
                    taskDDL: "#E38E7E",
                    taskDDLBg: "#372422",
                    taskLeisure: "#A99BE9",
                    taskLeisureBg: "#272543"
                )
            )
        case .lotr:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#8A6A2A",
                    primaryLight: "#C7A55E",
                    primaryDark: "#5D4520",
                    accentOrange: "#B86A2D",
                    accentOrangeLight: "#D99A63",
                    accentGreen: "#6C7852",
                    accentGreenLight: "#A4B28A",
                    accentPink: "#A67B67",
                    backgroundPrimary: "#F3EBDE",
                    backgroundSecondary: "#FBF7F0",
                    backgroundTertiary: "#E8DDCF",
                    textPrimary: "#261F17",
                    textSecondary: "#5B4A3D",
                    textTertiary: "#8E7D6C",
                    taskRegular: "#6B7C54",
                    taskRegularBg: "#E4EAD9",
                    taskDDL: "#A95A2C",
                    taskDDLBg: "#F5DFD0",
                    taskLeisure: "#7B5B9D",
                    taskLeisureBg: "#ECE5F7"
                ),
                dark: WeekThemePalette(
                    primary: "#C7A55E",
                    primaryLight: "#E0BE84",
                    primaryDark: "#6E5225",
                    accentOrange: "#D28A4D",
                    accentOrangeLight: "#E1AE79",
                    accentGreen: "#7A8C62",
                    accentGreenLight: "#A4B38C",
                    accentPink: "#AA7C6A",
                    backgroundPrimary: "#090806",
                    backgroundSecondary: "#12110D",
                    backgroundTertiary: "#1A1712",
                    textPrimary: "#F1E8D8",
                    textSecondary: "#C9B79E",
                    textTertiary: "#927D64",
                    taskRegular: "#8BB07A",
                    taskRegularBg: "#182119",
                    taskDDL: "#E29A68",
                    taskDDLBg: "#2C1D15",
                    taskLeisure: "#B29BD9",
                    taskLeisureBg: "#221E31"
                )
            )
        }
    }
}

private enum WeekThemeRuntime {
    private static var cachedThemeRaw = ""
    private static var cachedPalettePair = WeekThemePalettePair.forTheme(.amber)

    private static func resolvedTheme() -> WeekTheme {
        let defaults = WeekyiiWidgetBridge.sharedDefaults()
        let raw = defaults.string(forKey: WeekyiiWidgetBridge.selectedThemeKey) ?? WeekTheme.amber.rawValue
        let premiumThemeUnlocked = defaults.bool(forKey: WeekyiiWidgetBridge.premiumThemeUnlockedKey)
        let theme = WeekTheme.resolvedTheme(rawValue: raw, premiumThemeUnlocked: premiumThemeUnlocked)
        if theme.rawValue != cachedThemeRaw {
            cachedThemeRaw = theme.rawValue
            cachedPalettePair = WeekThemePalettePair.forTheme(theme)
        }
        return theme
    }

    private static var appearanceMode: AppearanceMode {
        let raw = WeekyiiWidgetBridge.sharedDefaults().string(forKey: WeekyiiWidgetBridge.appearanceModeKey) ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }

    private static var palettePair: WeekThemePalettePair {
        _ = resolvedTheme()
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
