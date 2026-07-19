package com.weekyii.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.weekyii.android.ui.theme.WeekyiiDimensions
import com.weekyii.android.ui.theme.LocalWeekyiiPalette

enum class WeekyiiButtonStyle { Primary, Secondary, Outline, OnGradient }

@Composable
fun WeekyiiButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    style: WeekyiiButtonStyle = WeekyiiButtonStyle.Primary,
    enabled: Boolean = true
) {
    val palette = LocalWeekyiiPalette.current
    val shape = RoundedCornerShape(WeekyiiDimensions.radiusExtraLarge)
    val background = when (style) {
        WeekyiiButtonStyle.Primary -> Brush.horizontalGradient(
            listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary)
        )
        WeekyiiButtonStyle.Secondary -> Brush.linearGradient(
            listOf(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
        )
        WeekyiiButtonStyle.Outline -> Brush.linearGradient(
            listOf(Color.Transparent, Color.Transparent)
        )
        WeekyiiButtonStyle.OnGradient -> Brush.linearGradient(
            listOf(palette.onGradient.copy(alpha = 0.20f), palette.onGradient.copy(alpha = 0.20f))
        )
    }
    val foreground = when (style) {
        WeekyiiButtonStyle.Primary -> MaterialTheme.colorScheme.onPrimary
        WeekyiiButtonStyle.Secondary, WeekyiiButtonStyle.Outline -> MaterialTheme.colorScheme.primary
        WeekyiiButtonStyle.OnGradient -> palette.onGradient
    }
    Row(
        modifier = modifier
            .defaultMinSize(minHeight = WeekyiiDimensions.controlHeight)
            .shadow(if (style == WeekyiiButtonStyle.Primary) WeekyiiDimensions.floatingElevation else 0.dp, shape)
            .clip(shape)
            .background(background)
            .then(
                if (style == WeekyiiButtonStyle.Outline) {
                    Modifier.border(WeekyiiDimensions.buttonOutlineWidth, MaterialTheme.colorScheme.primary, shape)
                } else if (style == WeekyiiButtonStyle.OnGradient) {
                    Modifier.border(WeekyiiDimensions.hairline, palette.onGradient.copy(alpha = 0.28f), shape)
                } else Modifier
            )
            .alpha(if (enabled) 1f else 0.46f)
            .clickable(
                enabled = enabled,
                role = Role.Button,
                onClick = onClick
            )
            .padding(horizontal = WeekyiiDimensions.spacingExtraLarge, vertical = WeekyiiDimensions.buttonVerticalPadding),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = foreground)
        }
        Text(
            text = text,
            modifier = if (icon == null) Modifier else Modifier.padding(start = WeekyiiDimensions.spacingSmall),
            color = foreground.copy(alpha = if (enabled) 1f else 0.5f),
            style = MaterialTheme.typography.bodyLarge,
            fontSize = MaterialTheme.typography.bodyLarge.fontSize
        )
    }
}
