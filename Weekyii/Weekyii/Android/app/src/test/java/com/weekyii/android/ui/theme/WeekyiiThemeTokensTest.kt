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
        assertEquals(themeIds.toSet(), WeekyiiPalettes.supportedThemeIds)
    }

    @Test
    fun semanticRolesStayInsideTheSelectedPalette() {
        val light = WeekyiiPalettes.forTheme("amber", darkTheme = false)
        val dark = WeekyiiPalettes.forTheme("amber", darkTheme = true)

        assertEquals(light.backgroundSecondary, light.onGradient)
        assertEquals(dark.backgroundPrimary, dark.onGradient)
        assertEquals(light.accentGreen, light.success)
        assertEquals(light.taskDDL, light.warning)
        assertEquals(light.textPrimary, light.navigationIcon)
        assertEquals(dark.textPrimary, dark.navigationIcon)
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
        assertEquals(20f, WeekyiiDimensions.screenPadding.value)
        assertEquals(14f, WeekyiiDimensions.listGap.value)
        assertEquals(52f, WeekyiiDimensions.controlHeight.value)
        assertEquals(48f, WeekyiiDimensions.minimumTouchTarget.value)
        assertEquals(1f, WeekyiiDimensions.hairline.value)
    }

    @Test
    fun typographyDefinesEveryIosHierarchyRole() {
        assertEquals(46f, WeekyiiTypography.displayLarge.fontSize.value)
        assertEquals(32f, WeekyiiTypography.titleLarge.fontSize.value)
        assertEquals(22f, WeekyiiTypography.titleMedium.fontSize.value)
        assertEquals(18f, WeekyiiTypography.titleSmall.fontSize.value)
        assertEquals(17f, WeekyiiTypography.bodyLarge.fontSize.value)
        assertEquals(15f, WeekyiiTypography.bodyMedium.fontSize.value)
        assertEquals(13f, WeekyiiTypography.bodySmall.fontSize.value)
        assertEquals(11f, WeekyiiTypography.labelSmall.fontSize.value)
    }
}
