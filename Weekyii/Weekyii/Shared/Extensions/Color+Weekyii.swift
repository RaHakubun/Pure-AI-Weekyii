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
    // Personalised themes: these ship with their own visual language, not just a palette.
    case brutal
    case neon
    case paper
    case terminal

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
        case .brutal: return String(localized: "theme.brutal.name", defaultValue: "粗野")
        case .neon: return String(localized: "theme.neon.name", defaultValue: "霓虹")
        case .paper: return String(localized: "theme.paper.name", defaultValue: "纸感")
        case .terminal: return String(localized: "theme.terminal.name", defaultValue: "终端")
        }
    }

    var isPremiumTheme: Bool {
        self == .lotr
    }

    /// Visual form (not colour): corner radius, borders, shadows and icon style.
    /// The ten original themes keep `.classic` so their appearance never changes;
    /// personalised themes override it to ship a different visual language.
    var visualStyle: ThemeVisualStyle {
        switch self {
        case .brutal:
            return .brutalist
        case .neon:
            return .neon
        case .paper:
            return .paper
        case .terminal:
            return .terminal
        case .amber, .ocean, .forest, .rose, .lavender, .graphite, .sunset, .mint, .midnight, .lotr:
            return .classic
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

    func liveActivityThemeSnapshot(appearanceMode: AppearanceMode) -> LiveActivityThemeSnapshot {
        LiveActivityThemeSnapshot(
            islandTextPrimaryHex: palettePair.dark.textPrimary,
            islandTextSecondaryHex: palettePair.dark.textSecondary,
            islandAccentHex: palettePair.dark.primary,
            islandWarningHex: palettePair.dark.taskDDL,
            islandSuccessHex: palettePair.dark.taskRegular,
            islandChipPrimaryHex: palettePair.dark.primary,
            islandChipSecondaryHex: palettePair.dark.accentOrange,
            islandKeylineHex: palettePair.dark.primaryLight,
            lockBackgroundHex: palettePair.light.backgroundSecondary,
            lockSurfaceHex: palettePair.light.backgroundTertiary,
            lockTextPrimaryHex: palettePair.light.textPrimary,
            lockTextSecondaryHex: palettePair.light.textSecondary,
            lockAccentHex: palettePair.light.primary,
            lockProgressTrackHex: palettePair.light.primaryLight,
            darkLockBackgroundHex: palettePair.dark.backgroundSecondary,
            darkLockSurfaceHex: palettePair.dark.backgroundTertiary,
            darkLockTextPrimaryHex: palettePair.dark.textPrimary,
            darkLockTextSecondaryHex: palettePair.dark.textSecondary,
            darkLockAccentHex: palettePair.dark.primary,
            darkLockProgressTrackHex: palettePair.dark.primaryLight,
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

// MARK: - Theme visual language (form, not colour)

/// How a theme renders frames, bars and icons. Deliberately separated from
/// `WeekThemePalette` so a theme can change its *shape* without touching its colours.
struct ThemeVisualStyle: Equatable {
    /// Corner radius for cards and frames.
    var cornerRadius: CGFloat
    /// Border width; `0` renders no stroke.
    var borderWidth: CGFloat
    /// Border colour in light mode. `nil` falls back to `backgroundTertiary`.
    var borderColorHexLight: String?
    /// Border colour in dark mode. Kept separate because an ink border vanishes on a dark surface.
    var borderColorHexDark: String?
    /// `nil` renders no shadow.
    var shadow: ThemeShadowStyle?
    /// SF Symbol variant applied app-wide through `.symbolVariant(_:)`.
    var symbolVariant: ThemeSymbolVariant
    /// Multiplier applied to the thickness a caller asked for on rings/bars.
    /// `1.0` keeps the original Weekyii weight, which is why this is a scale
    /// rather than an absolute width: call sites pass 4, 8, 12 … and every one
    /// of them has to stay pixel-identical under `.classic`.
    var barScale: CGFloat
    /// Bar corner radius in points. `nil` keeps the pill shape (half the height).
    var barCornerRadius: CGFloat?

    /// The original Weekyii look: soft radius, hairline border, diffuse shadow, outline icons.
    static let classic = ThemeVisualStyle(
        cornerRadius: 12,
        borderWidth: 1,
        borderColorHexLight: nil,
        borderColorHexDark: nil,
        shadow: ThemeShadowStyle(colorHex: "#3A2A22", opacity: 0.08, radius: 10, x: 0, y: 3),
        symbolVariant: .none,
        barScale: 1.0,
        barCornerRadius: nil
    )

    /// Neo-brutalism: near-square corners, heavy ink border, hard offset shadow, filled icons.
    static let brutalist = ThemeVisualStyle(
        cornerRadius: 4,
        borderWidth: 2.5,
        borderColorHexLight: "#111111",
        borderColorHexDark: "#F2F2F2",
        shadow: ThemeShadowStyle(colorHex: "#000000", opacity: 1.0, radius: 0, x: 4, y: 4),
        symbolVariant: .fill,
        barScale: 1.5,
        barCornerRadius: 0
    )

    /// Cyberpunk neon: medium radius, glowing accent border, neon bloom, filled icons.
    static let neon = ThemeVisualStyle(
        cornerRadius: 14,
        borderWidth: 1.5,
        borderColorHexLight: "#0091A8",
        borderColorHexDark: "#00F0FF",
        shadow: ThemeShadowStyle(colorHex: "#00F0FF", opacity: 0.35, radius: 16, x: 0, y: 0),
        symbolVariant: .fill,
        barScale: 1.25,
        barCornerRadius: nil
    )

    /// Printed page: near-square cards, hairline rules, no elevation, thin square bars.
    static let paper = ThemeVisualStyle(
        cornerRadius: 2,
        borderWidth: 0.75,
        borderColorHexLight: "#D6C9B4",
        borderColorHexDark: "#4A453D",
        shadow: .flat,
        symbolVariant: .none,
        barScale: 0.6,
        barCornerRadius: 0.5
    )

    /// Phosphor terminal: absolute right angles, 1pt phosphor rule, filled glyphs.
    static let terminal = ThemeVisualStyle(
        cornerRadius: 0,
        borderWidth: 1,
        borderColorHexLight: "#2F7A3F",
        borderColorHexDark: "#33FF66",
        shadow: .flat,
        symbolVariant: .fill,
        barScale: 0.8,
        barCornerRadius: 0
    )

    func borderColor(isDark: Bool) -> Color? {
        let hex = isDark ? borderColorHexDark : borderColorHexLight
        return hex.map { Color(hex: $0) }
    }
}

struct ThemeShadowStyle: Equatable {
    var colorHex: String
    var opacity: Double
    /// `0` produces a hard, unblurred offset shadow (the brutalist signature).
    var radius: CGFloat
    var x: CGFloat
    var y: CGFloat

    var color: Color {
        Color(hex: colorHex).opacity(opacity)
    }

    /// The original diffuse Weekyii shadow, used whenever a theme does not define one.
    static let classic = ThemeShadowStyle(colorHex: "#3A2A22", opacity: 0.08, radius: 10, x: 0, y: 3)

    /// No elevation. Expressed as a zeroed style rather than `nil`, because a
    /// `nil` shadow falls back to `.classic` and would silently re-add one.
    static let flat = ThemeShadowStyle(colorHex: "#000000", opacity: 0, radius: 0, x: 0, y: 0)
}

extension ThemeVisualStyle {
    /// Shadow to render, falling back to the classic diffuse shadow.
    var resolvedShadow: ThemeShadowStyle {
        shadow ?? .classic
    }

    /// Thickness for a ring/bar that the call site sized at `base`.
    /// Scaling (rather than an absolute width) is what keeps `.classic` unchanged
    /// across every call site, which pass 4, 8 and 12 points.
    func barThickness(_ base: CGFloat) -> CGFloat {
        base * barScale
    }

    /// Corner radius for a bar: `nil` means the pill shape the original used.
    func barCornerRadius(for thickness: CGFloat) -> CGFloat {
        barCornerRadius ?? thickness / 2
    }

    // MARK: - Settings picker swatch

    /// The 30pt theme swatch in 设置 is derived from the card form, so the picker
    /// previews the shape language too. Both factors are chosen so `.classic`
    /// reproduces the 7pt radius / 0.5pt rule the swatch has always had.
    var swatchRadius: CGFloat { cornerRadius * (7.0 / 12.0) }
    var swatchBorderWidth: CGFloat { borderWidth * 0.5 }

    /// Border colour that adapts to light/dark, falling back to `backgroundTertiary`.
    var resolvedBorderColor: Color {
        if let light = borderColorHexLight, let dark = borderColorHexDark {
            return Color.dynamic(lightHex: light, darkHex: dark)
        }
        return Color.backgroundTertiary
    }
}

enum ThemeSymbolVariant: Equatable {
    case none
    case fill
    case circle
    case square

    var symbolVariants: SymbolVariants {
        switch self {
        case .none: return .none
        case .fill: return .fill
        case .circle: return .circle
        case .square: return .square
        }
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
                    primary: "#C74D3E",
                    primaryLight: "#E57D5E",
                    primaryDark: "#8F2F25",
                    accentOrange: "#E18A4D",
                    accentOrangeLight: "#F0B98A",
                    accentGreen: "#4B8D78",
                    accentGreenLight: "#7CBBA5",
                    accentPink: "#CF6A74",
                    backgroundPrimary: "#FFF0E8",
                    backgroundSecondary: "#FFF9F5",
                    backgroundTertiary: "#F5E1D7",
                    textPrimary: "#351D19",
                    textSecondary: "#755149",
                    textTertiary: "#A27D72",
                    taskRegular: "#356F86",
                    taskRegularBg: "#D9EAF2",
                    taskDDL: "#CB5843",
                    taskDDLBg: "#F7E1DA",
                    taskLeisure: "#8C67C8",
                    taskLeisureBg: "#EFE8FA"
                ),
                dark: WeekThemePalette(
                    primary: "#DE7658",
                    primaryLight: "#EDA688",
                    primaryDark: "#8F2F25",
                    accentOrange: "#EEB37F",
                    accentOrangeLight: "#F4C79F",
                    accentGreen: "#74BA9F",
                    accentGreenLight: "#94D0B6",
                    accentPink: "#E09AA4",
                    backgroundPrimary: "#18110F",
                    backgroundSecondary: "#211714",
                    backgroundTertiary: "#2E1F1B",
                    textPrimary: "#F8E8E2",
                    textSecondary: "#D5B8AD",
                    textTertiary: "#AA8A80",
                    taskRegular: "#78C2D3",
                    taskRegularBg: "#1A333F",
                    taskDDL: "#ED8A73",
                    taskDDLBg: "#37231F",
                    taskLeisure: "#B39AEB",
                    taskLeisureBg: "#2D2644"
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
                    primary: "#7F683C",
                    primaryLight: "#B79863",
                    primaryDark: "#4E3E24",
                    accentOrange: "#A76635",
                    accentOrangeLight: "#C69060",
                    accentGreen: "#6A7382",
                    accentGreenLight: "#9EA7B6",
                    accentPink: "#8F7160",
                    backgroundPrimary: "#ECE8DE",
                    backgroundSecondary: "#F5F2EB",
                    backgroundTertiary: "#DDD8CD",
                    textPrimary: "#211D18",
                    textSecondary: "#4E4439",
                    textTertiary: "#7C7063",
                    taskRegular: "#5F6B7C",
                    taskRegularBg: "#DCE2EA",
                    taskDDL: "#9F5930",
                    taskDDLBg: "#ECD8CB",
                    taskLeisure: "#6D5A8A",
                    taskLeisureBg: "#E4DEEF"
                ),
                dark: WeekThemePalette(
                    primary: "#AF9160",
                    primaryLight: "#C6AA79",
                    primaryDark: "#5C4829",
                    accentOrange: "#BE8354",
                    accentOrangeLight: "#D6A678",
                    accentGreen: "#7A8597",
                    accentGreenLight: "#99A5B8",
                    accentPink: "#987669",
                    backgroundPrimary: "#080A08",
                    backgroundSecondary: "#101411",
                    backgroundTertiary: "#171C18",
                    textPrimary: "#E6DECf",
                    textSecondary: "#B8AB94",
                    textTertiary: "#837662",
                    taskRegular: "#8392AA",
                    taskRegularBg: "#18202C",
                    taskDDL: "#D28F62",
                    taskDDLBg: "#291C15",
                    taskLeisure: "#A48FC8",
                    taskLeisureBg: "#211D2E"
                )
            )
        case .brutal:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#2B50FF",
                    primaryLight: "#5C7BFF",
                    primaryDark: "#1A34CC",
                    accentOrange: "#FF5C39",
                    accentOrangeLight: "#FF8A70",
                    accentGreen: "#00A86B",
                    accentGreenLight: "#3FC98D",
                    accentPink: "#FF3D7F",
                    backgroundPrimary: "#FFFDF5",
                    backgroundSecondary: "#FFFFFF",
                    backgroundTertiary: "#EFEBE0",
                    textPrimary: "#111111",
                    textSecondary: "#4A4A4A",
                    textTertiary: "#8A8A8A",
                    taskRegular: "#2B50FF",
                    taskRegularBg: "#DCE3FF",
                    taskDDL: "#E23E1D",
                    taskDDLBg: "#FFE0D9",
                    taskLeisure: "#7B4DCC",
                    taskLeisureBg: "#EDE4FA"
                ),
                dark: WeekThemePalette(
                    primary: "#7B96FF",
                    primaryLight: "#A3B5FF",
                    primaryDark: "#2B50FF",
                    accentOrange: "#FF7A5C",
                    accentOrangeLight: "#FF9E88",
                    accentGreen: "#3FC98D",
                    accentGreenLight: "#6FDCA8",
                    accentPink: "#FF6B9D",
                    backgroundPrimary: "#111111",
                    backgroundSecondary: "#1C1C1C",
                    backgroundTertiary: "#2A2A2A",
                    textPrimary: "#FFFDF5",
                    textSecondary: "#C4C4C4",
                    textTertiary: "#8A8A8A",
                    taskRegular: "#7B96FF",
                    taskRegularBg: "#1E2A5C",
                    taskDDL: "#FF7A5C",
                    taskDDLBg: "#4A2018",
                    taskLeisure: "#C9A6FF",
                    taskLeisureBg: "#2E2440"
                )
            )
        case .neon:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#0091A8",
                    primaryLight: "#00B8D4",
                    primaryDark: "#00697A",
                    accentOrange: "#E5007D",
                    accentOrangeLight: "#FF3DA0",
                    accentGreen: "#00B87A",
                    accentGreenLight: "#38D9A0",
                    accentPink: "#E5007D",
                    backgroundPrimary: "#F0F8FA",
                    backgroundSecondary: "#FFFFFF",
                    backgroundTertiary: "#DDEEF2",
                    textPrimary: "#0A1A20",
                    textSecondary: "#3E5A63",
                    textTertiary: "#6E8C95",
                    taskRegular: "#0091A8",
                    taskRegularBg: "#D6F2F7",
                    taskDDL: "#C5006B",
                    taskDDLBg: "#FFDCEF",
                    taskLeisure: "#6B3FD4",
                    taskLeisureBg: "#E9E0FA"
                ),
                dark: WeekThemePalette(
                    primary: "#00F0FF",
                    primaryLight: "#7DF5FF",
                    primaryDark: "#00A8B8",
                    accentOrange: "#FF4DA6",
                    accentOrangeLight: "#FF85C2",
                    accentGreen: "#00E5A0",
                    accentGreenLight: "#5CFFCB",
                    accentPink: "#FF4DA6",
                    backgroundPrimary: "#0A0E1A",
                    backgroundSecondary: "#121826",
                    backgroundTertiary: "#1C2436",
                    textPrimary: "#E8FDFF",
                    textSecondary: "#A8C4CC",
                    textTertiary: "#6E8A94",
                    taskRegular: "#00F0FF",
                    taskRegularBg: "#0E2A33",
                    taskDDL: "#FF4DA6",
                    taskDDLBg: "#33102A",
                    taskLeisure: "#B08CFF",
                    taskLeisureBg: "#221A3D"
                )
            )
        case .paper:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#B23A2E",
                    primaryLight: "#D2695A",
                    primaryDark: "#8A2A20",
                    accentOrange: "#C08A3E",
                    accentOrangeLight: "#D9AE72",
                    accentGreen: "#4A6C58",
                    accentGreenLight: "#7A9A85",
                    accentPink: "#B4576B",
                    backgroundPrimary: "#FBF6EC",
                    backgroundSecondary: "#FFFDF8",
                    backgroundTertiary: "#F1E9DA",
                    textPrimary: "#2C2A26",
                    textSecondary: "#5F594F",
                    textTertiary: "#8C8377",
                    taskRegular: "#3F6B62",
                    taskRegularBg: "#E2EDE7",
                    taskDDL: "#B23A2E",
                    taskDDLBg: "#F7E2DE",
                    taskLeisure: "#7A5FA8",
                    taskLeisureBg: "#EAE3F2"
                ),
                dark: WeekThemePalette(
                    primary: "#E0705F",
                    primaryLight: "#F0A091",
                    primaryDark: "#B23A2E",
                    accentOrange: "#D9AE72",
                    accentOrangeLight: "#E8C79B",
                    accentGreen: "#8FBF9F",
                    accentGreenLight: "#B5D8BF",
                    accentPink: "#DE8D9C",
                    backgroundPrimary: "#1B1917",
                    backgroundSecondary: "#232019",
                    backgroundTertiary: "#2E2A22",
                    textPrimary: "#F0EADF",
                    textSecondary: "#B8AFA1",
                    textTertiary: "#8A8175",
                    taskRegular: "#8FBF9F",
                    taskRegularBg: "#223029",
                    taskDDL: "#E0705F",
                    taskDDLBg: "#3A221E",
                    taskLeisure: "#B79AE0",
                    taskLeisureBg: "#2C2438"
                )
            )
        case .terminal:
            return WeekThemePalettePair(
                light: WeekThemePalette(
                    primary: "#1B7F3B",
                    primaryLight: "#3FA35C",
                    primaryDark: "#0F5A28",
                    accentOrange: "#B26A00",
                    accentOrangeLight: "#D18F2E",
                    accentGreen: "#1B7F3B",
                    accentGreenLight: "#3FA35C",
                    accentPink: "#A31F5B",
                    backgroundPrimary: "#F2F5F2",
                    backgroundSecondary: "#FBFDFB",
                    backgroundTertiary: "#E2E9E2",
                    textPrimary: "#0F1A12",
                    textSecondary: "#3E4F42",
                    textTertiary: "#6E7F72",
                    taskRegular: "#1B7F3B",
                    taskRegularBg: "#DCEDE1",
                    taskDDL: "#A32B1B",
                    taskDDLBg: "#F5DFDB",
                    taskLeisure: "#5A4FA8",
                    taskLeisureBg: "#E4E2F5"
                ),
                dark: WeekThemePalette(
                    primary: "#33FF66",
                    primaryLight: "#8CFFA8",
                    primaryDark: "#1FA84A",
                    accentOrange: "#FFB000",
                    accentOrangeLight: "#FFC94D",
                    accentGreen: "#33FF66",
                    accentGreenLight: "#8CFFA8",
                    accentPink: "#FF4D9E",
                    backgroundPrimary: "#05100A",
                    backgroundSecondary: "#0A1A10",
                    backgroundTertiary: "#12291A",
                    textPrimary: "#D6FFE1",
                    textSecondary: "#7FB892",
                    textTertiary: "#4E7A5C",
                    taskRegular: "#33FF66",
                    taskRegularBg: "#0C2415",
                    taskDDL: "#FF5A5A",
                    taskDDLBg: "#2A0F0F",
                    taskLeisure: "#9D8CFF",
                    taskLeisureBg: "#171334"
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
