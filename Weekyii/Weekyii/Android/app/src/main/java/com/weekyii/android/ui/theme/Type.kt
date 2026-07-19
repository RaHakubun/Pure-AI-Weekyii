package com.weekyii.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val WeekyiiDisplay = TextStyle(
    fontFamily = FontFamily.Serif,
    fontWeight = FontWeight.Bold
)

private val WeekyiiTitle = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Bold
)

private val WeekyiiBody = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Normal
)

val WeekyiiTypography = Typography(
    displayLarge = WeekyiiDisplay.copy(fontSize = 46.sp),
    displayMedium = WeekyiiDisplay.copy(fontSize = 32.sp),
    displaySmall = WeekyiiDisplay.copy(fontSize = 28.sp),
    headlineLarge = WeekyiiTitle.copy(fontSize = 32.sp),
    headlineMedium = WeekyiiTitle.copy(fontSize = 24.sp),
    headlineSmall = WeekyiiTitle.copy(fontSize = 22.sp),
    titleLarge = WeekyiiTitle.copy(fontSize = 32.sp),
    titleMedium = WeekyiiTitle.copy(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = WeekyiiTitle.copy(fontSize = 18.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = WeekyiiBody.copy(fontSize = 17.sp),
    bodyMedium = WeekyiiBody.copy(fontSize = 15.sp),
    bodySmall = WeekyiiBody.copy(fontSize = 13.sp),
    labelLarge = WeekyiiBody.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    labelMedium = WeekyiiBody.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
    labelSmall = WeekyiiBody.copy(fontSize = 11.sp)
)
