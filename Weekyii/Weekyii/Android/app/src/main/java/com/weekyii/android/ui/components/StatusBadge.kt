package com.weekyii.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.theme.LocalWeekyiiPalette
import com.weekyii.android.ui.theme.WeekyiiDimensions

@Composable
fun StatusBadge(
    text: String,
    color: Color,
    contentColor: Color? = null,
    contentPadding: PaddingValues = PaddingValues(horizontal = WeekyiiDimensions.badgeHorizontalPadding, vertical = WeekyiiDimensions.badgeVerticalPadding)
) {
    val resolvedContentColor = contentColor ?: LocalWeekyiiPalette.current.onGradient
    Text(
        text = text,
        color = resolvedContentColor,
        fontWeight = FontWeight.Medium,
        modifier = Modifier
            .background(color, RoundedCornerShape(WeekyiiDimensions.badgeRadius))
            .padding(contentPadding)
    )
}
