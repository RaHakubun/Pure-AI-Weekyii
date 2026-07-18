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
fun WeekyiiTheme(themeId: String = "amber", darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val base = if (darkTheme) DarkColors else LightColors
    val colors = base.copy(primary = when (themeId) {
        "ocean" -> androidx.compose.ui.graphics.Color(0xFF267A9A)
        "forest" -> androidx.compose.ui.graphics.Color(0xFF3F8054)
        "rose" -> androidx.compose.ui.graphics.Color(0xFFB65368)
        "lavender" -> androidx.compose.ui.graphics.Color(0xFF765BB2)
        "graphite" -> androidx.compose.ui.graphics.Color(0xFF59636B)
        "mint" -> androidx.compose.ui.graphics.Color(0xFF2D8A78)
        "midnight" -> androidx.compose.ui.graphics.Color(0xFF526EA8)
        else -> WeekyiiPrimary
    })

    MaterialTheme(
        colorScheme = colors,
        typography = WeekyiiTypography,
        content = content
    )
}
