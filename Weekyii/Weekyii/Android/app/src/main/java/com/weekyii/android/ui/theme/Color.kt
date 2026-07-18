package com.weekyii.android.ui.theme

import androidx.compose.ui.graphics.Color

/** Semantic palette mirrored from the iOS WeekThemePalette. */
data class WeekyiiPalette(
    val primary: Color,
    val primaryLight: Color,
    val primaryDark: Color,
    val accentOrange: Color,
    val accentOrangeLight: Color,
    val accentGreen: Color,
    val accentGreenLight: Color,
    val accentPink: Color,
    val backgroundPrimary: Color,
    val backgroundSecondary: Color,
    val backgroundTertiary: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val taskRegular: Color,
    val taskRegularBg: Color,
    val taskDDL: Color,
    val taskDDLBg: Color,
    val taskLeisure: Color,
    val taskLeisureBg: Color
)

object WeekyiiPalettes {
    private fun color(hex: String): Color = Color(hex.removePrefix("#").toLong(16) or 0xFF000000L)

    private fun palette(values: List<String>): WeekyiiPalette {
        require(values.size == 20)
        val colors = values.map(::color)
        return WeekyiiPalette(
            primary = colors[0], primaryLight = colors[1], primaryDark = colors[2],
            accentOrange = colors[3], accentOrangeLight = colors[4], accentGreen = colors[5],
            accentGreenLight = colors[6], accentPink = colors[7], backgroundPrimary = colors[8],
            backgroundSecondary = colors[9], backgroundTertiary = colors[10], textPrimary = colors[11],
            textSecondary = colors[12], textTertiary = colors[13], taskRegular = colors[14],
            taskRegularBg = colors[15], taskDDL = colors[16], taskDDLBg = colors[17],
            taskLeisure = colors[18], taskLeisureBg = colors[19]
        )
    }

    private fun pair(light: String, dark: String): Pair<WeekyiiPalette, WeekyiiPalette> =
        palette(light.split(" ")) to palette(dark.split(" "))

    private val palettes = mapOf(
        "amber" to pair(
            "C46A1A E0A35B 8A4A13 F08A3C F4AE77 3FA67A 6DC7A3 D97A6C FFF7EE FFFDF9 F6EDE3 2A1D16 6B5A4F 9B887C 2F7E79 D9F0EC D05C3E F8E1DB 8C6AD9 EFE8FB",
            "E0A35B F2C284 8A4A13 F4AE77 F7C9A5 62C9A0 8FDCBC E39B8E 18120E 221A14 2E241D F7EBDD D2BDA9 A98F79 6ECBC3 1E3C3A F18B70 3D241F B99AF0 2F2644"
        ),
        "ocean" to pair(
            "2A6FA1 5AA3D1 1D4F73 F28D49 F7B787 2E9B8C 66C3B7 D86F8B F2F8FD FCFEFF E7F0F7 172A3A 4B667A 7D93A2 2A7A91 D8EDF4 D36345 F9E3DC 6E78D8 E8EBFB",
            "5AA3D1 8EC5E6 1D4F73 F7B787 F9CCAB 5BC4B2 85D8CB E59BB0 0F1A24 15222F 1E2F40 EAF4FC BED3E3 8BA4B8 73C8DE 183543 F19174 3A2520 98A0EE 252B45"
        ),
        "forest" to pair(
            "2E7D4E 5BA879 205737 D9903D E8B37A 2F9B6A 66C394 C97563 F4FAF6 FEFFFE E8F1EA 1E2C22 4F6657 7A8F80 2E8071 D7EFE9 C95D3E F5E2DB 7B70CC EAE7F7",
            "5BA879 83C59A 205737 E8B37A EEC79D 63C995 8BDCB3 DFA090 111B15 18251D 223328 E8F5EC B6CFBC 869E8B 74CEBE 173833 E98669 3A2520 A39AE8 272544"
        ),
        "rose" to pair(
            "B85C7A D98EA8 7E3F54 E18A4E F0B88D 3A9A7B 70C2A6 D86B87 FFF5F8 FFFDFE F6EAF0 321D27 6E4D5B 9B7C89 337E83 DDF0F1 D16449 F9E5DF 8A69CB EFE8FA",
            "D98EA8 EAB4C6 7E3F54 F0B88D F4CCAD 67C3A2 90D8BE EB9EB5 1C1217 261920 33222B F9EAF0 D8B8C6 AA8796 73C1C7 1B363B EE8F73 3C2521 B49CE8 2C2842"
        ),
        "lavender" to pair(
            "7C5295 9E7BB5 5A3870 E68C55 F2B99C 4B9A84 7DC4B1 CF729C F8F5FA FEFDFE EFEAF4 291F2F 605068 8C7B94 4B7C95 E0EFF5 C36154 F8E6E3 9162CC F2EBFC",
            "9E7BB5 B89BCC 5A3870 F2B99C F5CDB7 77C8AF 9ADDC8 E09EBE 16131B 201A28 2B2336 EFE8F6 C9BCD8 9888AA 8CBEDC 1D3340 E58679 392523 B79AEF 2E2745"
        ),
        "graphite" to pair(
            "444A52 6B727A 2B3036 D48B4C E8B78C 449277 77BB9F C56877 F5F6F8 FFFFFF EBECEF 1C1F22 565D65 828991 4A7885 E2F0F4 C55B51 F7E6E5 7A6CB8 EDEAF6",
            "8D96A1 B0B7C0 2B3036 E8B78C F1CFB0 74C7A7 9ADABD DA9DA8 111214 181A1E 24272D E7EAF0 BDC4CF 8E97A5 84B8C8 1C3139 E6847A 372423 A99EE0 2B2840"
        ),
        "sunset" to pair(
            "C74D3E E57D5E 8F2F25 E18A4D F0B98A 4B8D78 7CBBA5 CF6A74 FFF0E8 FFF9F5 F5E1D7 351D19 755149 A27D72 356F86 D9EAF2 CB5843 F7E1DA 8C67C8 EFE8FA",
            "DE7658 EDA688 8F2F25 EEB37F F4C79F 74BA9F 94D0B6 E09AA4 18110F 211714 2E1F1B F8E8E2 D5B8AD AA8A80 78C2D3 1A333F ED8A73 37231F B39AEB 2D2644"
        ),
        "mint" to pair(
            "2E8F84 61B6A8 1F5F58 DF8D48 EDB987 349F79 6FCAA5 CC718A F2FBF8 FCFFFE E5F3EF 1B2D2A 4A6A64 79968F 2E7E93 D8EEF4 C9644B F8E4DE 7A6ED0 ECE9FB",
            "61B6A8 8BD0C4 1F5F58 EDB987 F2CAA6 65CEAB 8FE0C1 E2A6B8 0F1917 162421 20332E E8F6F2 BCD9D1 8EA9A2 7CCBE0 183542 EA8D78 392522 AA9CEE 282643"
        ),
        "midnight" to pair(
            "33558C 678BC6 223A60 D98A49 EAB88D 3F8F79 73BDA4 B76C8D F2F5FB FCFDFF E6EBF5 1A2334 4B5D79 7688A4 3B7894 DCECF4 C45D4C F8E5E1 7668C7 EBE8FA",
            "7DA2DF A2BDEB 223A60 EAB88D F0CAAA 73C2A8 98D7BF DAA1B8 070C14 0E1521 172235 E8F0FF BDCCE6 8999B5 7FBFDC 173243 E38E7E 372422 A99BE9 272543"
        ),
        "lotr" to pair(
            "7F683C B79863 4E3E24 A76635 C69060 6A7382 9EA7B6 8F7160 ECE8DE F5F2EB DDD8CD 211D18 4E4439 7C7063 5F6B7C DCE2EA 9F5930 ECD8CB 6D5A8A E4DEEF",
            "AF9160 C6AA79 5C4829 BE8354 D6A678 7A8597 99A5B8 987669 080A08 101411 171C18 E6DECF B8AB94 837662 8392AA 18202C D28F62 291C15 A48FC8 211D2E"
        )
    )

    fun forTheme(themeId: String, darkTheme: Boolean): WeekyiiPalette {
        val (light, dark) = palettes[themeId] ?: palettes.getValue("amber")
        return if (darkTheme) dark else light
    }
}

// Compatibility aliases for existing screens while they migrate to semantic tokens.
val WeekyiiPrimary get() = WeekyiiPalettes.forTheme("amber", false).primary
val WeekyiiPrimaryLight get() = WeekyiiPalettes.forTheme("amber", false).primaryLight
val WeekyiiPrimaryDark get() = WeekyiiPalettes.forTheme("amber", false).primaryDark
val AccentOrange get() = WeekyiiPalettes.forTheme("amber", false).accentOrange
val AccentOrangeLight get() = WeekyiiPalettes.forTheme("amber", false).accentOrangeLight
val AccentGreen get() = WeekyiiPalettes.forTheme("amber", false).accentGreen
val AccentGreenLight get() = WeekyiiPalettes.forTheme("amber", false).accentGreenLight
val AccentPink get() = WeekyiiPalettes.forTheme("amber", false).accentPink
val BackgroundPrimary get() = WeekyiiPalettes.forTheme("amber", false).backgroundPrimary
val BackgroundSecondary get() = WeekyiiPalettes.forTheme("amber", false).backgroundSecondary
val BackgroundTertiary get() = WeekyiiPalettes.forTheme("amber", false).backgroundTertiary
val TextPrimary get() = WeekyiiPalettes.forTheme("amber", false).textPrimary
val TextSecondary get() = WeekyiiPalettes.forTheme("amber", false).textSecondary
val TextTertiary get() = WeekyiiPalettes.forTheme("amber", false).textTertiary
val TaskRegular get() = WeekyiiPalettes.forTheme("amber", false).taskRegular
val TaskRegularBg get() = WeekyiiPalettes.forTheme("amber", false).taskRegularBg
val TaskDDL get() = WeekyiiPalettes.forTheme("amber", false).taskDDL
val TaskDDLBg get() = WeekyiiPalettes.forTheme("amber", false).taskDDLBg
val TaskLeisure get() = WeekyiiPalettes.forTheme("amber", false).taskLeisure
val TaskLeisureBg get() = WeekyiiPalettes.forTheme("amber", false).taskLeisureBg
