package com.weekyii.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.theme.WeekyiiDimensions
import com.weekyii.android.ui.theme.LocalWeekyiiPalette

@Composable
fun WeekyiiCard(
    modifier: Modifier = Modifier,
    accentColor: Color? = null,
    gradient: Boolean = false,
    fillWidth: Boolean = true,
    content: @Composable ColumnScope.() -> Unit
) {
    val palette = LocalWeekyiiPalette.current
    val shape = RoundedCornerShape(WeekyiiDimensions.radiusLarge)
    val borderColor = if (gradient) {
        palette.onGradient.copy(alpha = 0.22f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.82f)
    }
    val background = if (gradient) {
        Brush.linearGradient(
            listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary)
        )
    } else {
        Brush.linearGradient(
            listOf(MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.surface)
        )
    }

    Column(
        modifier = modifier
            .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
            .shadow(
                WeekyiiDimensions.cardElevation,
                shape,
                ambientColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                spotColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
            )
            .clip(shape)
            .background(background)
            .border(1.dp, borderColor, shape)
            .padding(WeekyiiDimensions.spacingLarge),
    ) {
        if (accentColor != null) {
            Spacer(
                modifier = Modifier
                    .width(WeekyiiDimensions.accentBarWidth)
                    .height(WeekyiiDimensions.accentBarHeight)
                    .background(accentColor, RoundedCornerShape(WeekyiiDimensions.radiusFull))
                    .align(androidx.compose.ui.Alignment.CenterHorizontally)
            )
            Spacer(Modifier.height(WeekyiiDimensions.spacingMedium))
        }
        content()
    }
}
