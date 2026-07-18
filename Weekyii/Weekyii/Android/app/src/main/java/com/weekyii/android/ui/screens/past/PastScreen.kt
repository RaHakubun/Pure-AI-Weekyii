package com.weekyii.android.ui.screens.past

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.weekyii.android.data.db.entities.DayStatus
import com.weekyii.android.data.db.entities.TaskZone
import com.weekyii.android.ui.model.DayUi
import com.weekyii.android.ui.model.WeekUi
import com.weekyii.android.ui.viewmodel.PastViewModel
import com.weekyii.android.ui.components.WeekyiiCard
import com.weekyii.android.ui.components.WeekyiiEmptyState
import com.weekyii.android.ui.components.WeekyiiHeader
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter

@Composable
fun PastScreen(viewModel: PastViewModel, padding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val summaries = state.monthSummaries.associateBy { it.date }
    val selectedDay = state.monthDays.firstOrNull { it.date == state.selectedDate }
    var showAnalytics by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                PastToolbarButton(
                    icon = if (state.displayMode == PastViewModel.DisplayMode.WEEK_LIST) Icons.Filled.CalendarMonth else Icons.Filled.ViewList,
                    contentDescription = "切换视图",
                    onClick = { viewModel.setDisplayMode(if (state.displayMode == PastViewModel.DisplayMode.WEEK_LIST) PastViewModel.DisplayMode.MONTH else PastViewModel.DisplayMode.WEEK_LIST) }
                )
                WeekyiiHeader(modifier = Modifier.weight(1f))
                androidx.compose.foundation.layout.Spacer(Modifier.size(48.dp))
            }
        }
        item { MonthToolbar(state.selectedMonth, viewModel::previousMonth, viewModel::nextMonth) }
        item { PastStatsCard(state.selectedMonth, state.stats) }
        if (state.displayMode == PastViewModel.DisplayMode.WEEK_LIST) {
            if (state.monthWeeks.isEmpty()) item {
                WeekyiiEmptyState(
                    title = "暂无历史",
                    subtitle = "完成的周将显示在这里。",
                    icon = Icons.Outlined.History
                )
            }
            else items(state.monthWeeks, key = { it.weekId }) { week -> PastWeekCard(week) }
        } else {
            item { PastMonthCalendar(state.selectedMonth, summaries, state.selectedDate, viewModel::selectDate) }
            item { PastSelectedDayCard(selectedDay, state.selectedDate) }
        }
        item { AnalyticsDisclosureCard(showAnalytics, onToggle = { showAnalytics = !showAnalytics }) }
        if (showAnalytics) {
            item { TrendCard(state.trend) }
            item { HeatmapCard(state.heatmap) }
        }
    }
}

@Composable
private fun PastToolbarButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    onClick: () -> Unit
) {
    val shape = CircleShape
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(48.dp)
            .shadow(2.dp, shape)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.08f), shape)
    ) {
        Icon(icon, contentDescription, tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun MonthToolbar(month: YearMonth, onPrevious: () -> Unit, onNext: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Surface(
        modifier = Modifier.fillMaxWidth().height(56.dp).shadow(2.dp, shape),
        shape = shape,
        color = MaterialTheme.colorScheme.surface,
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.12f))
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onPrevious) { Icon(Icons.Filled.ArrowBack, "上个月") }
            Text(
                month.format(DateTimeFormatter.ofPattern("yyyy年M月")),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            IconButton(onClick = onNext) { Icon(Icons.Filled.ArrowForward, "下个月") }
        }
    }
}

@Composable
private fun PastStatsCard(month: YearMonth, stats: PastViewModel.Stats) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.primary) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("本月回顾", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(month.format(DateTimeFormatter.ofPattern("yyyy年M月")), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text("↗", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleLarge)
            }
            val hasHistory = stats.totalCompletedTasks > 0 || stats.totalExpiredTasks > 0 || stats.totalStartedDays > 0
            if (hasHistory) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Stat("完成", stats.totalCompletedTasks)
                    Stat("过期", stats.totalExpiredTasks)
                    Stat("完成率", "${(stats.completionRate * 100).toInt()}%")
                    Stat("启动", stats.totalStartedDays)
                }
                Text("专注 ${formatMinutes(stats.totalFocusMinutes)} · 平均每项 ${stats.averageTaskMinutes} 分钟", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Text("这个月还没有可以回顾的记录。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun AnalyticsDisclosureCard(expanded: Boolean, onToggle: () -> Unit) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("趋势与洞察", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("趋势、热力与效率统计", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(if (expanded) "⌃" else "⌄", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.headlineSmall)
            }
            Text("完成任务保留详情；过期任务仅保留数量。", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Stat(label: String, value: Any) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(value.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

private fun formatMinutes(minutes: Long): String = if (minutes < 60) "${minutes}分钟" else "${minutes / 60}小时${minutes % 60}分"

@Composable
private fun PastWeekCard(week: WeekUi) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(week.weekId, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Text("${week.completedTasksCount} 完成 / ${week.expiredTasksCount} 过期") }
            Text("${week.startDate} ~ ${week.endDate} · 启动 ${week.totalStartedDays} 天", color = MaterialTheme.colorScheme.onSurfaceVariant)
            week.days.sortedBy { it.date }.forEach { day -> Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("${day.dayOfWeek} ${day.date}"); Text(if (day.status == DayStatus.EXPIRED) "过期 ${day.expiredCount} 项" else "完成 ${day.tasks.count { it.zone == TaskZone.COMPLETE }}") } }
        }
    }
}

@Composable
private fun PastMonthCalendar(month: YearMonth, summaries: Map<LocalDate, PastViewModel.MonthDaySummary>, selectedDate: LocalDate, onSelect: (LocalDate) -> Unit) {
    val first = month.atDay(1).minusDays((month.atDay(1).dayOfWeek.value - 1).toLong())
    val last = month.atEndOfMonth().plusDays((7 - month.atEndOfMonth().dayOfWeek.value).toLong())
    val dates = generateSequence(first) { it.plusDays(1) }.takeWhile { !it.isAfter(last) }.toList()
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(modifier = Modifier.fillMaxWidth()) { listOf("一", "二", "三", "四", "五", "六", "日").forEach { Text(it, Modifier.weight(1f), style = MaterialTheme.typography.labelMedium) } }
            dates.chunked(7).forEach { week -> Row(modifier = Modifier.fillMaxWidth()) { week.forEach { date ->
                val summary = summaries[date]; val selected = date == selectedDate
                Column(modifier = Modifier.weight(1f).height(56.dp).padding(2.dp).background(if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .35f)).clickable { onSelect(date) }.padding(4.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(date.dayOfMonth.toString(), style = MaterialTheme.typography.labelLarge, color = if (date.month == month.month) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = .35f))
                    if (summary != null && summary.hasRecord) Text("${summary.completedCount}/${summary.expiredCount}", style = MaterialTheme.typography.labelSmall)
                }
            } } }
        }
    }
}

@Composable
private fun PastSelectedDayCard(day: DayUi?, date: LocalDate) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${date.format(DateTimeFormatter.ofPattern("M月d日"))} 回顾", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            if (day == null || (day.tasks.isEmpty() && day.expiredCount == 0)) Text("当天没有历史记录。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            else { Text("完成 ${day.tasks.count { it.zone == TaskZone.COMPLETE }} · 过期 ${day.expiredCount}"); day.tasks.filter { it.zone == TaskZone.COMPLETE }.forEach { task -> Text("✓ ${task.title}") } }
        }
    }
}

@Composable
private fun TrendCard(points: List<PastViewModel.DayTaskPoint>) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("月趋势", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (points.all { it.completedCount == 0 && it.expiredCount == 0 }) Text("暂无可绘制的任务数据。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            else {
                val max = points.maxOf { it.completedCount + it.expiredCount }.coerceAtLeast(1)
                Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                    points.forEach { point -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        val height = ((point.completedCount + point.expiredCount).toFloat() / max * 100).coerceAtLeast(if (point.completedCount + point.expiredCount > 0) 8f else 2f)
                        Column(modifier = Modifier.height(height.dp).background(if (point.expiredCount > 0) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)) {}
                        Text(point.label, style = MaterialTheme.typography.labelSmall)
                    } }
                }
            }
        }
    }
}

@Composable
private fun HeatmapCard(points: List<PastViewModel.HeatmapPoint>) {
    WeekyiiCard(modifier = Modifier.fillMaxWidth(), accentColor = MaterialTheme.colorScheme.secondary) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("完成热力图", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            points.chunked(7).forEach { week -> Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { week.forEach { point -> androidx.compose.foundation.layout.Box(modifier = Modifier.size(16.dp).background(heatmapColor(point.status))) } } }
            Text("浅色=低完成 · 深色=高完成 · 红色=过期", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun heatmapColor(status: PastViewModel.HeatmapStatus): Color = when (status) {
    PastViewModel.HeatmapStatus.EMPTY -> Color.Gray.copy(alpha = .18f)
    PastViewModel.HeatmapStatus.LOW -> Color(0xFFB7DFC3)
    PastViewModel.HeatmapStatus.MID -> Color(0xFF62B57A)
    PastViewModel.HeatmapStatus.HIGH -> Color(0xFF208B4B)
    PastViewModel.HeatmapStatus.EXPIRED -> Color(0xFFD36B52)
}

@Composable private fun EmptyPastMessage() { Text("这个月还没有过去周记录。", color = MaterialTheme.colorScheme.onSurfaceVariant) }
