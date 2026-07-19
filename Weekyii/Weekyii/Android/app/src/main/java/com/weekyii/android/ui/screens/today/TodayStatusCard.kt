package com.weekyii.android.ui.screens.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.ui.components.StatusBadge
import com.weekyii.android.ui.components.WeekyiiCard
import com.weekyii.android.ui.components.WeekyiiStatusArtwork
import com.weekyii.android.ui.theme.WeekyiiDimensions
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable
fun TodayStatusCard(
    status: DayStatus,
    daysStartedCount: Int,
    date: LocalDate,
    modifier: Modifier = Modifier
) {
    WeekyiiCard(modifier = modifier, accentColor = statusAccentColor(status)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(WeekyiiDimensions.spacingSmall)) {
                Text("状态", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                StatusBadge(
                    text = statusLabel(status),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    contentPadding = PaddingValues(horizontal = WeekyiiDimensions.spacingMedium, vertical = 7.dp)
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("已启动天数", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(daysStartedCount.toString(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            }
        }
        Spacer(Modifier.height(WeekyiiDimensions.spacingBase))
        WeekyiiStatusArtwork(status)
        Spacer(Modifier.height(WeekyiiDimensions.spacingBase))
        Text(date.format(DateTimeFormatter.ofPattern("yyyy年M月d日")), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun statusLabel(status: DayStatus): String = when (status) {
    DayStatus.EMPTY -> "空"
    DayStatus.DRAFT -> "草稿"
    DayStatus.EXECUTE -> "执行中"
    DayStatus.COMPLETED -> "已完成"
    DayStatus.EXPIRED -> "已过期"
}

@Composable
private fun statusAccentColor(status: DayStatus): Color = when (status) {
    DayStatus.EMPTY -> MaterialTheme.colorScheme.outline
    DayStatus.DRAFT -> MaterialTheme.colorScheme.primary
    DayStatus.EXECUTE -> MaterialTheme.colorScheme.tertiary
    DayStatus.COMPLETED -> MaterialTheme.colorScheme.secondary
    DayStatus.EXPIRED -> MaterialTheme.colorScheme.error
}
