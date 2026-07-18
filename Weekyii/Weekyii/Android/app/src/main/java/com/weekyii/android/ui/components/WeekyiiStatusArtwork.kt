package com.weekyii.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.lerp
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.ui.theme.WeekyiiDimensions

@Composable
fun WeekyiiStatusArtwork(
    status: DayStatus,
    modifier: Modifier = Modifier
) {
    val primary = MaterialTheme.colorScheme.primary
    val accent = MaterialTheme.colorScheme.tertiary
    val success = MaterialTheme.colorScheme.secondary
    val neutral = MaterialTheme.colorScheme.onSurfaceVariant
    val (start, end, ground) = when (status) {
        DayStatus.EMPTY -> Triple(lerp(Color.White, primary, 0.34f), lerp(primary, accent, 0.36f), lerp(primary, neutral, 0.46f))
        DayStatus.DRAFT -> Triple(lerp(Color.White, primary, 0.42f), primary, lerp(primary, neutral, 0.40f))
        DayStatus.EXECUTE -> Triple(lerp(Color.White, accent, 0.45f), accent, lerp(accent, neutral, 0.46f))
        DayStatus.COMPLETED -> Triple(lerp(Color.White, success, 0.38f), success, lerp(success, neutral, 0.42f))
        DayStatus.EXPIRED -> Triple(lerp(Color.White, neutral, 0.30f), neutral, lerp(neutral, Color.Black, 0.18f))
    }
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(88.dp)
            .clip(RoundedCornerShape(WeekyiiDimensions.radiusMedium))
            .background(Brush.horizontalGradient(listOf(start, end)))
    ) {
        val groundTop = size.height * 0.64f
        drawRect(ground, topLeft = Offset(0f, groundTop), size = Size(size.width, size.height - groundTop))

        val windowWidth = size.width * 0.28f
        val windowHeight = size.height * 0.72f
        val windowLeft = size.width * 0.52f
        val windowTop = size.height * 0.10f
        drawRoundRect(
            color = Color(0xFFFFE7A9).copy(alpha = 0.84f),
            topLeft = Offset(windowLeft, windowTop),
            size = Size(windowWidth, windowHeight),
            cornerRadius = CornerRadius(windowWidth * 0.25f, windowWidth * 0.25f)
        )
        drawLine(Color.White.copy(alpha = 0.36f), Offset(windowLeft + windowWidth / 2, windowTop + 8f), Offset(windowLeft + windowWidth / 2, windowTop + windowHeight - 8f), 1.5f)
        drawLine(Color.White.copy(alpha = 0.36f), Offset(windowLeft + 8f, windowTop + windowHeight / 2), Offset(windowLeft + windowWidth - 8f, windowTop + windowHeight / 2), 1.5f)

        val tableY = size.height * 0.63f
        drawLine(Color(0xFF6E321B), Offset(size.width * 0.20f, tableY), Offset(size.width * 0.57f, tableY), 3f)
        drawLine(Color(0xFFFFE1B5), Offset(size.width * 0.47f, tableY + 5f), Offset(size.width * 0.67f, tableY + 2f), 4f)
        val arcPath = Path().apply {
            moveTo(size.width * 0.27f, tableY)
            quadraticBezierTo(size.width * 0.37f, tableY - size.height * 0.28f, size.width * 0.47f, tableY)
        }
        drawPath(arcPath, Color(0xFF6E321B), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.5f))
        drawRoundRect(Color(0xFFFFF1B9), Offset(size.width * 0.34f, tableY - size.height * 0.40f), Size(size.width * 0.025f, size.height * 0.22f), CornerRadius(8f, 8f))
    }
}
