package com.weekyii.android.ui.theme

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

class WeekyiiThemeTokensTest {
    @Test
    fun amberLightPaletteMatchesIosSemanticColors() {
        val palette = WeekyiiPalettes.forTheme("amber", darkTheme = false)

        assertEquals(Color(0xFFFFF7EE), palette.backgroundPrimary)
        assertEquals(Color(0xFFFFFDF9), palette.backgroundSecondary)
        assertEquals(Color(0xFFF6EDE3), palette.backgroundTertiary)
        assertEquals(Color(0xFFC46A1A), palette.primary)
        assertEquals(Color(0xFF2A1D16), palette.textPrimary)
        assertEquals(Color(0xFF6B5A4F), palette.textSecondary)
    }

    @Test
    fun amberDarkPaletteMatchesIosSemanticColors() {
        val palette = WeekyiiPalettes.forTheme("amber", darkTheme = true)

        assertEquals(Color(0xFF18120E), palette.backgroundPrimary)
        assertEquals(Color(0xFF221A14), palette.backgroundSecondary)
        assertEquals(Color(0xFFE0A35B), palette.primary)
        assertEquals(Color(0xFFF7EBDD), palette.textPrimary)
    }

    @Test
    fun unknownThemeFallsBackToAmber() {
        assertEquals(
            WeekyiiPalettes.forTheme("amber", darkTheme = false),
            WeekyiiPalettes.forTheme("not-a-theme", darkTheme = false)
        )
    }

    @Test
    fun oceanAndLotrPalettesMatchIosSemanticColors() {
        val ocean = WeekyiiPalettes.forTheme("ocean", darkTheme = false)
        val lotrDark = WeekyiiPalettes.forTheme("lotr", darkTheme = true)

        assertEquals(Color(0xFF2A6FA1), ocean.primary)
        assertEquals(Color(0xFFF2F8FD), ocean.backgroundPrimary)
        assertEquals(Color(0xFFAF9160), lotrDark.primary)
        assertEquals(Color(0xFF080A08), lotrDark.backgroundPrimary)
    }

    @Test
    fun everyIosThemeHasItsOwnPalette() {
        val themeIds = listOf("amber", "ocean", "forest", "rose", "lavender", "graphite", "sunset", "mint", "midnight", "lotr")
        val primaryColors = themeIds.map { WeekyiiPalettes.forTheme(it, darkTheme = false).primary }

        assertEquals(themeIds.size, primaryColors.distinct().size)
    }

    @Test
    fun spacingAndRadiusTokensMatchIosDesignSystem() {
        assertEquals(8f, WeekyiiDimensions.spacingSmall.value)
        assertEquals(12f, WeekyiiDimensions.spacingMedium.value)
        assertEquals(16f, WeekyiiDimensions.spacingBase.value)
        assertEquals(20f, WeekyiiDimensions.spacingLarge.value)
        assertEquals(24f, WeekyiiDimensions.spacingExtraLarge.value)
        assertEquals(16f, WeekyiiDimensions.radiusLarge.value)
        assertEquals(24f, WeekyiiDimensions.radiusExtraLarge.value)
    }
}
