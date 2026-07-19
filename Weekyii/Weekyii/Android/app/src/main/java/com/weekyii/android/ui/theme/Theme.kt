package com.weekyii.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

val LocalWeekyiiThemeId = staticCompositionLocalOf { "amber" }
val LocalWeekyiiPalette = staticCompositionLocalOf { WeekyiiPalettes.forTheme("amber", false) }

@Composable
fun WeekyiiTheme(themeId: String = "amber", darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val palette = WeekyiiPalettes.forTheme(themeId, darkTheme)
    val colors = (if (darkTheme) {
        darkColorScheme(
            primary = palette.primary,
            onPrimary = palette.backgroundPrimary,
            primaryContainer = palette.primaryDark,
            onPrimaryContainer = palette.textPrimary,
            secondary = palette.accentGreen,
            onSecondary = palette.backgroundPrimary,
            secondaryContainer = palette.accentGreen.copy(alpha = 0.30f),
            onSecondaryContainer = palette.textPrimary,
            tertiary = palette.accentOrange,
            onTertiary = palette.backgroundPrimary,
            background = palette.backgroundPrimary,
            onBackground = palette.textPrimary,
            surface = palette.backgroundSecondary,
            onSurface = palette.textPrimary,
            surfaceVariant = palette.backgroundTertiary,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.textTertiary,
            error = palette.taskDDL,
            onError = palette.backgroundSecondary,
            errorContainer = palette.taskDDLBg,
            onErrorContainer = palette.textPrimary,
            inverseSurface = palette.textPrimary,
            inverseOnSurface = palette.backgroundSecondary,
            inversePrimary = palette.primaryLight,
            scrim = Color.Black.copy(alpha = 0.32f)
        )
    } else {
        lightColorScheme(
            primary = palette.primary,
            onPrimary = palette.backgroundSecondary,
            primaryContainer = palette.primaryLight.copy(alpha = 0.45f),
            onPrimaryContainer = palette.textPrimary,
            secondary = palette.accentGreen,
            onSecondary = palette.backgroundSecondary,
            secondaryContainer = palette.accentGreenLight.copy(alpha = 0.45f),
            onSecondaryContainer = palette.textPrimary,
            tertiary = palette.accentOrange,
            onTertiary = palette.backgroundSecondary,
            background = palette.backgroundPrimary,
            onBackground = palette.textPrimary,
            surface = palette.backgroundSecondary,
            onSurface = palette.textPrimary,
            surfaceVariant = palette.backgroundTertiary,
            onSurfaceVariant = palette.textSecondary,
            outline = palette.textTertiary,
            error = palette.taskDDL,
            onError = palette.backgroundSecondary,
            errorContainer = palette.taskDDLBg,
            onErrorContainer = palette.textPrimary,
            inverseSurface = palette.textPrimary,
            inverseOnSurface = palette.backgroundSecondary,
            inversePrimary = palette.primaryLight,
            scrim = Color.Black.copy(alpha = 0.32f)
        )
    })

    val shapes = Shapes(
        extraSmall = RoundedCornerShape(WeekyiiDimensions.radiusSmall),
        small = RoundedCornerShape(WeekyiiDimensions.radiusMedium),
        medium = RoundedCornerShape(WeekyiiDimensions.radiusLarge),
        large = RoundedCornerShape(WeekyiiDimensions.radiusExtraLarge),
        extraLarge = RoundedCornerShape(WeekyiiDimensions.radiusExtraLarge)
    )

    CompositionLocalProvider(
        LocalWeekyiiThemeId provides themeId,
        LocalWeekyiiPalette provides palette
    ) {
        MaterialTheme(
            colorScheme = colors,
            typography = WeekyiiTypography,
            shapes = shapes,
            content = content
        )
    }
}
