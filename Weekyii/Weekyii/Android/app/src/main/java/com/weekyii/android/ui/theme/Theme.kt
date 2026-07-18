package com.weekyii.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

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
            outline = palette.textTertiary
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
            outline = palette.textTertiary
        )
    })

    MaterialTheme(
        colorScheme = colors,
        typography = WeekyiiTypography,
        content = content
    )
}
