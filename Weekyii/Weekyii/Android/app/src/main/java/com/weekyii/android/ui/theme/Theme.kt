package com.weekyii.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = WeekyiiPrimary,
    onPrimary = BackgroundSecondary,
    primaryContainer = WeekyiiPrimaryLight,
    onPrimaryContainer = TextPrimary,
    secondary = AccentGreen,
    onSecondary = BackgroundSecondary,
    secondaryContainer = AccentGreenLight,
    onSecondaryContainer = TextPrimary,
    tertiary = AccentOrange,
    onTertiary = BackgroundSecondary,
    background = BackgroundSecondary,
    onBackground = TextPrimary,
    surface = BackgroundPrimary,
    onSurface = TextPrimary,
    surfaceVariant = BackgroundTertiary,
    onSurfaceVariant = TextSecondary,
    outline = TextTertiary
)

private val DarkColors = darkColorScheme(
    primary = WeekyiiPrimaryLight,
    onPrimary = TextPrimary,
    primaryContainer = WeekyiiPrimaryDark,
    onPrimaryContainer = BackgroundSecondary,
    secondary = AccentGreenLight,
    onSecondary = TextPrimary,
    tertiary = AccentOrangeLight,
    onTertiary = TextPrimary,
    background = BackgroundPrimary,
    onBackground = TextPrimary,
    surface = BackgroundTertiary,
    onSurface = TextPrimary,
    surfaceVariant = BackgroundSecondary,
    onSurfaceVariant = TextSecondary,
    outline = TextTertiary
)

@Composable
fun WeekyiiTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (darkTheme) DarkColors else LightColors

    MaterialTheme(
        colorScheme = colors,
        typography = WeekyiiTypography,
        content = content
    )
}
